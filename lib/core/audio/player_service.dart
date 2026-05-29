import 'dart:async';

import 'package:flutter/foundation.dart' show VoidCallback, visibleForTesting;
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../../utils/log.dart';
import '../jellyfin/models/items.dart';
import 'artwork_manager.dart';
import 'audio_device_manager.dart';
import 'media_session_bridge.dart';
import 'position_tracker.dart';
import 'player_settings_store.dart';
import 'queue_manager.dart';
import 'stream_prefetcher.dart';

import 'spectrum_settings.dart';

/// Bridges [Player] (mpv_audio_kit) with a platform-native media session.
///
/// Uses a single-track model: mpv plays exactly what we give it via
/// [openAll]. On completion, [skipToNext] or the completed handler
/// advances the Dart queue and calls [openAll] with the next track's
/// URL. No 2-track sliding window, no gapless sync between Dart and
/// mpv's internal playlist.
///
/// - Dart owns the full queue via [AfQueueManager]/[AfQueueEngine].
/// - Queue mutations are pure Dart — 0 mpv calls.
/// - Shuffle is pure Dart Fisher-Yates — 0 mpv calls.
/// - [AfAsyncLock] serializes [openAll] calls in playQueue,
///   setAfLoopMode, and the completed handler.
class AfPlayerService {
  AfPlayerService() : _player = Player() {
    _positionTracker = AfPositionTracker(
      player: _player,
      shouldAdvancePosition: () => shouldAdvancePosition,
    );
    _artworkManager = AfArtworkManager()..onArtworkChanged = _pushStateToNative;
    _audioDeviceManager = AfAudioDeviceManager(player: _player);
    _queueManager = AfQueueManager();
    _prefetcher = StreamPrefetcher();
    _loopModeController = StreamController<Loop>.broadcast();

    final bridge = NativeMediaSessionBridge();
    _wireBridgeCallbacks(bridge);
    _bridge = bridge;

    // Check for pending startup shortcut actions
    Future.microtask(() async {
      final action = await _bridge.getShortcutAction();
      if (action != null) {
        _handleShortcutAction(action);
      }
    });

    // Set audio driver BEFORE binding streams. If setAudioDriver is called
    // after property observation starts, it can re-initialize the output
    // pipeline and break time-pos observation until output is re-selected.
    _player.setAudioDriver('aaudio').catchError((Object e, StackTrace? stack) {
      afLog('error', 'setAudioDriver failed', error: e, stackTrace: stack);
    });

    // 200 ms keeps background playback stable under Android Doze.
    _player.setAudioBuffer(const Duration(milliseconds: 200)).catchError((
      Object e,
      StackTrace? stack,
    ) {
      afLog('error', 'setAudioBuffer failed', error: e, stackTrace: stack);
    });
    _bindStreams();
    _positionTracker.start();

    // Default to 'auto' (Autoselect devices) after streams are bound.
    // mpv starts on a specific device; we switch to 'auto' so the UI
    // shows "Autoselect devices" on first launch. setAudioDevice() no
    // longer calls _audioDeviceManager.nudge(), so the selection won't bounce back.
    Future.delayed(const Duration(milliseconds: 500), () {
      if (_disposed) return;
      try {
        final devices = _player.state.audioDevices;
        final auto = devices.firstWhere(
          (d) => d.name == 'auto',
          orElse: () => _player.state.audioDevice,
        );
        _player.setAudioDevice(auto);
      } catch (_) {}
    });
  }

  @visibleForTesting
  AfPlayerService.test({
    required PlayerApi player,
    NativeMediaSessionBridge? bridge,
  }) : _player = player {
    _positionTracker = AfPositionTracker(
      player: player,
      shouldAdvancePosition: () => shouldAdvancePosition,
    );
    _artworkManager = AfArtworkManager()..onArtworkChanged = _pushStateToNative;
    _audioDeviceManager = AfAudioDeviceManager(player: player);
    _queueManager = AfQueueManager();
    _prefetcher = StreamPrefetcher();
    _loopModeController = StreamController<Loop>.broadcast();

    if (bridge != null) {
      _bridge = bridge;
    }
    _wireBridgeCallbacks(_bridge);

    // Skip setAudioDriver, setAudioBuffer, Future.delayed in test mode.
    // Also skips _positionTracker.start() — position polling creates a
    // Timer.periodic that leaves pending timers in widget tests using
    // FakeAsync. Tests that need position tracking should call
    // _positionTracker.start() explicitly via a visibleForTesting helper.
    _bindStreams();
  }

  @visibleForTesting
  AfPositionTracker get positionTracker => _positionTracker;

  final PlayerApi _player;
  late final AfPositionTracker _positionTracker;
  late final AfArtworkManager _artworkManager;
  late final AfAudioDeviceManager _audioDeviceManager;
  late final AfQueueManager _queueManager;
  double _preDuckVolume = 1.0;
  bool _isDucked = false;
  late final StreamPrefetcher _prefetcher;
  Loop _loopMode = Loop.off;
  late final StreamController<Loop> _loopModeController;
  Map<String, String> _authHeaders = const <String, String>{};
  String? _prefetchStartedForTrackId;
  bool _prefetchPlaylistEnabled = true;

  /// Guards against re-processing a `completed` event for the same track.
  ///
  /// When a track finishes, the completed handler processes the event and
  /// sets this to the track's id. If `completed` re-fires for the same
  /// track (e.g. because a loop mode toggle causes mpv to re-evaluate
  /// end-of-file), the duplicate event is ignored.
  ///
  /// Reset on any explicit track change (playQueue, skip, skipToQueueItem)
  /// so the next track's completion is always processed.
  ///
  /// NOT set for [Loop.file] restarts — the track is expected to complete
  /// again after looping.
  String? _completedHandledForTrackId;

  /// Guards against re-processing a track completion via the EOF fallback.
  ///
  /// Mirrors [_completedHandledForTrackId] but for the position-based
  /// EOF fallback path ([_checkEndOfTrackFallback]). Set when the
  /// fallback fires for a track. Checked by both the fallback itself
  /// (prevents re-entry) and the completed handler (prevents duplicate
  /// advance if a delayed `completed` arrives after the fallback fired).
  ///
  /// Reset on any explicit track change (playQueue, skip, skipToQueueItem)
  /// so the next track's fallback is always processed.
  String? _eofFallbackHandledTrackId;

  /// The ID of the track currently loaded in the mpv player.
  ///
  /// Used in the `completed` stream listener to verify if a completed event
  /// is actually for the current track or a stale event from a previous track.
  String? _mpvLoadedTrackId;

  Duration? _lastPosition;
  Duration _listenedDuration = Duration.zero;

  /// Returns the accumulated continuous listen duration for the active track.
  Duration get listenedDuration => _listenedDuration;

  void _onTrackChangedOrRestarted() {
    _positionTracker.onTrackChanged();
    _listenedDuration = Duration.zero;
    _lastPosition = null;
  }

  void Function(AfTrack? track)? onTrackChanged;
  void Function(String? trackId)? onMpvLoadedTrackChanged;
  void Function(AfTrack track)? onTrackCompleted;
  void Function(AfTrack track)? onTrackSkipped;
  Future<List<AfTrack>> Function(AfTrack lastTrack)? onGetSimilarTracks;
  VoidCallback? onToggleFavorite;
  void Function(bool enabled)? onForNtimesChanged;

  /// Fired when the user starts the app via the "Play Favorites" launcher shortcut.
  VoidCallback? onShortcutPlayFavorites;

  /// Fired when the user starts the app via the "Search" launcher shortcut.
  VoidCallback? onShortcutSearchMusic;

  /// Fired when the artwork path for the active track is updated or resolved.
  void Function(Uri?)? onArtworkUpdated;

  final List<StreamSubscription<dynamic>> _subs =
      <StreamSubscription<dynamic>>[];

  bool _disposed = false;

  NativeMediaSessionBridge _bridge = NativeMediaSessionBridge();

  /// Stored from [playQueue] so [skipToQueueItem] and the completed handler
  /// can lazily resolve stream URLs when rebuilding the 2-track window.
  String Function(AfTrack)? _resolveStreamUrl;

  bool _userPaused = false;
  final AfAsyncLock _queueLock = AfAsyncLock();

  // ---------------------------------------------------------------------------
  // Public stream surface
  // ---------------------------------------------------------------------------

  Stream<Duration> get positionStream => _positionTracker.positionStream;
  Stream<bool> get playingStream => _player.stream.playing;
  Stream<Duration> get audioPtsStream => _player.stream.audioPts;
  Stream<double> get percentPosStream => _player.stream.percentPos;
  double get percentPos => _player.state.percentPos;
  Stream<AfTrack?> get currentTrackStream => _queueManager.currentTrackStream;
  Stream<List<AfTrack>> get queueStream => _queueManager.queueStream;
  Stream<bool> get shuffleModeStream => _queueManager.shuffleModeStream;
  Stream<Loop> get loopModeStream => _loopModeController.stream;
  Stream<double> get speedStream => _player.stream.rate;

  Stream<List<Device>> get audioDevicesStream => _player.stream.audioDevices;
  Stream<Device> get audioDeviceStream => _player.stream.audioDevice;
  List<Device> get audioDevices => _player.state.audioDevices;
  Device get audioDevice => _player.state.audioDevice;

  Future<void> setAudioDevice(Device device) async {
    if (_disposed) return;
    await _player.setAudioDevice(device);
    afLog('audio', 'audioDevice set to ${device.name}');
  }

  // ---------------------------------------------------------------------------
  // Audio hardware & routing
  // ---------------------------------------------------------------------------

  Future<void> setAudioDriver(String driver) async {
    await _player.setAudioDriver(driver);
    afLog('audio', 'audioDriver set to $driver');
  }

  Future<void> setAudioExclusive(bool enabled) async {
    if (_disposed) return;
    await _player.setAudioExclusive(enabled);
    afLog('audio', 'audioExclusive=$enabled');
    _audioDeviceManager.nudge();
  }

  Future<void> setAudioSampleRate(int rate) async {
    if (_disposed) return;
    await _player.setAudioSampleRate(rate);
    afLog('audio', 'audioSampleRate=$rate');
  }

  Future<void> setAudioFormat(Format format) async {
    if (_disposed) return;
    await _player.setAudioFormat(format);
    afLog('audio', 'audioFormat=$format');
  }

  Future<void> setAudioChannels(Channels channels) async {
    await _player.setAudioChannels(channels);
    afLog('audio', 'audioChannels=$channels');
  }

  Future<void> setAudioSpdif(Set<Spdif> codecs) async {
    await _player.setAudioSpdif(codecs);
    afLog('audio', 'audioSpdif=$codecs');
  }

  Stream<AudioParams> get audioOutParamsStream => _player.stream.audioOutParams;
  AudioParams get audioOutParams => _player.state.audioOutParams;

  // ---------------------------------------------------------------------------
  // Network & caching
  // ---------------------------------------------------------------------------

  Future<void> setCache(CacheSettings settings) async {
    if (_disposed) return;
    await _player.setCache(settings);
    afLog('audio', 'cache set: mode=${settings.mode} secs=${settings.secs}');
  }

  CacheSettings get cacheSettings => _player.state.cache;
  Stream<CacheSettings> get cacheStream => _player.stream.cache;

  Future<void> setDemuxerMaxBytes(int bytes) async {
    await _player.setDemuxerMaxBytes(bytes);
    afLog('audio', 'demuxerMaxBytes=${bytes ~/ (1024 * 1024)} MiB');
  }

  Future<void> setDemuxerMaxBackBytes(int bytes) async {
    await _player.setDemuxerMaxBackBytes(bytes);
    afLog('audio', 'demuxerMaxBackBytes=${bytes ~/ (1024 * 1024)} MiB');
  }

  Future<void> setDemuxerReadaheadSecs(int secs) async {
    await _player.setDemuxerReadaheadSecs(secs);
    afLog('audio', 'demuxerReadaheadSecs=$secs');
  }

  Future<void> setNetworkTimeout(Duration timeout) async {
    await _player.setNetworkTimeout(timeout);
    afLog('audio', 'networkTimeout=${timeout.inSeconds}s');
  }

  Future<void> setAudioBuffer(Duration buffer) async {
    if (_disposed) return;
    await _player.setAudioBuffer(buffer);
    afLog('audio', 'audioBuffer=${buffer.inMilliseconds}ms');
  }

  Future<void> setAudioStreamSilence(bool enabled) async {
    if (_disposed) return;
    await _player.setAudioStreamSilence(enabled);
    afLog('audio', 'audioStreamSilence=$enabled');
  }

  bool get audioExclusive => _player.state.audioExclusive;
  Stream<bool> get audioExclusiveStream => _player.stream.audioExclusive;
  bool get audioStreamSilence => _player.state.audioStreamSilence;
  Stream<bool> get audioStreamSilenceStream =>
      _player.stream.audioStreamSilence;
  Duration get audioBuffer => _player.state.audioBuffer;
  Stream<Duration> get audioBufferStream => _player.stream.audioBuffer;

  // ---------------------------------------------------------------------------
  // Playback state & buffering
  // ---------------------------------------------------------------------------

  Stream<MpvPlaybackState> get mpvPlaybackStateStream =>
      _player.stream.playbackState;
  Stream<bool> get bufferingStream => _player.stream.buffering;
  bool get isBuffering => _player.state.buffering;
  Stream<bool> get pausedForCacheStream => _player.stream.pausedForCache;
  bool get isPausedForCache => _player.state.pausedForCache;
  Stream<double> get bufferingPercentageStream =>
      _player.stream.bufferingPercentage;
  double get bufferingPercentage => _player.state.bufferingPercentage;

  Stream<double> get volumeStream => _player.stream.volume;
  double get volume => _player.state.volume;

  Future<void> setVolume(double vol) async {
    await _player.setVolume(vol);
    afLog('audio', 'volume=$vol');
  }

  Stream<bool> get muteStream => _player.stream.mute;
  bool get isMuted => _player.state.mute;

  Future<void> setMute(bool muted) async {
    await _player.setMute(muted);
    afLog('audio', 'mute=$muted');
  }

  Duration get audioDelay => _audioDelay;
  Duration _audioDelay = Duration.zero;

  Future<void> setAudioDelay(Duration delay) async {
    await _player.setAudioDelay(delay);
    _audioDelay = delay;
    afLog('audio', 'audioDelay=${delay.inMilliseconds}ms');
  }

  // ---------------------------------------------------------------------------
  // Audio quality info
  // ---------------------------------------------------------------------------

  Stream<double?> get audioBitrateStream => _player.stream.audioBitrate;
  double? get audioBitrate => _player.state.audioBitrate;
  Stream<AudioParams> get audioParamsStream => _player.stream.audioParams;
  AudioParams get audioParams => _player.state.audioParams;
  Stream<MpvPrefetchState> get prefetchStateStream =>
      _player.stream.prefetchState;
  Stream<MpvPlayerError> get errorStream => _player.stream.error;

  // ---------------------------------------------------------------------------
  // A-B Loop
  // ---------------------------------------------------------------------------

  Future<void> setAbLoopA(Duration? position) async {
    await _player.setAbLoopA(position);
    afLog('audio', 'abLoopA=${position?.inMilliseconds}ms');
  }

  Future<void> setAbLoopB(Duration? position) async {
    await _player.setAbLoopB(position);
    afLog('audio', 'abLoopB=${position?.inMilliseconds}ms');
  }

  Future<void> setAbLoopCount(int? count) async {
    await _player.setAbLoopCount(count);
    afLog('audio', 'abLoopCount=$count');
  }

  Stream<Duration?> get abLoopAStream => _player.stream.abLoopA;
  Duration? get abLoopA => _player.state.abLoopA;
  Stream<Duration?> get abLoopBStream => _player.stream.abLoopB;
  Duration? get abLoopB => _player.state.abLoopB;
  Stream<int?> get remainingAbLoopsStream => _player.stream.remainingAbLoops;

  // ---------------------------------------------------------------------------
  // DSP / Audio Effects
  // ---------------------------------------------------------------------------

  Future<void> setAudioEffects(AudioEffects effects) async {
    if (_disposed) return;
    final optimized = autoBypassFlat(effects);
    await _player.setAudioEffects(optimized);
    afLog('audio', 'audioEffects set');
  }

  Future<void> updateAudioEffects(
    AudioEffects Function(AudioEffects) mapper,
  ) async {
    await _player.updateAudioEffects((current) {
      final updated = mapper(current);
      return autoBypassFlat(updated);
    });
    afLog('audio', 'audioEffects updated');
  }

  Stream<AudioEffects> get audioEffectsStream => _player.stream.audioEffects;
  AudioEffects get audioEffects => _player.state.audioEffects;

  Future<void> setReplayGain(ReplayGainSettings settings) async {
    if (_disposed) return;
    await _player.setReplayGain(settings);
    afLog('audio', 'replayGain mode=${settings.mode}');
  }

  Stream<ReplayGainSettings> get replayGainStream => _player.stream.replayGain;
  ReplayGainSettings get replayGain => _player.state.replayGain;

  // ---------------------------------------------------------------------------
  // Gapless & prefetch (no-ops — deprecated in single-track model)
  // ---------------------------------------------------------------------------

  Future<void> setGapless(Gapless mode) async {
    if (_disposed) return;
    // No-op: gapless is handled by Dart transition logic, not mpv.
    afLog('audio', 'gapless=${mode.name} (no-op)');
  }

  Gapless get gaplessMode => Gapless.no;
  Stream<Gapless> get gaplessStream => const Stream.empty();

  Future<void> setPrefetchPlaylist(bool enabled) async {
    if (_disposed) return;
    _prefetchPlaylistEnabled = enabled;
    if (!enabled) {
      _prefetcher.cancelCurrentPrefetch();
    }
    afLog('audio', 'prefetchPlaylist=$enabled');
  }

  bool get prefetchPlaylist => _prefetchPlaylistEnabled;

  Stream<FftFrame> get spectrumStream => _player.stream.spectrum;

  Future<void> configureSpectrum() async {
    try {
      await _player.setSpectrum(defaultSpectrumSettings);
    } catch (e) {
      afLog('audio', 'configureSpectrum failed', error: e);
    }
  }

  Duration get position => _player.state.position;
  Duration get duration => _player.state.duration;
  Stream<Duration> get durationStream => _player.stream.duration;

  Future<Duration> getRawPosition() {
    return _positionTracker.getRawPosition();
  }

  Future<Duration> getRawDuration() {
    return _positionTracker.getRawDuration();
  }

  List<AfTrack> get currentQueue => _queueManager.currentQueue;

  /// The logical index of the currently-playing track in the queue.
  /// Returns -1 if the queue is empty or playback has ended.
  int get currentIndex => _queueManager.currentIndex;

  AfTrack? get currentTrack => _queueManager.currentTrack;

  bool get isPlaying => _player.state.playing;
  bool get isCompleted => _player.state.completed;
  bool get isUserPaused => _userPaused;

  @visibleForTesting
  set disposedForTesting(bool value) => _disposed = value;

  @visibleForTesting
  bool get isDisposedForTesting => _disposed;

  /// True when UI/notification progress should keep advancing even if mpv's
  /// reported `playing` flag is temporarily stale/false on an OEM pipeline.
  bool get shouldAdvancePosition {
    if (currentTrack == null) return false;
    if (_userPaused) return false;

    // Stop extrapolating as soon as mpv reports any track completed.
    // The completed handler will either advance to the next track
    // (resetting completed to false) or stop playback. Without this
    // guard, position keeps extrapolating past the track end if the
    // completed handler fails or hasn't run yet.
    if (_player.state.completed) return false;

    // Fallback completion detection: on some OEM pipelines / local files
    // mpv's `end-of-file` property observation never fires, so the
    // `completed` stream stays false.  When the queue has ended and mpv
    // reports not-playing, stop advancing.  This also handles the case
    // where the user seeks back after the track ends — a duration-based
    // check would incorrectly keep advancing because pos < dur.
    if (_queueManager.isAtQueueEnd && !_player.state.playing) {
      return false;
    }

    return true;
  }

  bool get isShuffleEnabled => _queueManager.isShuffleEnabled;
  bool get isTailShuffle => _queueManager.isTailShuffle;
  Loop get loopMode => _loopMode;
  double get speed => _player.state.rate;

  // ---------------------------------------------------------------------------
  // Playback control
  // ---------------------------------------------------------------------------

  void setAuthHeaders(Map<String, String> headers) {
    _authHeaders = headers;
    _artworkManager.setAuthHeaders(headers);
  }

  Future<void> playQueue(
    List<AfTrack> tracks, {
    int startIndex = 0,
    required String Function(AfTrack track) resolveStreamUrl,
    Map<String, String> streamHeaders = const <String, String>{},
  }) async {
    if (tracks.isEmpty) return;

    _userPaused = false;
    _resolveStreamUrl = resolveStreamUrl;
    _prefetcher.cancelCurrentPrefetch();
    _prefetchStartedForTrackId = null;
    _completedHandledForTrackId = null;
    _eofFallbackHandledTrackId = null;
    _mpvLoadedTrackId = null;
    onMpvLoadedTrackChanged?.call(null);

    if (streamHeaders.isNotEmpty) {
      _authHeaders = streamHeaders;
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

    final cachedFile = _prefetcher.getCachedFile(startTrack.id);
    final String url;
    if (cachedFile != null && cachedFile.existsSync()) {
      url = cachedFile.uri.toString();
      afLog(
        'audio',
        'playQueue: using prefetched file for "${startTrack.title}"',
      );
    } else {
      url = resolveStreamUrl(startTrack);
    }
    final medias = <Media>[Media(url)];

    return _queueLock.run(() async {
      try {
        _onTrackChangedOrRestarted();

        final shouldPlay = !_userPaused;
        await _player.openAll(medias, index: 0, play: shouldPlay);
        _mpvLoadedTrackId = startTrack.id;
        onMpvLoadedTrackChanged?.call(_mpvLoadedTrackId);

        _audioDeviceManager.nudge();
      } catch (e, stack) {
        afLog('audio', 'playQueue failed', error: e, stackTrace: stack);
        _userPaused = true;
        _queueManager.clear();
        _mpvLoadedTrackId = null;
        onMpvLoadedTrackChanged?.call(null);
        try {
          await _player.stop();
        } catch (err, st) {
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
    _userPaused = false;
    _positionTracker.onPlay();
    try {
      await _player.play();
      _audioDeviceManager.nudge();
    } catch (e, stack) {
      afLog('audio', 'play failed', error: e, stackTrace: stack);
    }
  }

  Future<void> pause() async {
    if (_disposed) return;
    _userPaused = true;
    _positionTracker.onPause();
    try {
      await _player.pause();
    } catch (e, stack) {
      afLog('audio', 'pause failed', error: e, stackTrace: stack);
    }
  }

  Future<void> stop() async {
    if (_disposed) return;
    _userPaused = true;
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
    } catch (e, stack) {
      afLog('audio', 'stop failed', error: e, stackTrace: stack);
    }
  }

  /// Full reset: stops playback, clears the queue, nulls the current track,
  /// and dismisses the media-session notification.
  ///
  /// Used before folder mutations in local mode so stale track references
  /// don't remain in the queue or now-playing screen.
  Future<void> stopAndClear() async {
    if (_disposed) return;
    _userPaused = true;
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
    } catch (e, stack) {
      afLog(
        'audio',
        'stop failed in stopAndClear',
        error: e,
        stackTrace: stack,
      );
    }
    _queueManager.clear();
    onTrackChanged?.call(null);
    _updateMediaSession();
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
      _updateMediaSession();
      _audioDeviceManager.nudge();
    } catch (e, stack) {
      afLog('audio', 'seek failed', error: e, stackTrace: stack);
    }
  }

  Future<void> skipToNext() async {
    if (_disposed) return;
    if (_queueManager.engine.isAtQueueEnd && _loopMode != Loop.playlist) {
      return;
    }

    final wasPlaying = _queueManager.currentTrack;
    _userPaused = false;
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
    if (nextTrack == null) return;

    _onTrackChangedOrRestarted();
    _queueManager.emitCurrentTrack(nextTrack);
    onTrackChanged?.call(nextTrack);
    _updateMediaSession();
    unawaited(_reconfigureSpectrumOnTrackChange());

    try {
      await _rebuildWindow(nextTrack);
    } catch (e, stack) {
      afLog('audio', 'skipToNext failed', error: e, stackTrace: stack);
    }
  }

  Future<void> skipToPrevious() async {
    if (_disposed) return;

    final wasPlaying = _queueManager.currentTrack;
    _userPaused = false;
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
    if (prevTrack == null) return;

    _onTrackChangedOrRestarted();
    _queueManager.emitCurrentTrack(prevTrack);
    onTrackChanged?.call(prevTrack);
    _updateMediaSession();
    unawaited(_reconfigureSpectrumOnTrackChange());

    try {
      await _rebuildWindow(prevTrack);
    } catch (e, stack) {
      afLog('audio', 'skipToPrevious failed', error: e, stackTrace: stack);
    }
  }

  Future<void> skipToQueueItem(int index) async {
    if (_disposed) return;

    final wasPlaying = _queueManager.currentTrack;
    _userPaused = false;
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
    if (targetTrack == null) return;

    _onTrackChangedOrRestarted();
    _queueManager.emitCurrentTrack(targetTrack);
    onTrackChanged?.call(targetTrack);
    _updateMediaSession();
    unawaited(_reconfigureSpectrumOnTrackChange());

    try {
      await _rebuildWindow(targetTrack);
    } catch (e, stack) {
      afLog('audio', 'skipToQueueItem failed', error: e, stackTrace: stack);
    }
  }

  /// Shuffle only the tail of the queue — everything after the current
  /// logical position. The current track keeps its position.
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

    _queueManager.setShuffle(enabled);
    unawaited(PlayerSettingsStore.saveShuffleEnabled(enabled));

    // Don't emitCurrentTrack or fire onTrackChanged — the current track
    // hasn't changed, only the remaining queue order has. Firing
    // onTrackChanged would reset positionStreamProvider to Duration.zero
    // and durationStreamProvider to metadata duration, causing the
    // progress bar to blink between 00:00 and the real position.

    afLog(
      'data',
      'shuffleMode source=live enabled=$enabled '
          'queueSize=${_queueManager.currentQueue.length} currentIndex=${_queueManager.currentIndex}',
    );
    _updateMediaSession();
  }

  Future<void> setAfLoopMode(Loop mode) async {
    if (_disposed) return;
    return _queueLock.run(() async {
      try {
        _loopMode = mode;
        _loopModeController.add(mode);
        unawaited(PlayerSettingsStore.saveLoopMode(mode));
        afLog('data', 'loopMode source=live mode=${mode.name}');
        _updateMediaSession();
      } catch (e, stack) {
        afLog('audio', 'setAfLoopMode failed', error: e, stackTrace: stack);
      }
    });
  }

  /// Enable or disable N-times repeat mode.
  /// When enabled, each track repeats [_queueManager.engine.ntimesCount]
  /// times before advancing to the next track.
  Future<void> setAfForNtimes(bool enabled) async {
    if (_disposed) return;
    _queueManager.engine.setForNtimes(enabled);
    onForNtimesChanged?.call(enabled);
    _updateMediaSession();
    afLog(
      'data',
      'forNtimes source=live enabled=$enabled '
          'ntimesCount=${_queueManager.engine.ntimesCount}',
    );
  }

  /// Update the N value for forNtimes repeat mode.
  Future<void> setAfNtimesCount(int count) async {
    if (_disposed) return;
    _queueManager.engine.setNtimesCount(count);
    afLog('data', 'forNtimesCount source=live count=$count');
  }

  /// Whether forNtimes mode is currently active.
  bool get isForNtimesMode => _queueManager.engine.isForNtimes;

  /// Synchronously set loop mode to off (no async lock, no queue mutation).
  /// Use when exiting forNtimes to prevent stale [_loopMode] reads in
  /// concurrent [setAfForNtimes] → [_updateMediaSession] calls.
  void setLoopModeOffSync() {
    _loopMode = Loop.off;
    _loopModeController.add(Loop.off);
  }

  /// Returns the current active track's artwork URI.
  Uri? get currentArtworkUri {
    final track = _queueManager.currentTrack;
    return track != null ? _artworkManager.artUri(track) : null;
  }

  /// Set playback speed. Intentionally bypasses `_queueLock` because
  /// `setRate` is a simple mpv property setter — it doesn't touch the
  /// playlist/queue state and cannot interleave with queue mutations.
  Future<void> setAfSpeed(double speed) async {
    if (_disposed) return;
    await _player.setRate(speed);
    afLog('data', 'playbackSpeed source=live speed=$speed');
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (_disposed) return;
    if (!_queueManager.canReorder(oldIndex, newIndex)) return;

    _queueManager.reorder(oldIndex, newIndex);
    afLog(
      'audio',
      'reorderQueue oldIndex=$oldIndex newIndex=$newIndex '
          'currentIndex=${_queueManager.currentIndex} queueSize=${_queueManager.currentQueue.length}',
    );
  }

  /// Remove a track from the queue at [index]. Refuses to remove the
  /// currently-playing item. Returns `true` when the removal took effect.
  Future<bool> removeFromQueue(int index) async {
    if (_disposed) return false;
    if (!_queueManager.canRemove(index)) {
      afLog(
        'audio',
        'removeFromQueue refused index=$index (currently playing)',
      );
      return false;
    }

    _queueManager.remove(index);
    afLog(
      'audio',
      'removeFromQueue index=$index currentIndex=${_queueManager.currentIndex} '
          'queueSize=${_queueManager.currentQueue.length}',
    );
    return true;
  }

  Future<void> insertIntoQueue(
    int index,
    AfTrack track, {
    required String Function(AfTrack) resolveStreamUrl,
  }) async {
    if (_disposed) return;
    _resolveStreamUrl = resolveStreamUrl;
    _queueManager.insert(index, track);
    afLog(
      'audio',
      'insertIntoQueue "${track.title}" at index=$index '
          'currentIndex=${_queueManager.currentIndex}',
    );
  }

  Future<void> playNext(
    AfTrack track, {
    required String Function(AfTrack) resolveStreamUrl,
  }) async {
    if (_disposed) return;
    _resolveStreamUrl = resolveStreamUrl;
    _queueManager.engine.insert(
      _queueManager.currentIndex >= 0
          ? _queueManager.currentIndex + 1
          : _queueManager.currentQueue.length,
      track,
    );
    _queueManager.emitQueue();
    afLog('audio', 'playNext "${track.title}"');
  }

  Future<void> addToQueue(
    AfTrack track, {
    required String Function(AfTrack) resolveStreamUrl,
  }) async {
    if (_disposed) return;
    _resolveStreamUrl = resolveStreamUrl;
    _queueManager.engine.append(track);
    _queueManager.emitQueue();
    afLog('audio', 'addToQueue "${track.title}" at end');
  }

  Future<void> appendQueue(
    List<AfTrack> tracks, {
    required String Function(AfTrack) resolveStreamUrl,
  }) async {
    if (_disposed || tracks.isEmpty) return;
    _resolveStreamUrl = resolveStreamUrl;
    _queueManager.appendAll(tracks);
    afLog('audio', 'appendQueue added ${tracks.length} tracks at end');
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _bridge.dispose();
    _positionTracker.dispose();
    _queueManager.dispose();
    _prefetcher.cancelCurrentPrefetch();
    _mpvLoadedTrackId = null;
    _eofFallbackHandledTrackId = null;
    for (final s in _subs) {
      await s.cancel();
    }
    await _loopModeController.close();
    await _player.dispose();
  }

  void _pushStateToNative() {
    _updateMediaSession();
  }

  Future<void> _reconfigureSpectrumOnTrackChange() async {
    if (_disposed) return;
    try {
      await Future.delayed(const Duration(milliseconds: 250));
      if (_disposed) return;
      await _player.setSpectrum(defaultSpectrumSettings);
      afLog('audio', 'spectrum re-configured after track change');
    } catch (e) {
      afLog('audio', 'reconfigureSpectrumOnTrackChange failed', error: e);
    }
  }

  // ---------------------------------------------------------------------------
  // 2-track window management
  // ---------------------------------------------------------------------------

  /// Rebuild the 2-track mpv window for [target] and its next track.
  ///
  /// Used by [skipToQueueItem] and the completed handler when the current
  /// mpv slots don't match the new queue position. Resolves stream URLs
  /// lazily via [_resolveStreamUrl].
  Future<void> _rebuildWindow(AfTrack target) async {
    if (_resolveStreamUrl == null) return;

    _prefetcher.cancelCurrentPrefetch();
    _prefetchStartedForTrackId = null;

    final cachedFile = _prefetcher.getCachedFile(target.id);
    final String url;
    if (cachedFile != null && cachedFile.existsSync()) {
      url = cachedFile.uri.toString();
      afLog(
        'audio',
        'rebuildWindow: using prefetched file for "${target.title}"',
      );
    } else {
      url = _resolveStreamUrl!(target);
    }

    try {
      await _player.openAll([Media(url)], index: 0, play: !_userPaused);
      _mpvLoadedTrackId = target.id;
      onMpvLoadedTrackChanged?.call(_mpvLoadedTrackId);
    } catch (e) {
      _mpvLoadedTrackId = null;
      onMpvLoadedTrackChanged?.call(null);
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Internal stream wiring
  // ---------------------------------------------------------------------------

  void _bindStreams() {
    _subs.add(
      _positionTracker.positionStream.listen((pos) {
        _checkPrefetch(pos);
        _checkEndOfTrackFallback(pos);
        final last = _lastPosition;
        _lastPosition = pos;
        if (last != null && isPlaying) {
          final delta = pos - last;
          if (delta > Duration.zero &&
              delta < const Duration(milliseconds: 1200)) {
            _listenedDuration += delta;
          }
        }
      }),
    );
    _subs.add(
      _player.stream.playing.listen((playing) async {
        try {
          _updateMediaSession();
          if (playing && _queueManager.currentTrack != null) {
            _userPaused = false;
          }
        } catch (e, stack) {
          afLog('audio', 'playing handler failed', error: e, stackTrace: stack);
        }
      }),
    );

    _subs.add(_player.stream.buffering.listen((_) => _updateMediaSession()));

    _subs.add(
      _player.stream.completed.listen((completed) async {
        try {
          if (_disposed) return;
          if (!completed) return;

          // No track active or mismatch between loaded track in mpv and Dart.
          // This prevents stale/duplicate completed events from the previous
          // track (which fires when stopping/replacing the media in openAll)
          // from being treated as the completion of the newly-advanced track.
          final currentTrackId = _queueManager.currentTrack?.id;
          if (currentTrackId == null || _mpvLoadedTrackId != currentTrackId) {
            afLog(
              'audio',
              'completed event ignored: currentTrackId=$currentTrackId, '
                  'mpvLoadedTrackId=$_mpvLoadedTrackId (mismatch or null)',
            );
            return;
          }

          final loopAtEvent = _loopMode;
          final playingAtEvent = _player.state.playing;

          // Guard: ignore duplicate completed events for the same track.
          // This prevents loop mode toggles from re-entering the handler
          // and changing the displayed track (Bug 2).
          if (_completedHandledForTrackId == currentTrackId) {
            afLog(
              'audio',
              'completed event ignored: already handled for '
                  'track "$currentTrackId"',
            );
            return;
          }

          // Loop.file: restart current track regardless of queue position.
          // mpv's single-track model may fire `completed` even with
          // Loop.file set. Don't advance — explicitly seek to 0 and play.
          // Don't set _completedHandledForTrackId so the next completion
          // (after the track loops) is processed.
          if (loopAtEvent == Loop.file) {
            return _queueLock.run(() async {
              _onTrackChangedOrRestarted();
              try {
                await _player.seek(Duration.zero);
                if (!_player.state.playing) {
                  await _player.play();
                }
              } catch (e, stack) {
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
              _updateMediaSession();
              afLog('audio', 'Loop.file — restarted current track');
            });
          }

          // Check for N-times repeat before advancing or ending
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
            } catch (e, stack) {
              afLog(
                'audio',
                'forNtimes: seek(0) failed',
                error: e,
                stackTrace: stack,
              );
            }
            _updateMediaSession();
            return;
          }

          // Mark this track's completion as handled so duplicate events
          // (from loop mode toggles) are ignored.
          _completedHandledForTrackId = currentTrackId;

          if (!_queueManager.engine.isAtQueueEnd) {
            return _queueLock.run(_advanceToNextTrack);
          } else {
            // End of queue
            var autoplayTriggered = false;
            if (loopAtEvent == Loop.off && onGetSimilarTracks != null) {
              final lastTrack = _queueManager.currentTrack;
              if (lastTrack != null) {
                try {
                  final similar = await onGetSimilarTracks!(lastTrack);
                  if (similar.isNotEmpty) {
                    for (final t in similar) {
                      _queueManager.engine.append(t);
                    }
                    _queueManager.emitQueue();

                    // Now the queue is extended! Slide and play the next track.
                    return _queueLock.run(() async {
                      await _advanceToNextTrack();
                      autoplayTriggered = true;
                    });
                  }
                } catch (e, stack) {
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
                  _userPaused = true;
                  _positionTracker.onStop();
                  _mpvLoadedTrackId = null;
                  try {
                    await _player.stop();
                  } catch (e, stack) {
                    afLog(
                      'audio',
                      'stop failed on queue completion',
                      error: e,
                      stackTrace: stack,
                    );
                  }
                  _queueManager.endPlayback();
                  onTrackChanged?.call(null);
                  _updateMediaSession();
                  afLog('audio', 'queue end, auto-stop (loop=off)');

                case Loop.playlist:
                  return _queueLock.run(() async {
                    _queueManager.engine.jumpTo(0);
                    _onTrackChangedOrRestarted();
                    await _rebuildWindow(_queueManager.currentTrack!);
                    _updateMediaSession();
                    afLog('audio', 'queue end, looping playlist');
                  });
                case Loop.file:
                  // Loop.file is handled early (before isAtQueueEnd check).
                  // This branch should never be reached, but if it is,
                  // restart the track defensively.
                  _onTrackChangedOrRestarted();
                  try {
                    await _player.seek(Duration.zero);
                    if (!_player.state.playing) {
                      await _player.play();
                    }
                  } catch (e, stack) {
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
        } catch (e, stack) {
          afLog(
            'audio',
            'completed handler failed',
            error: e,
            stackTrace: stack,
          );
        }
      }),
    );

    _subs.add(_player.stream.rate.listen((_) => _updateMediaSession()));
    _subs.add(
      _player.stream.duration.listen((dur) {
        if (dur > Duration.zero) {
          _updateMediaSession();
        }
      }),
    );
    _subs.add(
      _player.stream.coverArt.listen((raw) async {
        try {
          try {
            await _artworkManager.persistCover(raw);
          } catch (e, stack) {
            afLog('audio', 'persistCover failed', error: e, stackTrace: stack);
          }
          _updateMediaSession();
        } catch (e, stack) {
          afLog(
            'audio',
            'coverArt handler failed',
            error: e,
            stackTrace: stack,
          );
        }
      }),
    );

    _subs.add(
      _player.stream.audioDevice.listen((newDevice) async {
        try {
          if (!_audioDeviceManager.isRealDeviceChange(newDevice.name)) return;
          try {
            await _audioDeviceManager.reapplyPersistedEffects();
          } catch (e, stack) {
            afLog(
              'audio',
              'reapplyPersistedEffects failed',
              error: e,
              stackTrace: stack,
            );
          }
        } catch (e, stack) {
          afLog(
            'audio',
            'audioDevice handler failed',
            error: e,
            stackTrace: stack,
          );
        }
      }),
    );
  }

  void _checkPrefetch(Duration pos) {
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
        final nextUrl = _resolveStreamUrl?.call(nextTrack);
        if (nextUrl != null) {
          unawaited(
            _prefetcher.prefetch(nextUrl, _authHeaders, trackId: nextTrack.id),
          );
        }
      }
    }
  }

  /// Advance the engine to the next track and rebuild the mpv window.
  ///
  /// Called from:
  /// - The completed handler's mid-queue branch
  /// - The completed handler's autoplay branch (end-of-queue with similar tracks)
  /// - The EOF fallback ([_checkEndOfTrackFallback])
  ///
  /// Must be called inside [_queueLock.run()] to prevent interleaving with
  /// other queue mutations. Errors propagate to the caller's try-catch.
  Future<void> _advanceToNextTrack() async {
    _queueManager.engine.advanceIndex();
    _onTrackChangedOrRestarted();

    final current = _queueManager.currentTrack;
    if (current != null) {
      _queueManager.emitCurrentTrack(current);
      onTrackChanged?.call(current);
      unawaited(Future.microtask(() => onTrackCompleted?.call(current)));
    }
    _updateMediaSession();
    unawaited(_reconfigureSpectrumOnTrackChange());

    if (current != null) {
      await _rebuildWindow(current);
    }
  }

  /// Position-based EOF fallback detection.
  ///
  /// Called on every position tick from the position stream listener
  /// (inside [_bindStreams], alongside [_checkPrefetch]).
  ///
  /// Fires when all conditions are met:
  /// 1. A current track exists
  /// 2. The completed handler hasn't already processed this track
  /// 3. The fallback itself hasn't already fired for this track
  /// 4. mpv reports a valid duration
  /// 5. Position is within 500ms of the end
  /// 6. mpv has stopped playing (EOF reached)
  ///
  /// When triggered, advances to the next track via [_advanceToNextTrack]
  /// inside [_queueLock].
  void _checkEndOfTrackFallback(Duration pos) {
    final currentTrack = _queueManager.currentTrack;
    if (currentTrack == null) return;

    // Don't fire if the completed handler already processed this track.
    if (_completedHandledForTrackId == currentTrack.id) return;

    // Don't fire if we already triggered the fallback for this track.
    if (_eofFallbackHandledTrackId == currentTrack.id) return;

    final duration = _player.state.duration;
    if (duration <= Duration.zero) return;

    // Position must be near the end of the track.
    if (pos < duration - const Duration(milliseconds: 500)) return;

    // mpv must have stopped (EOF reached).
    if (_player.state.playing) return;

    // All conditions met — advance to next track.
    _eofFallbackHandledTrackId = currentTrack.id;
    afLog(
      'audio',
      'EOF fallback triggered for track "${currentTrack.id}" '
          'pos=${pos.inMilliseconds}ms duration=${duration.inMilliseconds}ms',
    );

    unawaited(_queueLock.run(_advanceToNextTrack));
  }

  int _lastMediaSessionUpdateMs = 0;
  bool _lastEffectivePlaying = false;

  /// Push the current state through the bridge (throttled to ~100ms).
  /// Sends `updateState` when there is an active track,
  /// or `clear` when the queue is empty.
  ///
  /// Throttles at the entry point so `MediaSessionState` construction
  /// (which involves several field accesses across managers) doesn't
  /// run at 30–60 Hz from [_player.stream.position]. The bridge's own
  /// internal throttle on the MethodChannel call is insufficient because
  /// by the time it's reached, the state object has already been built.
  void _updateMediaSession() {
    if (_disposed) return;
    final track = _queueManager.currentTrack;
    if (track == null) {
      _bridge.clear();
      return;
    }

    final s = _player.state;
    final isQueueEnd = s.completed && _queueManager.isAtQueueEnd;
    // Fallback track-end detection for when mpv's end-of-file property
    // observation doesn't fire.  Overrides s.playing which may be
    // transiently true even though the track has finished.
    final trackEnded =
        !_userPaused &&
        _queueManager.isAtQueueEnd &&
        s.duration > Duration.zero &&
        _positionTracker.lastKnownPosition >= s.duration;
    final effectivePlaying = (isQueueEnd || trackEnded)
        ? false
        : (s.playing || shouldAdvancePosition);

    // Throttle — skip early when called too frequently, BUT always let
    // playing→stopped transitions through immediately. If we throttle
    // the first playing:false call, Android MediaSession keeps the last
    // STATE_PLAYING anchor and extrapolates the progress bar forever.
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

    // Map mpv Loop enum to the string the native side expects.
    // forNtimes takes priority since it's a superset of the underlying
    // mpv loop mode.
    final loopModeStr = _queueManager.engine.isForNtimes
        ? 'ntimes'
        : switch (_loopMode) {
            Loop.file => 'one',
            Loop.playlist => 'all',
            Loop.off => 'off',
          };

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

  void _wireBridgeCallbacks(NativeMediaSessionBridge bridge) {
    bridge.onPlay = () => unawaited(play());
    bridge.onPause = () => unawaited(pause());
    bridge.onNext = () => unawaited(skipToNext());
    bridge.onPrevious = () => unawaited(skipToPrevious());
    bridge.onStop = () => unawaited(stop());
    bridge.onSeek = (Duration pos) => unawaited(seek(pos));
    bridge.onSkipToQueueItem = (int idx) => unawaited(skipToQueueItem(idx));
    bridge.onSetShuffleMode = (int shuffleMode) {
      unawaited(setAfShuffleMode(shuffleMode == 1));
    };
    bridge.onSetRepeatMode = (int repeatMode) {
      final mode = switch (repeatMode) {
        1 => Loop.file,
        2 => Loop.playlist,
        _ => Loop.off,
      };
      unawaited(setAfLoopMode(mode));
    };
    bridge.onToggleShuffle = () {
      unawaited(setAfShuffleMode(!_queueManager.isShuffleEnabled));
    };
    bridge.onToggleRepeat = () {
      if (_queueManager.engine.isForNtimes) {
        _loopMode = Loop.off;
        _loopModeController.add(Loop.off);
        unawaited(setAfForNtimes(false));
        unawaited(PlayerSettingsStore.saveLoopMode(Loop.off));
      } else {
        switch (_loopMode) {
          case Loop.off:
            unawaited(setAfLoopMode(Loop.playlist));
          case Loop.playlist:
            unawaited(setAfLoopMode(Loop.file));
          case Loop.file:
            unawaited(setAfForNtimes(true));
        }
      }
    };
    bridge.onDuck = (double targetVolume) {
      if (!_isDucked) {
        _preDuckVolume = _player.state.volume;
        _isDucked = true;
      }
      unawaited(setVolume(_preDuckVolume * targetVolume));
    };
    bridge.onUnduck = () {
      if (_isDucked) {
        unawaited(setVolume(_preDuckVolume));
        _isDucked = false;
      }
    };
    bridge.onShortcutAction = _handleShortcutAction;
    bridge.onToggleFavorite = () => onToggleFavorite?.call();
  }

  void updateTrackFavorite(String trackId, bool isFavorite) {
    _queueManager.updateTrackFavorite(trackId, isFavorite);
    _updateMediaSession();
  }

  void _handleShortcutAction(String action) {
    afLog('audio', 'Handling native shortcut action: $action');
    if (action == 'play_favorites') {
      onShortcutPlayFavorites?.call();
    } else if (action == 'search_music') {
      onShortcutSearchMusic?.call();
    }
  }
}

/// Sanitise an [AudioEffects] bundle before it goes into libmpv's
/// `af` filter chain.
///
/// Two things happen here:
///
/// 1. **Bypass flat filters.** libmpv keeps every entry in `af`
///    even when its parameters are neutral, which costs CPU on the
///    audio thread *and* causes the FFT spectrum (which taps the
///    chain post-DSP) to smear when a shelf or EQ band is set to
///    0/flat. Stripping no-op filters keeps the chain minimal.
///
///    Notes per filter:
///      * `bass` / `treble` shelves: neutral gain is `0` dB.
///        Disable when the user has cut the slider all the way
///        back to 0.
///      * `superequalizer`: neutral gain is `1.0` (a multiplier,
///        not a dB value). `_buildEqParams()` in the EQ screen
///        already strips bands at `1.0`, so by the time the bundle
///        reaches here, `params` is either empty (every band flat
///        — nothing to do) or contains at least one user-adjusted
///        band that we must keep. The previous check used
///        `gain != 0.0`, which also disabled the EQ when a user
///        explicitly cut a band to 0 (full mute), defeating
///        "muted band" presets entirely.
///
/// 2. **Clamp out-of-range filter params to libmpv's accepted
///    domain.** If *any* filter in an `af` chain has an
///    out-of-range parameter, libmpv rejects the entire chain and
///    audio flows through un-filtered (with no error surfaced to
///    the user). That makes one bad value silently disable every
///    other DSP filter, which is exactly the de-esser regression
///    that prompted this sanitiser: the EQ/DSP screen used to send
///    `deesser.f` as a 5500 Hz cutoff while libmpv expects a
///    0..1 ratio, kicking the chain out as soon as the user
///    enabled the de-esser.
///
/// Exposed as a top-level function so it can be unit-tested
/// without constructing an [AfPlayerService] (which requires
/// libmpv).
@visibleForTesting
AudioEffects autoBypassFlat(AudioEffects fx) {
  return fx.copyWith(
    bass: fx.bass.copyWith(enabled: fx.bass.enabled && fx.bass.g.abs() > 0.001),
    treble: fx.treble.copyWith(
      enabled: fx.treble.enabled && fx.treble.g.abs() > 0.001,
    ),
    superequalizer: fx.superequalizer.copyWith(
      enabled: fx.superequalizer.enabled && fx.superequalizer.params.isNotEmpty,
    ),
    deesser: fx.deesser.copyWith(
      // Every deesser knob is a 0..1 ratio in libmpv. Clamp on the
      // way out so a value persisted by an older build (or one set
      // by a future buggy UI) can never poison the chain again.
      f: fx.deesser.f.clamp(0.0, 1.0),
      i: fx.deesser.i.clamp(0.0, 1.0),
      m: fx.deesser.m.clamp(0.0, 1.0),
    ),
  );
}

class AfAsyncLock {
  Future<void> _chain = Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _chain = _chain
        .then((_) async {
          try {
            final result = await action();
            completer.complete(result);
          } catch (e, st) {
            completer.completeError(e, st);
          }
        })
        .catchError((Object error, StackTrace stack) {
          afLog(
            'error',
            'AfAsyncLock chain error',
            error: error,
            stackTrace: stack,
          );
        });
    return completer.future;
  }
}
