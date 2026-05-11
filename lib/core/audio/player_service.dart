import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../../utils/log.dart';
import '../jellyfin/models/items.dart';

/// Wraps `just_audio` + `audio_service` so:
///   - the OS lock screen / notification controls drive playback,
///   - `position`, `state`, and `currentTrack` are single-source streams
///     (per non-negotiable rule §4.3 — one [Stream<Duration>] feeds the
///     ring, waveform, lyric scroll, and time labels),
///   - background audio survives app backgrounding.
class AfPlayerService extends BaseAudioHandler with QueueHandler, SeekHandler {
  final _player = AudioPlayer();
  final _trackQueue = <AfTrack>[];
  int _currentIndex = -1;
  final _trackController = StreamController<AfTrack?>.broadcast();
  final _queueController = StreamController<List<AfTrack>>.broadcast();

  /// Called whenever the active track changes (queue advance, manual
  /// skip, queue replaced). Wired by `playerServiceProvider` so the
  /// Riverpod layer can keep `currentTrackProvider` in sync and report
  /// session start/stop to Jellyfin.
  ///
  /// Player itself is Riverpod-free so it stays testable without a
  /// ProviderContainer.
  void Function(AfTrack track)? onTrackChanged;

  AfPlayerService() {
    _player.playbackEventStream.listen(
      _broadcastPlaybackEvent,
      onError: (Object e, StackTrace stack) {
        afLog(
          'audio',
          'playbackEventStream error',
          error: e,
          stackTrace: stack,
        );
      },
    );
    _player.processingStateStream.listen((state) {
      afLog(
        'audio',
        'processingState=${state.name} '
        'playing=${_player.playing} position=${_player.position.inMilliseconds}ms '
        'duration=${_player.duration?.inMilliseconds ?? "?"}ms',
      );
    });
    _player.currentIndexStream.listen((idx) {
      if (idx == null) return;
      if (idx < 0 || idx >= _trackQueue.length) return;
      // currentIndexStream re-emits on every state change, not just on
      // index changes — without this dedupe we'd fire onTrackChanged +
      // playbackStart dozens of times for the same track and spam
      // /Sessions/Playing.
      if (idx == _currentIndex) return;
      _currentIndex = idx;
      final track = _trackQueue[idx];
      mediaItem.add(_mediaItemFor(track));
      _trackController.add(track);
      afLog(
        'data',
        'currentTrack source=live id=${track.id} '
        'title="${track.title}" index=$idx',
      );
      onTrackChanged?.call(track);
    });
  }

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<bool> get playingStream => _player.playingStream;
  Stream<ProcessingState> get stateStream => _player.processingStateStream;
  /// Broadcast stream of the currently-playing [AfTrack]. Emits whenever
  /// the queue index advances; emits `null` when the queue is cleared.
  Stream<AfTrack?> get currentTrackStream => _trackController.stream;
  /// Broadcast stream of the active queue — emits the same list shape the
  /// Queue screen renders so it reflects skips / replacements immediately.
  Stream<List<AfTrack>> get queueStream => _queueController.stream;
  /// Broadcast stream of just_audio's shuffle flag.
  Stream<bool> get shuffleModeStream => _player.shuffleModeEnabledStream;
  /// Broadcast stream of just_audio's loop mode (off / one / all).
  Stream<LoopMode> get loopModeStream => _player.loopModeStream;
  /// Broadcast stream of the playback speed multiplier (1.0 = normal).
  Stream<double> get speedStream => _player.speedStream;
  Duration get position => _player.position;
  List<AfTrack> get currentQueue => List.unmodifiable(_trackQueue);
  AfTrack? get currentTrack =>
      (_currentIndex >= 0 && _currentIndex < _trackQueue.length)
          ? _trackQueue[_currentIndex]
          : null;
  /// Synchronous snapshot of the play/pause state. Backs the live-
  /// update notification's "playing" colour cue — the chip needs the
  /// current value at post-time, not just a stream subscription.
  bool get isPlaying => _player.playing;
  bool get isShuffleEnabled => _player.shuffleModeEnabled;
  LoopMode get loopMode => _player.loopMode;
  double get speed => _player.speed;

  /// The Android audio session ID of the underlying ExoPlayer instance.
  /// Used by [VisualizerService] to attach [android.media.audiofx.Visualizer].
  /// Returns null before the first [playQueue] call (player not yet initialised).
  int? get audioSessionId => _player.androidAudioSessionId;

  /// Stream of Android audio session ID changes. ExoPlayer can recreate
  /// its session on some devices after a seek or source change — the
  /// [VisualizerService] re-attaches on each new value.
  Stream<int?> get audioSessionIdStream => _player.androidAudioSessionIdStream;

  /// Replace the queue with [tracks] and start playback at [startIndex].
  ///
  /// [streamHeaders] are attached to every `AudioSource.uri` so the
  /// Jellyfin Authorization header rides on each stream request instead
  /// of being embedded as `?api_key=…` in the URL (where it would leak to
  /// the server's access log and any logcat-grepping app on the device).
  Future<void> playQueue(
    List<AfTrack> tracks, {
    int startIndex = 0,
    required String Function(AfTrack track) resolveStreamUrl,
    Map<String, String> streamHeaders = const {},
  }) async {
    if (tracks.isEmpty) return;
    // Clamp the caller-supplied index so a stale UI cannot crash playback
    // with a RangeError on the line `tracks[startIndex]` below.
    final safeIndex = startIndex < 0
        ? 0
        : (startIndex >= tracks.length ? tracks.length - 1 : startIndex);
    final previousIndex = _currentIndex;
    final previousQueue = List<AfTrack>.from(_trackQueue);
    final previousTrack =
        (previousIndex >= 0 && previousIndex < previousQueue.length)
            ? previousQueue[previousIndex]
            : null;
    _trackQueue
      ..clear()
      ..addAll(tracks);
    queue.add(tracks.map(_mediaItemFor).toList());
    _queueController.add(List.unmodifiable(_trackQueue));
    final sources = tracks
        .map((t) => AudioSource.uri(
              Uri.parse(resolveStreamUrl(t)),
              headers: streamHeaders.isEmpty ? null : streamHeaders,
              tag: _mediaItemFor(t),
            ))
        .toList();
    final startTrack = tracks[safeIndex];
    // Pre-set _currentIndex BEFORE setAudioSource so the currentIndexStream
    // listener's dedupe (`if (idx == _currentIndex) return;`) suppresses
    // the spurious emit that fires immediately after the source is set —
    // we drive the initial onTrackChanged + mediaItem broadcast ourselves
    // below so the UI / playback reporter see the new track before audio
    // even starts loading.
    _currentIndex = safeIndex;
    mediaItem.add(_mediaItemFor(startTrack));
    _trackController.add(startTrack);
    afLog(
      'data',
      'playQueue source=live size=${tracks.length} '
      'startIndex=$safeIndex first="${startTrack.title}"',
    );
    onTrackChanged?.call(startTrack);
    try {
      await _player.setAudioSource(
        ConcatenatingAudioSource(children: sources),
        initialIndex: safeIndex,
      );
      await _player.play();
    } on Object catch (e, stack) {
      afLog(
        'audio',
        'playQueue failed',
        error: e,
        stackTrace: stack,
      );
      // Revert the FULL optimistic update so the UI doesn't keep claiming
      // a track is loaded that we couldn't actually wire up. The original
      // rollback only un-set `_trackQueue` and `_currentIndex` — the
      // `mediaItem`, `_trackController`, and `onTrackChanged` broadcasts
      // still pointed at the failed start track, so MiniPlayer + Now
      // Playing rendered metadata for audio that would never play.
      _trackQueue
        ..clear()
        ..addAll(previousQueue);
      _currentIndex = previousIndex;
      queue.add(previousQueue.map(_mediaItemFor).toList());
      _queueController.add(List.unmodifiable(_trackQueue));
      // audio_service's `mediaItem` is BehaviorSubject<MediaItem?>; emit
      // null when there was no prior track so the lock-screen / OS card
      // clears too. Previously the failed `mediaItem.add(_mediaItemFor(
      // startTrack))` stayed wedged on the OS layer.
      mediaItem.add(
        previousTrack != null ? _mediaItemFor(previousTrack) : null,
      );
      _trackController.add(previousTrack);
      if (previousTrack != null) {
        onTrackChanged?.call(previousTrack);
      }
      rethrow;
    }
  }

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() => _player.seekToNext();

  @override
  Future<void> skipToPrevious() => _player.seekToPrevious();

  @override
  Future<void> skipToQueueItem(int index) =>
      _player.seek(Duration.zero, index: index);

  /// Toggle shuffle. just_audio reshuffles the queue order; the
  /// underlying [_trackQueue] list is left in original order — only the
  /// playback order changes. The Queue screen reflects the new order via
  /// `queueStream` (currentIndexStream still fires per-skip).
  ///
  /// Named with the `af` prefix to avoid colliding with
  /// `BaseAudioHandler.setShuffleMode(AudioServiceShuffleMode)` which the
  /// OS lock-screen calls with a different enum type.
  Future<void> setAfShuffleMode(bool enabled) async {
    if (enabled) {
      // Generate a fresh shuffle order so consecutive toggles don't
      // produce the same sequence.
      await _player.shuffle();
    }
    await _player.setShuffleModeEnabled(enabled);
    afLog('data', 'shuffleMode source=live enabled=$enabled');
  }

  /// Set loop mode to `off`, `one`, or `all`.
  ///
  /// Named with the `af` prefix to avoid colliding with
  /// `BaseAudioHandler.setRepeatMode(AudioServiceRepeatMode)`.
  Future<void> setAfLoopMode(LoopMode mode) async {
    await _player.setLoopMode(mode);
    afLog('data', 'loopMode source=live mode=${mode.name}');
  }

  /// Set playback speed multiplier (0.5–2.0 is the user-facing range).
  Future<void> setAfSpeed(double speed) async {
    await _player.setSpeed(speed);
    afLog('data', 'playbackSpeed source=live speed=$speed');
  }

  /// Move a track within the queue from [oldIndex] to [newIndex].
  ///
  /// Updates both the in-memory [_trackQueue] list and the underlying
  /// [ConcatenatingAudioSource] so the player's actual playback order
  /// matches what the Queue screen shows. Previously only the UI mirror
  /// was updated — the player kept the original order and skip-next
  /// would play the wrong track after a drag.
  ///
  /// [oldIndex] and [newIndex] are the indices BEFORE the standard
  /// `ReorderableListView` adjustment (i.e. the raw values from
  /// `onReorder`). The caller must apply the `if (newIndex > oldIndex)
  /// newIndex -= 1` adjustment before calling this method.
  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (oldIndex < 0 ||
        oldIndex >= _trackQueue.length ||
        newIndex < 0 ||
        newIndex >= _trackQueue.length ||
        oldIndex == newIndex) {
      return;
    }
    // Update the in-memory track list.
    final track = _trackQueue.removeAt(oldIndex);
    _trackQueue.insert(newIndex, track);
    // Update the audio source so the player's skip-next/prev order
    // matches. ConcatenatingAudioSource.move() is the just_audio API
    // for this — it moves the source at [currentIndex] to [newIndex]
    // without interrupting playback.
    final source = _player.audioSource;
    if (source is ConcatenatingAudioSource) {
      await source.move(oldIndex, newIndex);
    }
    // Keep _currentIndex in sync — if the currently-playing track was
    // moved, or if the move shifted it, update the pointer.
    if (_currentIndex == oldIndex) {
      _currentIndex = newIndex;
    } else if (oldIndex < _currentIndex && newIndex >= _currentIndex) {
      _currentIndex -= 1;
    } else if (oldIndex > _currentIndex && newIndex <= _currentIndex) {
      _currentIndex += 1;
    }
    // Broadcast the new queue so the Queue screen re-renders.
    queue.add(_trackQueue.map(_mediaItemFor).toList());
    _queueController.add(List.unmodifiable(_trackQueue));
    afLog(
      'audio',
      'reorderQueue oldIndex=$oldIndex newIndex=$newIndex '
      'currentIndex=$_currentIndex queueSize=${_trackQueue.length}',
    );
  }

  Future<void> dispose() async {
    await _player.dispose();
    await _trackController.close();
    await _queueController.close();
  }

  // ---------------------------------------------------------------------------

  MediaItem _mediaItemFor(AfTrack t) => MediaItem(
        id: t.id,
        album: t.albumName,
        title: t.title,
        artist: t.artistName,
        duration: t.duration,
        artUri: t.imageUrl != null ? Uri.parse(t.imageUrl!) : null,
        extras: {
          'albumId': t.albumId,
          'artistId': t.artistId,
        },
      );

  void _broadcastPlaybackEvent(PlaybackEvent event) {
    final playing = _player.playing;
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      // The lookup defaults to AudioProcessingState.idle when just_audio
      // adds a new ProcessingState enum value (e.g. a future "stalled")
      // we haven't taught the map about. The old `[..]!` null-bang would
      // crash the playback handler the first time the new value showed
      // up — idle is the only sound default since it stops the lock-screen
      // controls from claiming progress that isn't happening.
      processingState: const {
            ProcessingState.idle: AudioProcessingState.idle,
            ProcessingState.loading: AudioProcessingState.loading,
            ProcessingState.buffering: AudioProcessingState.buffering,
            ProcessingState.ready: AudioProcessingState.ready,
            ProcessingState.completed: AudioProcessingState.completed,
          }[_player.processingState] ??
          AudioProcessingState.idle,
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
    ));
  }
}
