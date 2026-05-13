import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';
import '../../utils/log.dart';
import '../jellyfin/models/items.dart';

/// Bridges [Player] (mpv_audio_kit) with [audio_service] so the OS
/// lock-screen / notification controls drive playback.
///
/// Keeps [playbackState], [mediaItem], and [queue] in sync with the
/// mpv player and delegates all control commands back to it.
///
/// Cover art is persisted to a temp file and passed to [MediaItem.artUri]
/// as a `file://` URI — Android MediaSession, iOS Now Playing, and
/// Windows SMTC all render `file://` URIs reliably.
class AfPlayerService extends BaseAudioHandler
    with SeekHandler, QueueHandler {
  final Player _player;

  /// The active track queue as [AfTrack] objects. Kept in sync with
  /// `_player.state.playlist` so the rest of the app can read typed
  /// metadata without going through mpv's raw URI strings.
  final List<AfTrack> _trackQueue = [];
  int _currentIndex = -1;

  final _trackController = StreamController<AfTrack?>.broadcast();
  final _queueController = StreamController<List<AfTrack>>.broadcast();

  /// Called whenever the active track changes. Wired by
  /// `playerServiceProvider` to keep `currentTrackProvider` in sync.
  void Function(AfTrack track)? onTrackChanged;

  final List<StreamSubscription<Object?>> _subs = [];

  /// Monotonic counter for cover-art temp files so the OS media widget
  /// doesn't cache stale artwork when the path stays the same.
  int _coverCounter = 0;
  String? _coverPath;

  /// Disposed flag — guards against double-dispose and post-dispose callbacks.
  bool _disposed = false;

  /// Throttle: last time _updatePlaybackState was pushed to audio_service.
  /// Position stream fires at 30-60 Hz; the OS media session only needs
  /// ~2 Hz for human-visible progress. We skip updates that arrive within
  /// 500ms of the last one unless playing/buffering state changed.
  DateTime _lastPlaybackStatePush = DateTime.fromMillisecondsSinceEpoch(0);
  bool _lastPushedPlaying = false;
  bool _lastPushedBuffering = false;

  /// Bounded retry counter for auto-advance nudge.
  /// Prevents infinite play() loops if MPV repeatedly fails to start.
  int _nudgeRetries = 0;
  static const _maxNudgeRetries = 3;

  AfPlayerService() : _player = Player() {
    _bindStreams();
  }

  // ---------------------------------------------------------------------------
  // Public stream surface — mirrors just_audio's API shape so the rest
  // of the codebase needs minimal changes.
  // ---------------------------------------------------------------------------

  Stream<Duration> get positionStream => _player.stream.position;
  Stream<bool> get playingStream => _player.stream.playing;
  Stream<AfTrack?> get currentTrackStream => _trackController.stream;
  Stream<List<AfTrack>> get queueStream => _queueController.stream;
  Stream<bool> get shuffleModeStream => _player.stream.shuffle;
  Stream<Loop> get loopModeStream => _player.stream.loop;
  Stream<double> get speedStream => _player.stream.rate;

  /// Audio device streams for the Output picker.
  Stream<List<Device>> get audioDevicesStream => _player.stream.audioDevices;
  Stream<Device> get audioDeviceStream => _player.stream.audioDevice;
  List<Device> get audioDevices => _player.state.audioDevices;
  Device get audioDevice => _player.state.audioDevice;

  Future<void> setAudioDevice(Device device) async {
    await _player.setAudioDevice(device);
    afLog('audio', 'audioDevice set to ${device.name}');
  }

  /// Real-time FFT spectrum — 64 log-spaced bands in [0, 1] at ~30 fps.
  /// No RECORD_AUDIO permission needed. Lazy: pipeline starts on first
  /// listener, stops on last cancel.
  Stream<FftFrame> get spectrumStream => _player.stream.spectrum;

  /// Configure the spectrum pipeline for visualizer use.
  /// Called once after the player is ready.
  ///
  /// The player owns all DSP: perceptual band mapping, psychoacoustic
  /// scaling, smoothing semantics, and cadence. The UI renderer receives
  /// already-processed bands and applies only a light topology transform
  /// (neighbor blend). No client-side EMA, decay, or ticker needed.
  ///
  /// Settings rationale:
  ///   bandCount: 48   — matches renderer bar count 1:1, no resampling
  ///   emitInterval 16ms — 60 fps, tactile sync perception
  ///   attackSmoothing 0.72 — preserves transient responsiveness
  ///   releaseSmoothing 0.16 — enough persistence without lag
  ///   minDb -68 / maxDb -8 — narrower window prevents noise-floor shimmer
  ///     and keeps the dynamic range in the perceptually active zone
  Future<void> configureSpectrum() async {
    try {
      // Enable gapless playback — mpv pre-fetches the next track so
      // transitions are seamless and auto-advance works correctly.
      await _player.setGapless(Gapless.weak);
      await _player.setSpectrum(const SpectrumSettings(
        bandCount: 64,
        minDb: -30.0,
        maxDb: -12.0,
        attackSmoothing: 0.72,
        releaseSmoothing: 0.08,
        emitInterval: Duration(milliseconds: 16),
      ));
    } catch (_) {
      // Player not ready yet — spectrum will use defaults.
    }
  }

  Duration get position => _player.state.position;
  List<AfTrack> get currentQueue => List.unmodifiable(_trackQueue);
  AfTrack? get currentTrack =>
      (_currentIndex >= 0 && _currentIndex < _trackQueue.length)
          ? _trackQueue[_currentIndex]
          : null;
  bool get isPlaying => _player.state.playing;
  bool get isShuffleEnabled => _player.state.shuffle;
  Loop get loopMode => _player.state.loop;
  double get speed => _player.state.rate;

  // ---------------------------------------------------------------------------
  // Playback control
  // ---------------------------------------------------------------------------

  /// Replace the queue with [tracks] and start playback at [startIndex].
  ///
  /// [resolveStreamUrl] is called for each track to build the Jellyfin
  /// direct-stream URL. [streamHeaders] carries the Authorization header
  /// so it never appears in the URL (and therefore never in server logs).
  Future<void> playQueue(
    List<AfTrack> tracks, {
    int startIndex = 0,
    required String Function(AfTrack track) resolveStreamUrl,
    Map<String, String> streamHeaders = const {},
  }) async {
    if (tracks.isEmpty) return;
    final safeIndex = startIndex.clamp(0, tracks.length - 1);

    _trackQueue
      ..clear()
      ..addAll(tracks);
    _currentIndex = safeIndex;
    _queueController.add(List.unmodifiable(_trackQueue));

    final startTrack = tracks[safeIndex];
    _trackController.add(startTrack);
    onTrackChanged?.call(startTrack);

    afLog(
      'data',
      'playQueue source=live size=${tracks.length} '
      'startIndex=$safeIndex first="${startTrack.title}"',
    );

    // Build Media list. Auth is embedded in the URL via api_key= so
    // libmpv/FFmpeg can authenticate without needing the Authorization
    // header (which FFmpeg rejects due to its comma separators).
    final medias = tracks
        .map((t) => Media(resolveStreamUrl(t)))
        .toList();

    try {
      await _player.openAll(
        medias,
        index: safeIndex,
        play: true,
      );
    } catch (e, stack) {
      afLog('audio', 'playQueue failed', error: e, stackTrace: stack);
      // Revert optimistic state.
      _trackQueue.clear();
      _currentIndex = -1;
      _queueController.add(const []);
      _trackController.add(null);
      rethrow;
    }
  }

  @override
  Future<void> play() async {
    _userPaused = false;
    await _player.play();
  }

  @override
  Future<void> pause() async {
    _userPaused = true;
    _pendingPlayNudgeIdx = null; // cancel any pending nudge
    await _player.pause();
  }

  @override
  Future<void> stop() async {
    await _player.pause();
    await _player.seek(Duration.zero);
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() => _player.next();

  @override
  Future<void> skipToPrevious() => _player.previous();

  @override
  Future<void> skipToQueueItem(int index) => _player.jump(index);

  Future<void> setAfShuffleMode(bool enabled) async {
    await _player.setShuffle(enabled);
    afLog('data', 'shuffleMode source=live enabled=$enabled');
  }

  Future<void> setAfLoopMode(Loop mode) async {
    await _player.setLoop(mode);
    afLog('data', 'loopMode source=live mode=${mode.name}');
  }

  Future<void> setAfSpeed(double speed) async {
    await _player.setRate(speed);
    afLog('data', 'playbackSpeed source=live speed=$speed');
  }

  /// Move a track within the queue from [oldIndex] to [newIndex].
  /// Updates both the in-memory list and the mpv playlist.
  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (oldIndex < 0 ||
        oldIndex >= _trackQueue.length ||
        newIndex < 0 ||
        newIndex >= _trackQueue.length ||
        oldIndex == newIndex) {
      return;
    }

    final track = _trackQueue.removeAt(oldIndex);
    _trackQueue.insert(newIndex, track);

    // mpv playlist-move: moves item at oldIndex to newIndex.
    await _player.sendRawCommand(['playlist-move', '$oldIndex', '$newIndex']);

    // Keep _currentIndex in sync.
    if (_currentIndex == oldIndex) {
      _currentIndex = newIndex;
    } else if (oldIndex < _currentIndex && newIndex >= _currentIndex) {
      _currentIndex -= 1;
    } else if (oldIndex > _currentIndex && newIndex <= _currentIndex) {
      _currentIndex += 1;
    }

    _queueController.add(List.unmodifiable(_trackQueue));
    afLog(
      'audio',
      'reorderQueue oldIndex=$oldIndex newIndex=$newIndex '
      'currentIndex=$_currentIndex queueSize=${_trackQueue.length}',
    );
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final s in _subs) {
      await s.cancel();
    }
    await _trackController.close();
    await _queueController.close();
    await _player.dispose();
  }

  // Set to the expected next index when an auto-advance is in progress.
  // Cleared when mpv fires playing=true for that index OR when the user
  // explicitly pauses (to prevent the nudge from un-pausing them).
  int? _pendingPlayNudgeIdx;
  // Set to true when the user explicitly calls pause() so the nudge
  // listener knows not to call play() on the next playing=false event.
  bool _userPaused = false;

  /// Jump to [index] and immediately play.
  ///
  /// Uses async/await rather than .then() chaining — under Android Doze
  /// with the screen off, Future.then() callbacks on chained Futures can
  /// be deferred by the scheduler. An async method with await runs as a
  /// single continuation and is not subject to the same deferral.
  Future<void> _jumpAndPlay(int index) async {
    try {
      await _player.jump(index);
      await _player.play();
    } catch (e, stack) {
      afLog('audio', '_jumpAndPlay failed at index=$index',
          error: e, stackTrace: stack);
    }
  }

  // ---------------------------------------------------------------------------
  // Internal stream wiring
  // ---------------------------------------------------------------------------

  void _bindStreams() {
    // Sync current track when the playlist index changes.
    _subs.add(_player.stream.playlist.listen((playlist) {
      final idx = playlist.index;
      if (idx < 0 || idx >= _trackQueue.length) return;

      final indexChanged = idx != _currentIndex;
      _currentIndex = idx;

      if (indexChanged) {
        final track = _trackQueue[idx];
        _trackController.add(track);
        afLog(
          'data',
          'currentTrack source=live id=${track.id} '
          'title="${track.title}" index=$idx',
        );
        onTrackChanged?.call(track);
        _updateMediaItem();

        // Reset nudge retry counter for the new track.
        _nudgeRetries = 0;
        // Mark that we expect mpv to start playing this index.
        _pendingPlayNudgeIdx = idx;

        // Race-condition guard: if mpv already fired playing=false before
        // this playlist event arrived (can happen under Doze load), the
        // playing stream listener already missed the nudge window.
        // Check synchronously here — if we're not playing and not user-paused,
        // nudge immediately without waiting for the next playing=false event.
        if (!_player.state.playing && !_userPaused) {
          if (_nudgeRetries < _maxNudgeRetries) {
            _nudgeRetries++;
            _player.play();
            afLog('audio',
                'auto-advance nudge (playlist event) play() at index=$idx (attempt $_nudgeRetries)');
          }
          _pendingPlayNudgeIdx = null;
        }
      }
    }));

    // Sync playback state. Also handles auto-advance nudge without timers:
    // if mpv advanced the index but didn't start playing, nudge it here.
    // This fires synchronously in the foreground service — not throttled
    // by Android Doze unlike Future.delayed.
    _subs.add(_player.stream.playing.listen((playing) {
      _updatePlaybackState();
      if (playing) {
        // mpv started playing — clear the nudge flag and user-pause flag.
        _pendingPlayNudgeIdx = null;
        _userPaused = false;
      } else if (!_userPaused &&
          _pendingPlayNudgeIdx != null &&
          _pendingPlayNudgeIdx == _currentIndex) {
        // mpv advanced the index but stopped — nudge it to play.
        // Bounded retry: if MPV repeatedly fails, stop nudging to avoid
        // an infinite play() loop that thrashes CPU and logs.
        if (_nudgeRetries < _maxNudgeRetries) {
          _nudgeRetries++;
          _player.play();
          afLog('audio',
              'auto-advance nudge play() at index=$_currentIndex (attempt $_nudgeRetries)');
        } else {
          afLog('audio',
              'auto-advance nudge exhausted after $_maxNudgeRetries attempts at index=$_currentIndex');
        }
        _pendingPlayNudgeIdx = null;
      }
    }));

    _subs.add(_player.stream.position.listen((_) => _updatePlaybackStateThrottled()));
    _subs.add(_player.stream.buffering.listen((_) => _updatePlaybackState()));

    // Fallback: mpv signalled completion but didn't advance the index.
    // Jump to next track directly — no delay, fires in foreground context.
    _subs.add(_player.stream.completed.listen((completed) {
      _updatePlaybackState();
      if (!completed) return;
      final nextIdx = _currentIndex + 1;
      if (nextIdx < _trackQueue.length) {
        final currentMpvIdx = _player.state.playlist.index;
        if (currentMpvIdx == _currentIndex) {
          // mpv didn't advance — force jump to next track.
          // Use async/await instead of .then() — Doze can defer .then()
          // callbacks on chained Futures when the screen is off.
          _jumpAndPlay(nextIdx);
          afLog('audio', 'completed fallback: jump+play to index=$nextIdx');
        }
        // If mpv already advanced (currentMpvIdx == nextIdx), the playlist
        // stream + playing stream listeners handle it above.
      }
    }));

    _subs.add(_player.stream.rate.listen((_) => _updatePlaybackState()));

    // Persist embedded cover art to a temp file for the OS media widget.
    _subs.add(_player.stream.coverArt.listen(_persistCover));
  }

  /// Throttled wrapper for position-stream updates.
  /// Pushes at most ~2 Hz to avoid flooding the Android MediaSession
  /// (which syncs to the lock-screen and notification on every push).
  /// State-change events (playing/buffering) bypass the throttle.
  void _updatePlaybackStateThrottled() {
    final s = _player.state;
    final now = DateTime.now();
    final stateChanged =
        s.playing != _lastPushedPlaying || s.buffering != _lastPushedBuffering;
    if (!stateChanged &&
        now.difference(_lastPlaybackStatePush) <
            const Duration(milliseconds: 500)) {
      return;
    }
    _lastPlaybackStatePush = now;
    _lastPushedPlaying = s.playing;
    _lastPushedBuffering = s.buffering;
    _updatePlaybackState();
  }

  void _updatePlaybackState() {
    final s = _player.state;
    final isQueueEnd = s.completed && (_currentIndex >= _trackQueue.length - 1);
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          s.playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.stop,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: s.buffering
            ? AudioProcessingState.buffering
            : isQueueEnd
                ? AudioProcessingState.completed
                : AudioProcessingState.ready,
        playing: s.playing,
        updatePosition: s.position,
        bufferedPosition: s.buffer,
        speed: s.rate,
        queueIndex: _currentIndex >= 0 ? _currentIndex : null,
      ),
    );
  }

  void _updateMediaItem() {
    if (_currentIndex < 0 || _currentIndex >= _trackQueue.length) {
      mediaItem.add(null);
      return;
    }
    final track = _trackQueue[_currentIndex];
    mediaItem.add(
      MediaItem(
        id: track.id,
        title: track.title,
        artist: track.artistName,
        album: track.albumName,
        duration: track.duration == Duration.zero ? null : track.duration,
        artUri: _coverPath != null
            ? Uri.file(_coverPath!)
            : (track.imageUrl != null ? Uri.parse(track.imageUrl!) : null),
        extras: {
          'albumId': track.albumId,
          'artistId': track.artistId,
        },
      ),
    );
  }

  Future<void> _persistCover(CoverArt? raw) async {
    if (raw == null) {
      _coverPath = null;
      _updateMediaItem();
      return;
    }
    final ext = raw.mimeType.split('/').last;
    final id = ++_coverCounter;
    // Use the app's temp directory (guaranteed to be in cacheDir on Android,
    // cleaned up by the OS). Delete the previous file to avoid unbounded growth
    // over a long listening session (finding 3.9 / 4.8).
    final tmpDir = Directory.systemTemp.path;
    final path = '$tmpDir${Platform.pathSeparator}aetherfin_cover_$id.$ext';
    try {
      // Delete previous cover file before writing the new one.
      if (_coverPath != null) {
        final prev = File(_coverPath!);
        if (await prev.exists()) {
          await prev.delete();
        }
      }
      // No flush: true — avoids blocking IO on slower storage.
      // The OS will flush when it needs to; we don't need durability here.
      await File(path).writeAsBytes(raw.bytes);
      _coverPath = path;
      _updateMediaItem();
    } catch (_) {
      // Disk full / sandbox — fall back to network URL in _updateMediaItem.
    }
  }
}