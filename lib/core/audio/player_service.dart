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

  final List<StreamSubscription<dynamic>> _subs = [];

  /// Monotonic counter for cover-art temp files so the OS media widget
  /// doesn't cache stale artwork when the path stays the same.
  int _coverCounter = 0;
  String? _coverPath;

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
  Future<void> configureSpectrum() async {
    try {
      // Enable gapless playback — mpv pre-fetches the next track so
      // transitions are seamless and auto-advance works correctly.
      await _player.setGapless(Gapless.weak);
      await _player.setSpectrum(const SpectrumSettings(
        bandCount: 64,
        // Wide dB window so the full dynamic range of music is visible.
        // -90 dB floor = silence. -3 dB ceiling = near-clipping peaks.
        // A signal at -18 dBFS (typical loud music) maps to ~0.80,
        // a signal at -40 dBFS (quiet passage) maps to ~0.57 — giving
        // visible movement across the whole dynamic range.
        // Previously -50..-3 (47 dB) caused quiet sounds to saturate at 0.68+.
        minDb: -90.0,
        maxDb: -3.0,
        // Disable mpv's own EMA smoothing — the widget applies its own
        // asymmetric attack/decay lerp which gives better visual control.
        // With mpv smoothing ON, bars stay elevated between beats and
        // the visualizer looks "stuck at max".
        attackSmoothing: 0.0,
        releaseSmoothing: 0.0,
        emitInterval: Duration(milliseconds: 16), // ~60 fps
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
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

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
    for (final s in _subs) {
      await s.cancel();
    }
    await _trackController.close();
    await _queueController.close();
    await _player.dispose();
  }

  // ---------------------------------------------------------------------------
  // Internal stream wiring
  // ---------------------------------------------------------------------------

  void _bindStreams() {
    // Sync current track when the playlist index changes.
    // Also handles auto-advance: when mpv moves to the next track (either
    // via gapless or manual skip), we update our state and ensure playback
    // is running. This replaces the fragile `completed` stream approach
    // which raced with mpv's internal state updates.
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

        // Ensure playback resumes after auto-advance. mpv with Gapless.weak
        // advances the index but may leave the player in a paused state.
        // We give it a short window to start playing on its own, then
        // nudge it if it hasn't.
        Future.delayed(const Duration(milliseconds: 150), () {
          if (_currentIndex == idx && !_player.state.playing) {
            _player.play();
            afLog('audio', 'auto-advance nudge play() at index=$idx');
          }
        });
      }
    }));

    // Sync playback state to audio_service.
    _subs.add(_player.stream.playing.listen((_) => _updatePlaybackState()));
    _subs.add(_player.stream.position.listen((_) => _updatePlaybackState()));
    _subs.add(_player.stream.buffering.listen((_) => _updatePlaybackState()));
    _subs.add(_player.stream.completed.listen((_) => _updatePlaybackState()));
    _subs.add(_player.stream.rate.listen((_) => _updatePlaybackState()));

    // Fallback auto-advance via completed stream: handles the case where
    // mpv signals completion but doesn't advance the playlist index
    // (e.g. last track in queue with loop=none, or gapless disabled).
    _subs.add(_player.stream.completed.listen((completed) {
      if (!completed) return;
      final nextIdx = _currentIndex + 1;
      if (nextIdx < _trackQueue.length) {
        // mpv should have already advanced via the playlist stream above.
        // This is a safety net for edge cases where it hasn't.
        Future.delayed(const Duration(milliseconds: 300), () {
          final currentMpvIdx = _player.state.playlist.index;
          if (currentMpvIdx == nextIdx && !_player.state.playing) {
            _player.play();
            afLog('audio', 'completed fallback: play() at index=$nextIdx');
          } else if (currentMpvIdx == _currentIndex) {
            // mpv didn't advance — force jump to next track.
            _player.jump(nextIdx).then((_) {
              Future.delayed(const Duration(milliseconds: 100), () {
                _player.play();
              });
            });
            afLog('audio', 'completed fallback: jump+play to index=$nextIdx');
          }
        });
      }
    }));

    // Persist embedded cover art to a temp file for the OS media widget.
    _subs.add(_player.stream.coverArt.listen(_persistCover));
  }

  void _updatePlaybackState() {
    final s = _player.state;
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          s.playing ? MediaControl.pause : MediaControl.play,
          MediaControl.stop,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 3],
        processingState: s.buffering
            ? AudioProcessingState.buffering
            : s.completed
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
    final path =
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'aetherfin_cover_$id.$ext';
    try {
      await File(path).writeAsBytes(raw.bytes, flush: true);
      _coverPath = path;
      _updateMediaItem();
    } catch (_) {
      // Disk full / sandbox — fall back to network URL in _updateMediaItem.
    }
  }
}