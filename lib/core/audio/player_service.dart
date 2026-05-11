import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

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
    _player.playbackEventStream.listen(_broadcastPlaybackEvent);
    _player.currentIndexStream.listen((idx) {
      if (idx == null) return;
      if (idx < 0 || idx >= _trackQueue.length) return;
      _currentIndex = idx;
      final track = _trackQueue[idx];
      mediaItem.add(_mediaItemFor(track));
      _trackController.add(track);
      // ignore: avoid_print
      print(
        'aetherfin:data currentTrack source=live id=${track.id} '
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
  Duration get position => _player.position;
  List<AfTrack> get currentQueue => List.unmodifiable(_trackQueue);
  AfTrack? get currentTrack =>
      (_currentIndex >= 0 && _currentIndex < _trackQueue.length)
          ? _trackQueue[_currentIndex]
          : null;

  /// Replace the queue with [tracks] and start playback at [startIndex].
  Future<void> playQueue(
    List<AfTrack> tracks, {
    int startIndex = 0,
    required String Function(AfTrack track) resolveStreamUrl,
  }) async {
    _trackQueue
      ..clear()
      ..addAll(tracks);
    queue.add(tracks.map(_mediaItemFor).toList());
    _queueController.add(List.unmodifiable(_trackQueue));
    final sources = tracks
        .map((t) => AudioSource.uri(
              Uri.parse(resolveStreamUrl(t)),
              tag: _mediaItemFor(t),
            ))
        .toList();
    await _player.setAudioSource(
      ConcatenatingAudioSource(children: sources),
      initialIndex: startIndex,
    );
    _currentIndex = startIndex;
    final startTrack = tracks[startIndex];
    mediaItem.add(_mediaItemFor(startTrack));
    _trackController.add(startTrack);
    // ignore: avoid_print
    print(
      'aetherfin:data playQueue source=live size=${tracks.length} '
      'startIndex=$startIndex first="${startTrack.title}"',
    );
    onTrackChanged?.call(startTrack);
    await _player.play();
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
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
    ));
  }
}
