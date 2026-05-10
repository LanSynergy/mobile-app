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

  AfPlayerService() {
    _player.playbackEventStream.listen(_broadcastPlaybackEvent);
    _player.currentIndexStream.listen((idx) {
      if (idx == null) return;
      _currentIndex = idx;
      mediaItem.add(_mediaItemFor(_trackQueue[idx]));
    });
  }

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<bool> get playingStream => _player.playingStream;
  Stream<ProcessingState> get stateStream => _player.processingStateStream;
  Duration get position => _player.position;
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
    mediaItem.add(_mediaItemFor(tracks[startIndex]));
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
