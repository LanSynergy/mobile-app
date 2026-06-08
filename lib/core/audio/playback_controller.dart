import 'dart:async';

import 'package:flutter/foundation.dart' show VoidCallback, visibleForTesting;
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../../utils/log.dart';
import '../jellyfin/models/items.dart';
import 'artwork_manager.dart';
import 'async_lock.dart';
import 'audio_device_manager.dart';
import 'auth_headers_manager.dart';
import 'loop_mode_manager.dart';
import 'media_session_bridge.dart';
import 'player_settings_store.dart';
import 'position_tracker.dart';
import 'queue_manager.dart';
import 'stream_prefetcher.dart';
import 'stream_url_cache.dart';
import 'spectrum_settings.dart';

/// Orchestrates core playback operations: play, pause, seek, skip, queue
/// loading, track transitions, prefetch, and media-session state updates.
///
/// This is an internal implementation detail of [AfPlayerService].
/// It owns the orchestration logic and mutable playback state while the
/// service provides the public API surface and stream wiring.
class PlaybackController {
  PlaybackController({
    required PlayerApi player,
    required AfQueueManager queueManager,
    required AfPositionTracker positionTracker,
    required AfArtworkManager artworkManager,
    required AfAudioDeviceManager audioDeviceManager,
    required StreamPrefetcher prefetcher,
    required StreamUrlCache streamUrlCache,
    required AfAsyncLock queueLock,
    required LoopModeManager loopModeManager,
    required AuthHeadersManager authHeadersManager,
    required NativeMediaSessionBridge bridge,
  }) : _player = player,
       _queueManager = queueManager,
       _positionTracker = positionTracker,
       _artworkManager = artworkManager,
       _audioDeviceManager = audioDeviceManager,
       _prefetcher = prefetcher,
       _streamUrlCache = streamUrlCache,
       _queueLock = queueLock,
       _loopModeManager = loopModeManager,
       _authHeadersManager = authHeadersManager,
       _bridge = bridge;

  final PlayerApi _player;
  final AfQueueManager _queueManager;
  final AfPositionTracker _positionTracker;
  final AfArtworkManager _artworkManager;
  final AfAudioDeviceManager _audioDeviceManager;
  final StreamPrefetcher _prefetcher;
  final StreamUrlCache _streamUrlCache;
  final AfAsyncLock _queueLock;
  final LoopModeManager _loopModeManager;
  final AuthHeadersManager _authHeadersManager;
  final NativeMediaSessionBridge _bridge;

  bool _disposed = false;

  set disposedForTesting(bool value) => _disposed = value;

  // ── Mutable playback state ───────────────────────────────────────

  String? _prefetchStartedForTrackId;
  bool _prefetchPlaylistEnabled = true;

  /// Guards against re-processing a `completed` event for the same track.
  String? _completedHandledForTrackId;

  /// Guards against re-processing a track completion via the EOF fallback.
  String? _eofFallbackHandledTrackId;

  /// The ID of the track currently loaded in the mpv player.
  String? _mpvLoadedTrackId;

  Duration? _lastPosition;
  Duration _listenedDuration = Duration.zero;

  /// Returns the accumulated continuous listen duration for the active track.
  Duration get listenedDuration => _listenedDuration;

  /// Tracks last-applied spectrum settings to avoid redundant native calls.
  SpectrumSettings? _lastSpectrumSettings;

  int _lastMediaSessionUpdateMs = 0;
  int _lastQSPositionPushMs = 0;
  bool _lastEffectivePlaying = false;

  /// Stored from [playQueue] so [skipToQueueItem] and the completed handler
  /// can lazily resolve stream URLs when rebuilding the 2-track window.
  FutureOr<String> Function(AfTrack)? _resolveStreamUrl;

  // ── Callbacks ───────────────────────────────────────────────────

  void Function(AfTrack? track)? onTrackChanged;
  void Function(String? trackId)? onMpvLoadedTrackChanged;
  void Function(AfTrack track)? onTrackCompleted;
  void Function(AfTrack track)? onTrackSkipped;
  Future<List<AfTrack>> Function(AfTrack lastTrack)? onGetSimilarTracks;
  VoidCallback? onToggleFavorite;
  void Function(bool enabled)? onForNtimesChanged;
  void Function(Uri?)? onArtworkUpdated;
  void Function(AudioOutputState state)? onAudioOutputFailed;

  // ── Cached stream URL helpers ───────────────────────────────────

  String? _getCachedStreamUrl(String trackId) => _streamUrlCache.get(trackId);
  void _cacheStreamUrl(String trackId, String url) =>
      _streamUrlCache.put(trackId, url);

  void _clearStreamUrlCache() => _streamUrlCache.clear();

  // ── Auth header convenience ─────────────────────────────────────

  Map<String, String> get _authHeaders => _authHeadersManager.headers;

  // ── Loop mode convenience ───────────────────────────────────────

  Loop get loopMode => _loopModeManager.mode;

  // ── Track lifecycle helper ──────────────────────────────────────

  void _onTrackChangedOrRestarted() {
    _positionTracker.onTrackChanged();
    _listenedDuration = Duration.zero;
    _lastPosition = null;
    _artworkManager.persistCover(null);
  }

  // ---------------------------------------------------------------------------
  // Playback control
  // ---------------------------------------------------------------------------

  void setAuthHeaders(Map<String, String> headers) {
    _authHeadersManager.setHeaders(headers);
    _artworkManager.setAuthHeaders(headers);
  }

  Future<void> playQueue(
    List<AfTrack> tracks, {
    int startIndex = 0,
    required FutureOr<String> Function(AfTrack track) resolveStreamUrl,
    Map<String, String> streamHeaders = const <String, String>{},
  }) async {
    if (tracks.isEmpty) return;

    _resolveStreamUrl = resolveStreamUrl;
    _prefetcher.cancelCurrentPrefetch();
    _prefetchStartedForTrackId = null;
    _completedHandledForTrackId = null;
    _eofFallbackHandledTrackId = null;
    _mpvLoadedTrackId = null;
    onMpvLoadedTrackChanged?.call(null);

    if (streamHeaders.isNotEmpty) {
      _authHeadersManager.setHeaders(streamHeaders);
      _artworkManager.setAuthHeaders(streamHeaders);
    }

    final safeIndex = startIndex.clamp(0, tracks.length - 1);
    _queueManager.replaceQueue(tracks, safeIndex);

    final startTrack = tracks[safeIndex];
    _queueManager.emitCurrentTrack(startTrack);
    onTrackChanged?.call(startTrack);
    afLog(
      'data',
      'playQueue source=live size=${tracks.length} '
          'startIndex=$safeIndex first="${startTrack.title}"',
    );

    final cachedFile = await _prefetcher.getCachedFile(startTrack.id);
    final String url;
    if (cachedFile != null) {
      url = cachedFile.uri.toString();
      afLog(
        'audio',
        'playQueue: using prefetched file for "${startTrack.title}"',
      );
    } else {
      final cachedUrl = _getCachedStreamUrl(startTrack.id);
      if (cachedUrl != null) {
        url = cachedUrl;
        afLog(
          'audio',
          'playQueue: using cached stream URL for "${startTrack.title}"',
        );
      } else {
        url = await resolveStreamUrl(startTrack);
        _cacheStreamUrl(startTrack.id, url);
      }
    }
    final medias = <Media>[
      Media(url, httpHeaders: _authHeaders.isNotEmpty ? _authHeaders : null),
    ];
    afLog(
      'aetherfin:youtube',
      'playQueue: url=${url.length > 80 ? url.substring(0, 80) : url}...',
    );

    return _queueLock.run(() async {
      try {
        _onTrackChangedOrRestarted();

        await _player.openAll(medias, index: 0, play: true);
        _mpvLoadedTrackId = startTrack.id;
        onMpvLoadedTrackChanged?.call(_mpvLoadedTrackId);

        _audioDeviceManager.nudge();
      } on Exception catch (e, stack) {
        afLog(
          'aetherfin:error',
          'playQueue failed',
          error: e,
          stackTrace: stack,
        );
        _queueManager.clear();
        _mpvLoadedTrackId = null;
        onMpvLoadedTrackChanged?.call(null);
        try {
          await _player.stop();
        } on Exception catch (err, st) {
          afLog(
            'audio',
            'stop failed on playQueue cleanup',
            error: err,
            stackTrace: st,
          );
        }
        rethrow;
      }
    });
  }

  Future<void> play() async {
    if (_disposed) return;
    _positionTracker.onPlay();
    try {
      await _player.play();
      _audioDeviceManager.nudge();
    } on Exception catch (e, stack) {
      afLog('audio', 'play failed', error: e, stackTrace: stack);
    }
  }

  Future<void> pause() async {
    if (_disposed) return;
    _positionTracker.onPause();
    try {
      await _player.pause();
    } on Exception catch (e, stack) {
      afLog('audio', 'pause failed', error: e, stackTrace: stack);
    }
  }

  Future<void> stop() async {
    if (_disposed) return;
    _positionTracker.onStop();
    _listenedDuration = Duration.zero;
    _lastPosition = null;
    _prefetcher.cancelCurrentPrefetch();
    _prefetchStartedForTrackId = null;
    _mpvLoadedTrackId = null;
    onMpvLoadedTrackChanged?.call(null);
    _eofFallbackHandledTrackId = null;
    _clearStreamUrlCache();
    try {
      await _player.stop();
    } on Exception catch (e, stack) {
      afLog('audio', 'stop failed', error: e, stackTrace: stack);
    }
  }

  Future<void> stopAndClear() async {
    if (_disposed) return;
    _positionTracker.onStop();
    _listenedDuration = Duration.zero;
    _lastPosition = null;
    _prefetcher.cancelCurrentPrefetch();
    _prefetchStartedForTrackId = null;
    _mpvLoadedTrackId = null;
    onMpvLoadedTrackChanged?.call(null);
    _eofFallbackHandledTrackId = null;
    try {
      await _player.stop();
    } on Exception catch (e, stack) {
      afLog(
        'audio',
        'stop failed in stopAndClear',
        error: e,
        stackTrace: stack,
      );
    }
    _queueManager.clear();
    onTrackChanged?.call(null);
    updateMediaSession();
  }

  Future<void> seek(Duration position) async {
    if (_disposed) return;
    _positionTracker.onSeek(position);
    if (position == Duration.zero) {
      _listenedDuration = Duration.zero;
      _lastPosition = null;
    } else {
      _lastPosition = position;
    }
    try {
      await _player.seek(position);
      updateMediaSession();
      _audioDeviceManager.nudge();
    } on Exception catch (e, stack) {
      afLog('audio', 'seek failed', error: e, stackTrace: stack);
    }
  }

  Future<void> seekToPercent(
    double percent, {
    bool relative = false,
    bool exact = false,
  }) async {
    if (_disposed) return;
    final clamped = percent.clamp(0.0, 100.0);
    try {
      await _player.seekToPercent(clamped, relative: relative, exact: exact);
      updateMediaSession();
      _audioDeviceManager.nudge();
    } on Exception catch (e, stack) {
      afLog('audio', 'seekToPercent failed', error: e, stackTrace: stack);
    }
  }

  Future<void> revertSeek() async {
    if (_disposed) return;
    try {
      await _player.revertSeek();
      updateMediaSession();
    } on Exception catch (e, stack) {
      afLog('audio', 'revertSeek failed', error: e, stackTrace: stack);
    }
  }

  Future<void> skipToNext() async {
    if (_disposed) return;
    if (_queueManager.engine.isAtQueueEnd &&
        _loopModeManager.mode != Loop.playlist) {
      return;
    }

    _positionTracker.onStop();
    try {
      await _player.stop();
    } on Exception catch (e) {
      afLog('audio', 'Failed to stop player during skipToNext', error: e);
    }

    final wasPlaying = _queueManager.currentTrack;
    _completedHandledForTrackId = null;
    _eofFallbackHandledTrackId = null;
    _mpvLoadedTrackId = null;
    onMpvLoadedTrackChanged?.call(null);
    if (wasPlaying != null) {
      onTrackSkipped?.call(wasPlaying);
    }
    _queueManager.engine.advanceIndex();
    _queueManager.engine.resetRepeats();
    final nextTrack = _queueManager.currentTrack;
    if (nextTrack == null) {
      return;
    }

    _onTrackChangedOrRestarted();
    _queueManager.emitCurrentTrack(nextTrack);
    onTrackChanged?.call(nextTrack);
    updateMediaSession();
    unawaited(_reconfigureSpectrumOnTrackChange());

    try {
      await _rebuildWindow(nextTrack);
      updateMediaSession();
    } on Exception catch (e, stack) {
      afLog('audio', 'skipToNext failed', error: e, stackTrace: stack);
    }
  }

  Future<void> skipToPrevious() async {
    if (_disposed) return;

    _positionTracker.onStop();
    try {
      await _player.stop();
    } on Exception catch (e) {
      afLog('audio', 'Failed to stop player during skipToPrevious', error: e);
    }

    final wasPlaying = _queueManager.currentTrack;
    _completedHandledForTrackId = null;
    _eofFallbackHandledTrackId = null;
    _mpvLoadedTrackId = null;
    onMpvLoadedTrackChanged?.call(null);
    if (wasPlaying != null) {
      onTrackSkipped?.call(wasPlaying);
    }
    _queueManager.engine.retreatIndex();
    _queueManager.engine.resetRepeats();
    final prevTrack = _queueManager.currentTrack;
    if (prevTrack == null) {
      return;
    }

    _onTrackChangedOrRestarted();
    _queueManager.emitCurrentTrack(prevTrack);
    onTrackChanged?.call(prevTrack);
    updateMediaSession();
    unawaited(_reconfigureSpectrumOnTrackChange());

    try {
      await _rebuildWindow(prevTrack);
      updateMediaSession();
    } on Exception catch (e, stack) {
      afLog('audio', 'skipToPrevious failed', error: e, stackTrace: stack);
    }
  }

  Future<void> skipToQueueItem(int index) async {
    if (_disposed) return;

    _positionTracker.onStop();
    try {
      await _player.stop();
    } on Exception catch (e) {
      afLog('audio', 'Failed to stop player during skipToQueueItem', error: e);
    }

    final wasPlaying = _queueManager.currentTrack;
    _completedHandledForTrackId = null;
    _eofFallbackHandledTrackId = null;
    _mpvLoadedTrackId = null;
    onMpvLoadedTrackChanged?.call(null);
    if (wasPlaying != null) {
      onTrackSkipped?.call(wasPlaying);
    }
    _queueManager.engine.jumpTo(index);
    _queueManager.engine.resetRepeats();
    final targetTrack = _queueManager.currentTrack;
    if (targetTrack == null) {
      return;
    }

    _onTrackChangedOrRestarted();
    _queueManager.emitCurrentTrack(targetTrack);
    onTrackChanged?.call(targetTrack);
    updateMediaSession();
    unawaited(_reconfigureSpectrumOnTrackChange());

    try {
      await _rebuildWindow(targetTrack);
      updateMediaSession();
    } on Exception catch (e, stack) {
      afLog('audio', 'skipToQueueItem failed', error: e, stackTrace: stack);
    }
  }

  // ---------------------------------------------------------------------------
  // Shuffle / Loop / forNtimes
  // ---------------------------------------------------------------------------

  Future<void> setAfShuffleTail() async {
    if (_disposed) return;
    if (_queueManager.currentQueue.isEmpty) return;
    _queueManager.shuffleTail();
    afLog(
      'data',
      'shuffleTail source=live '
          'queueSize=${_queueManager.currentQueue.length}',
    );
  }

  Future<void> setAfShuffleMode(bool enabled) async {
    if (_disposed) return;
    if (_queueManager.isShuffleEnabled == enabled) return;

    await _queueLock.run(() async {
      _queueManager.setShuffle(enabled);
    });
    unawaited(PlayerSettingsStore.saveShuffleEnabled(enabled));

    afLog(
      'data',
      'shuffleMode source=live enabled=$enabled '
          'queueSize=${_queueManager.currentQueue.length} '
          'currentIndex=${_queueManager.currentIndex}',
    );
    updateMediaSession();
  }

  Future<void> setAfLoopMode(Loop mode) async {
    if (_disposed) return;
    return _queueLock.run(() async {
      try {
        _loopModeManager.setMode(mode);
        afLog('data', 'loopMode source=live mode=${mode.name}');
        updateMediaSession();
      } on Exception catch (e, stack) {
        afLog('audio', 'setAfLoopMode failed', error: e, stackTrace: stack);
      }
    });
  }

  Future<void> setAfForNtimes(bool enabled) async {
    if (_disposed) return;
    _queueManager.engine.setForNtimes(enabled);
    onForNtimesChanged?.call(enabled);
    updateMediaSession();
    afLog(
      'data',
      'forNtimes source=live enabled=$enabled '
          'ntimesCount=${_queueManager.engine.ntimesCount}',
    );
  }

  Future<void> setAfNtimesCount(int count) async {
    if (_disposed) return;
    _queueManager.engine.setNtimesCount(count);
    afLog('data', 'forNtimesCount source=live count=$count');
  }

  void setLoopModeOffSync() => _loopModeManager.setOffSync();

  /// Set playback speed. Intentionally bypasses [_queueLock] because
  /// `setRate` is a simple mpv property setter.
  Future<void> setAfSpeed(double speed) async {
    if (_disposed) return;
    await _player.setRate(speed);
    afLog('data', 'playbackSpeed source=live speed=$speed');
  }

  // ---------------------------------------------------------------------------
  // Queue management
  // ---------------------------------------------------------------------------

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (_disposed) return;
    final queueSize = _queueManager.currentQueue.length;
    if (oldIndex < 0 ||
        oldIndex >= queueSize ||
        newIndex < 0 ||
        newIndex >= queueSize) {
      afLog(
        'audio',
        'reorderQueue refused — index out of bounds: '
            'old=$oldIndex new=$newIndex size=$queueSize',
      );
      return;
    }
    if (!_queueManager.canReorder(oldIndex, newIndex)) return;

    await _queueLock.run(() async {
      _queueManager.reorder(oldIndex, newIndex);
    });
    afLog(
      'audio',
      'reorderQueue oldIndex=$oldIndex newIndex=$newIndex '
          'currentIndex=${_queueManager.currentIndex} '
          'queueSize=${_queueManager.currentQueue.length}',
    );
  }

  Future<bool> removeFromQueue(int index) async {
    if (_disposed) return false;
    final queueSize = _queueManager.currentQueue.length;
    if (index < 0 || index >= queueSize) {
      afLog(
        'audio',
        'removeFromQueue refused — index out of bounds: '
            'index=$index size=$queueSize',
      );
      return false;
    }
    if (!_queueManager.canRemove(index)) {
      afLog(
        'audio',
        'removeFromQueue refused index=$index (currently playing)',
      );
      return false;
    }

    await _queueLock.run(() async {
      _queueManager.remove(index);
    });
    afLog(
      'audio',
      'removeFromQueue index=$index '
          'currentIndex=${_queueManager.currentIndex} '
          'queueSize=${_queueManager.currentQueue.length}',
    );
    return true;
  }

  Future<void> insertIntoQueue(
    int index,
    AfTrack track, {
    required FutureOr<String> Function(AfTrack) resolveStreamUrl,
  }) async {
    if (_disposed) return;
    _resolveStreamUrl = resolveStreamUrl;
    await _queueLock.run(() async {
      _queueManager.insert(index, track);
    });
    afLog(
      'audio',
      'insertIntoQueue "${track.title}" at index=$index '
          'currentIndex=${_queueManager.currentIndex}',
    );
  }

  Future<void> playNext(
    AfTrack track, {
    required FutureOr<String> Function(AfTrack) resolveStreamUrl,
  }) async {
    if (_disposed) return;
    _resolveStreamUrl = resolveStreamUrl;
    await _queueLock.run(() async {
      _queueManager.engine.insert(
        _queueManager.currentIndex >= 0
            ? _queueManager.currentIndex + 1
            : _queueManager.currentQueue.length,
        track,
      );
      _queueManager.emitQueue();
    });
    afLog('audio', 'playNext "${track.title}"');
  }

  Future<void> addToQueue(
    AfTrack track, {
    required FutureOr<String> Function(AfTrack) resolveStreamUrl,
  }) async {
    if (_disposed) return;
    _resolveStreamUrl = resolveStreamUrl;
    await _queueLock.run(() async {
      _queueManager.engine.append(track);
      _queueManager.emitQueue();
    });
    afLog('audio', 'addToQueue "${track.title}" at end');
  }

  Future<void> appendQueue(
    List<AfTrack> tracks, {
    required FutureOr<String> Function(AfTrack) resolveStreamUrl,
  }) async {
    if (_disposed || tracks.isEmpty) return;
    _resolveStreamUrl = resolveStreamUrl;
    await _queueLock.run(() async {
      _queueManager.appendAll(tracks);
    });
    afLog('audio', 'appendQueue added ${tracks.length} tracks at end');
  }

  // ---------------------------------------------------------------------------
  // Spectrum / prefetch
  // ---------------------------------------------------------------------------

  Future<void> setPrefetchPlaylist(bool enabled) async {
    if (_disposed) return;
    _prefetchPlaylistEnabled = enabled;
    if (!enabled) {
      _prefetcher.dispose();
    }
    afLog('audio', 'prefetchPlaylist=$enabled');
  }

  bool get prefetchPlaylist => _prefetchPlaylistEnabled;

  Future<void> configureSpectrum() async {
    try {
      await _player.setSpectrum(defaultSpectrumSettings);
    } on Exception catch (e, stack) {
      afLog('audio', 'configureSpectrum failed', error: e, stackTrace: stack);
    }
  }

  Future<void> _reconfigureSpectrumOnTrackChange() async {
    if (_disposed) return;
    try {
      await Future.delayed(const Duration(milliseconds: 250));
      if (_disposed) return;
      if (_lastSpectrumSettings == defaultSpectrumSettings) return;
      await _player.setSpectrum(defaultSpectrumSettings);
      _lastSpectrumSettings = defaultSpectrumSettings;
      afLog('audio', 'spectrum re-configured after track change');
    } on Exception catch (e, stack) {
      afLog(
        'audio',
        'reconfigureSpectrumOnTrackChange failed',
        error: e,
        stackTrace: stack,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Autoplay queue cap
  // ---------------------------------------------------------------------------

  static const int _maxAutoplayQueueSize = 500;

  void _trimAutoplayedTracks() {
    final queue = _queueManager.currentQueue;
    final idx = _queueManager.currentIndex;
    if (queue.length <= _maxAutoplayQueueSize || idx <= 0) return;
    final excess = queue.length - _maxAutoplayQueueSize;
    final trimCount = excess < idx ? excess : idx - 1;
    if (trimCount <= 0) return;
    for (var i = 0; i < trimCount; i++) {
      _queueManager.remove(0);
    }
    afLog(
      'audio',
      'trimAutoplayedTracks: removed $trimCount old tracks, '
          'queueSize=${_queueManager.currentQueue.length}',
    );
  }

  // ---------------------------------------------------------------------------
  // 2-track window management
  // ---------------------------------------------------------------------------

  Future<void> _rebuildWindow(AfTrack target) async {
    if (_resolveStreamUrl == null) return;

    _prefetcher.cancelCurrentPrefetch();
    _prefetchStartedForTrackId = null;

    final cachedFile = await _prefetcher.getCachedFile(target.id);
    final String url;
    if (cachedFile != null) {
      url = cachedFile.uri.toString();
      afLog(
        'audio',
        'rebuildWindow: using prefetched file for "${target.title}"',
      );
    } else {
      final cachedUrl = _getCachedStreamUrl(target.id);
      if (cachedUrl != null) {
        url = cachedUrl;
        afLog(
          'audio',
          'rebuildWindow: using cached stream URL for "${target.title}"',
        );
      } else {
        url = await _resolveStreamUrl!(target);
        _cacheStreamUrl(target.id, url);
      }
    }

    try {
      await _player.openAll(
        [
          Media(
            url,
            httpHeaders: _authHeaders.isNotEmpty ? _authHeaders : null,
          ),
        ],
        index: 0,
        play: true,
      );
      _mpvLoadedTrackId = target.id;
      onMpvLoadedTrackChanged?.call(_mpvLoadedTrackId);
    } on Exception catch (_) {
      _mpvLoadedTrackId = null;
      onMpvLoadedTrackChanged?.call(null);
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Track advancement + completion handling
  // ---------------------------------------------------------------------------

  Future<void> _advanceToNextTrack() async {
    _queueManager.engine.advanceIndex();
    _onTrackChangedOrRestarted();

    final current = _queueManager.currentTrack;
    if (current != null) {
      _queueManager.emitCurrentTrack(current);
      onTrackChanged?.call(current);
      unawaited(Future.microtask(() => onTrackCompleted?.call(current)));
    }
    updateMediaSession();
    unawaited(_reconfigureSpectrumOnTrackChange());

    if (current != null) {
      await _rebuildWindow(current);
      if (!_player.state.playing && _player.state.playWhenReady) {
        try {
          await _player.play();
        } on Exception catch (e, stack) {
          afLog(
            'audio',
            'advance: play() guard failed',
            error: e,
            stackTrace: stack,
          );
        }
      }
      updateMediaSession();
    }
  }

  /// Position-based EOF fallback detection.
  void checkEndOfTrackFallback(Duration pos) {
    final currentTrack = _queueManager.currentTrack;
    if (currentTrack == null) return;
    if (_completedHandledForTrackId == currentTrack.id) return;
    if (_eofFallbackHandledTrackId == currentTrack.id) return;

    final duration = _player.state.duration;
    if (duration <= Duration.zero) return;
    if (pos < duration - const Duration(milliseconds: 500)) return;
    if (_player.state.playing) return;

    afLog(
      'audio',
      'EOF fallback triggered for track "${currentTrack.id}" '
          'pos=${pos.inMilliseconds}ms duration=${duration.inMilliseconds}ms',
    );

    unawaited(
      _queueLock.run(() async {
        if (_eofFallbackHandledTrackId == currentTrack.id) return;
        _eofFallbackHandledTrackId = currentTrack.id;
        await _advanceToNextTrack();
      }),
    );
  }

  // ---------------------------------------------------------------------------
  // Prefetch
  // ---------------------------------------------------------------------------

  void checkPrefetch(Duration pos) {
    if (!_prefetchPlaylistEnabled) return;
    final currentTrack = _queueManager.currentTrack;
    final nextTrack = _queueManager.engine.nextTrack;
    if (currentTrack != null &&
        nextTrack != null &&
        _prefetchStartedForTrackId != currentTrack.id) {
      final duration = _player.state.duration;
      if (duration > Duration.zero &&
          duration - pos <= const Duration(seconds: 3)) {
        _prefetchStartedForTrackId = currentTrack.id;
        final cachedUrl = _getCachedStreamUrl(nextTrack.id);
        if (cachedUrl != null) {
          unawaited(
            _prefetcher.prefetch(
              cachedUrl,
              _authHeaders,
              trackId: nextTrack.id,
            ),
          );
        } else {
          final resolved = _resolveStreamUrl?.call(nextTrack);
          if (resolved is Future<String>) {
            resolved.then((nextUrl) {
              _cacheStreamUrl(nextTrack.id, nextUrl);
              unawaited(
                _prefetcher.prefetch(
                  nextUrl,
                  _authHeaders,
                  trackId: nextTrack.id,
                ),
              );
            });
          } else if (resolved is String) {
            _cacheStreamUrl(nextTrack.id, resolved);
            unawaited(
              _prefetcher.prefetch(
                resolved,
                _authHeaders,
                trackId: nextTrack.id,
              ),
            );
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Completed handler (extracted from _bindStreams)
  // ---------------------------------------------------------------------------

  Future<void> handleCompleted(bool completed) async {
    try {
      if (_disposed) return;
      if (!completed) return;

      final currentTrackId = _queueManager.currentTrack?.id;
      if (currentTrackId == null || _mpvLoadedTrackId != currentTrackId) {
        afLog(
          'audio',
          'completed event ignored: currentTrackId=$currentTrackId, '
              'mpvLoadedTrackId=$_mpvLoadedTrackId (mismatch or null)',
        );
        return;
      }

      final loopAtEvent = _loopModeManager.mode;
      final playingAtEvent = _player.state.playing;

      if (_completedHandledForTrackId == currentTrackId) {
        afLog(
          'audio',
          'completed event ignored: already handled for '
              'track "$currentTrackId"',
        );
        return;
      }

      await _queueLock.run(() async {
        if (_disposed) return;

        if (loopAtEvent == Loop.file) {
          _onTrackChangedOrRestarted();
          try {
            await _player.seek(Duration.zero);
            if (!_player.state.playing) {
              await _player.play();
            }
          } on Exception catch (e, stack) {
            afLog(
              'audio',
              'Loop.file restart failed, rebuilding window',
              error: e,
              stackTrace: stack,
            );
            final track = _queueManager.currentTrack;
            if (track != null) {
              await _rebuildWindow(track);
            }
          }
          updateMediaSession();
          afLog('audio', 'Loop.file — restarted current track');
          return;
        }

        if (loopAtEvent == Loop.off &&
            _queueManager.engine.isForNtimes &&
            _queueManager.engine.remainingRepeats > 0) {
          _queueManager.engine.decrementRepeats();
          afLog(
            'audio',
            'forNtimes: restarting track, '
                '${_queueManager.engine.remainingRepeats} repeats remaining',
          );
          try {
            _onTrackChangedOrRestarted();
            await _player.seek(Duration.zero);
            if (!playingAtEvent) {
              await _player.play();
            }
          } on Exception catch (e, stack) {
            afLog(
              'audio',
              'forNtimes: seek(0) failed',
              error: e,
              stackTrace: stack,
            );
          }
          updateMediaSession();
          return;
        }

        _completedHandledForTrackId = currentTrackId;

        if (!_queueManager.engine.isAtQueueEnd) {
          await _advanceToNextTrack();
        } else {
          var autoplayTriggered = false;
          if (loopAtEvent == Loop.off && onGetSimilarTracks != null) {
            final lastTrack = _queueManager.currentTrack;
            if (lastTrack != null) {
              _trimAutoplayedTracks();

              try {
                final similar = await onGetSimilarTracks!(lastTrack);
                if (similar.isNotEmpty) {
                  for (final t in similar) {
                    _queueManager.engine.append(t);
                  }
                  _queueManager.emitQueue();

                  await _advanceToNextTrack();
                  autoplayTriggered = true;
                }
              } on Exception catch (e, stack) {
                afLog(
                  'audio',
                  'autoplay check failed',
                  error: e,
                  stackTrace: stack,
                );
              }
            }
          }

          if (!autoplayTriggered) {
            switch (loopAtEvent) {
              case Loop.off:
                _positionTracker.onStop();
                _mpvLoadedTrackId = null;
                try {
                  await _player.stop();
                } on Exception catch (e, stack) {
                  afLog(
                    'audio',
                    'stop failed on queue completion',
                    error: e,
                    stackTrace: stack,
                  );
                }
                _queueManager.endPlayback();
                onTrackChanged?.call(null);
                updateMediaSession();
                afLog('audio', 'queue end, auto-stop (loop=off)');

              case Loop.playlist:
                _queueManager.engine.jumpTo(0);
                _onTrackChangedOrRestarted();
                final track = _queueManager.currentTrack;
                if (track != null) {
                  await _rebuildWindow(track);
                }
                updateMediaSession();
                afLog('audio', 'queue end, looping playlist');
              case Loop.file:
                _onTrackChangedOrRestarted();
                try {
                  await _player.seek(Duration.zero);
                  if (!_player.state.playing) {
                    await _player.play();
                  }
                } on Exception catch (e, stack) {
                  afLog(
                    'audio',
                    'Loop.file fallback restart failed',
                    error: e,
                    stackTrace: stack,
                  );
                }
                afLog('audio', 'queue end, loop=file — restarted (fallback)');
            }
          }
        }
      });
    } on Exception catch (e, stack) {
      afLog('audio', 'completed handler failed', error: e, stackTrace: stack);
    }
  }

  // ---------------------------------------------------------------------------
  // Media session update
  // ---------------------------------------------------------------------------

  /// Push the current state to the OS media session and the legacy bridge.
  ///
  /// Throttled to ~100ms at the entry point so metadata construction
  /// doesn't run at 30–60 Hz from position stream events.
  void updateMediaSession() {
    if (_disposed) return;
    final track = _queueManager.currentTrack;
    if (track == null) {
      _player.setMediaSession(null);
      _bridge.clear();
      return;
    }

    final s = _player.state;
    final isQueueEnd = s.completed && _queueManager.isAtQueueEnd;
    final trackEnded =
        _player.state.playWhenReady &&
        _queueManager.isAtQueueEnd &&
        s.duration > Duration.zero &&
        _positionTracker.lastKnownPosition >= s.duration;
    final effectivePlaying = (isQueueEnd || trackEnded)
        ? false
        : (s.playing || _shouldAdvancePosition());

    final playingChanged = effectivePlaying != _lastEffectivePlaying;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (!playingChanged && nowMs - _lastMediaSessionUpdateMs < 100) return;
    _lastMediaSessionUpdateMs = nowMs;
    _lastEffectivePlaying = effectivePlaying;

    final effectiveDuration = s.duration > Duration.zero
        ? s.duration
        : track.duration;

    final artUri = _artworkManager.artUri(track);
    final artPath = artUri != null && artUri.isScheme('file')
        ? artUri.toFilePath()
        : null;

    onArtworkUpdated?.call(artUri);

    final loopModeStr = _queueManager.engine.isForNtimes
        ? 'ntimes'
        : switch (_loopModeManager.mode) {
            Loop.file => 'one',
            Loop.playlist => 'all',
            Loop.off => 'off',
          };

    final artwork = artUri != null
        ? MediaSessionArtwork.uri(artUri)
        : MediaSessionArtwork.none;

    _player.setMediaSession(
      (s.mediaSession ?? const MediaSession()).copyWith(
        title: track.title,
        artist: track.artistName,
        album: track.albumName,
        duration: effectiveDuration,
        artwork: artwork,
        isFavorite: track.isFavorite,
      ),
    );

    _bridge.pushState(
      MediaSessionState(
        playing: effectivePlaying,
        buffering: s.buffering,
        position: _positionTracker.lastKnownPosition,
        duration: effectiveDuration,
        speed: effectivePlaying ? s.rate : 0.0,
        title: track.title,
        artist: track.artistName,
        album: track.albumName,
        artPath: artPath,
        queueIndex: _queueManager.currentIndex >= 0
            ? _queueManager.currentIndex
            : null,
        queueSize: _queueManager.currentQueue.length,
        needsArtworkDownload:
            artUri == null && _artworkManager.needsRemoteArtwork(track),
        shuffleEnabled: _queueManager.isShuffleEnabled,
        loopMode: loopModeStr,
        isFavorite: track.isFavorite,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Position listener helpers (called from _bindStreams in the service)
  // ---------------------------------------------------------------------------

  void onPositionTick(Duration pos) {
    checkPrefetch(pos);
    checkEndOfTrackFallback(pos);
    final last = _lastPosition;
    _lastPosition = pos;
    if (last != null && _player.state.playing) {
      final delta = pos - last;
      if (delta > Duration.zero && delta < const Duration(milliseconds: 1200)) {
        _listenedDuration += delta;
      }
    }
    if (pos > Duration.zero) {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (nowMs - _lastQSPositionPushMs > 2000) {
        _lastQSPositionPushMs = nowMs;
        updateMediaSession();
      }
    }
  }

  void notifyAudioOutputFailed() {
    onAudioOutputFailed?.call(AudioOutputState.failed);
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  bool _shouldAdvancePosition() {
    if (_queueManager.currentTrack == null) return false;
    if (!_player.state.playWhenReady) return false;
    if (_player.state.completed) return false;
    if (_queueManager.isAtQueueEnd && !_player.state.playing) {
      return false;
    }
    return true;
  }

  void dispose() {
    _disposed = true;
  }
}
