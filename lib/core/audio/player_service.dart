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

  /// Original (unshuffled) queue order — stored when shuffle is toggled
  /// ON so we can restore it when shuffle is toggled OFF.
  List<AfTrack> _originalQueue = [];

  /// Dart-managed shuffle state. We don't use mpv's setShuffle because
  /// it physically reorders the playlist and emits index-change events
  /// that race with our state sync.
  bool _shuffleEnabled = false;
  final _shuffleController = StreamController<bool>.broadcast();

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

  /// Suppresses the playlist stream listener during shuffle reorder so
  /// the UI doesn't flash a wrong track while _trackQueue is being rebuilt.
  bool _suppressPlaylistSync = false;

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
  Stream<bool> get shuffleModeStream => _shuffleController.stream;
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

  // ---------------------------------------------------------------------------
  // Audio hardware & routing
  // ---------------------------------------------------------------------------

  /// Set the audio output driver (e.g. 'auto', 'opensles', 'aaudio').
  Future<void> setAudioDriver(String driver) async {
    await _player.setAudioDriver(driver);
    afLog('audio', 'audioDriver set to $driver');
  }

  /// Enable/disable exclusive mode (bypasses OS mixer for bit-perfect output).
  Future<void> setAudioExclusive(bool enabled) async {
    await _player.setAudioExclusive(enabled);
    afLog('audio', 'audioExclusive=$enabled');
  }

  /// Force a specific output sample rate (0 = auto).
  Future<void> setAudioSampleRate(int rate) async {
    await _player.setAudioSampleRate(rate);
    afLog('audio', 'audioSampleRate=$rate');
  }

  /// Force a specific output bit depth format.
  Future<void> setAudioFormat(Format format) async {
    await _player.setAudioFormat(format);
    afLog('audio', 'audioFormat=$format');
  }

  /// Force a specific channel layout.
  Future<void> setAudioChannels(Channels channels) async {
    await _player.setAudioChannels(channels);
    afLog('audio', 'audioChannels=$channels');
  }

  /// S/PDIF passthrough for compressed audio (AC3, DTS, etc.).
  Future<void> setAudioSpdif(Set<Spdif> codecs) async {
    await _player.setAudioSpdif(codecs);
    afLog('audio', 'audioSpdif=$codecs');
  }

  /// Current audio output parameters (sample rate, format, channels).
  Stream<AudioParams> get audioOutParamsStream => _player.stream.audioOutParams;
  AudioParams get audioOutParams => _player.state.audioOutParams;

  // ---------------------------------------------------------------------------
  // Network & caching
  // ---------------------------------------------------------------------------

  /// Set cache configuration (mode, duration, disk overflow, pause behavior).
  Future<void> setCache(CacheSettings settings) async {
    await _player.setCache(settings);
    afLog('audio', 'cache set: mode=${settings.mode} secs=${settings.secs}');
  }

  CacheSettings get cacheSettings => _player.state.cache;
  Stream<CacheSettings> get cacheStream => _player.stream.cache;

  /// Maximum bytes the demuxer caches ahead (default: 150 MiB).
  Future<void> setDemuxerMaxBytes(int bytes) async {
    await _player.setDemuxerMaxBytes(bytes);
    afLog('audio', 'demuxerMaxBytes=${bytes ~/ (1024 * 1024)} MiB');
  }

  /// Maximum bytes for the seekback buffer (default: 50 MiB).
  Future<void> setDemuxerMaxBackBytes(int bytes) async {
    await _player.setDemuxerMaxBackBytes(bytes);
    afLog('audio', 'demuxerMaxBackBytes=${bytes ~/ (1024 * 1024)} MiB');
  }

  /// How many seconds ahead the demuxer should read (default: 1).
  Future<void> setDemuxerReadaheadSecs(int secs) async {
    await _player.setDemuxerReadaheadSecs(secs);
    afLog('audio', 'demuxerReadaheadSecs=$secs');
  }

  /// Network timeout — fail after this duration of no data.
  Future<void> setNetworkTimeout(Duration timeout) async {
    await _player.setNetworkTimeout(timeout);
    afLog('audio', 'networkTimeout=${timeout.inSeconds}s');
  }

  /// Hardware audio buffer size. Lower = less latency, higher = more stable.
  Future<void> setAudioBuffer(Duration buffer) async {
    await _player.setAudioBuffer(buffer);
    afLog('audio', 'audioBuffer=${buffer.inMilliseconds}ms');
  }

  /// Keep audio hardware active when paused (eliminates click/pop on resume).
  Future<void> setAudioStreamSilence(bool enabled) async {
    await _player.setAudioStreamSilence(enabled);
    afLog('audio', 'audioStreamSilence=$enabled');
  }

  /// Read current audio hardware state.
  bool get audioExclusive => _player.state.audioExclusive;
  Stream<bool> get audioExclusiveStream => _player.stream.audioExclusive;
  bool get audioStreamSilence => _player.state.audioStreamSilence;
  Stream<bool> get audioStreamSilenceStream => _player.stream.audioStreamSilence;
  Duration get audioBuffer => _player.state.audioBuffer;
  Stream<Duration> get audioBufferStream => _player.stream.audioBuffer;

  // ---------------------------------------------------------------------------
  // Playback state & buffering
  // ---------------------------------------------------------------------------

  /// Aggregate playback lifecycle — one enum instead of checking
  /// playing + buffering + completed separately.
  Stream<MpvPlaybackState> get mpvPlaybackStateStream =>
      _player.stream.playbackState;

  /// True when the player is buffering (network stall or initial load).
  Stream<bool> get bufferingStream => _player.stream.buffering;
  bool get isBuffering => _player.state.buffering;

  /// Cache fill percentage (0–100) relative to configured cache duration.
  Stream<double> get bufferingPercentageStream =>
      _player.stream.bufferingPercentage;
  double get bufferingPercentage => _player.state.bufferingPercentage;

  /// Volume control.
  Stream<double> get volumeStream => _player.stream.volume;
  double get volume => _player.state.volume;
  Future<void> setVolume(double vol) async {
    await _player.setVolume(vol);
    afLog('audio', 'volume=$vol');
  }

  /// Mute control.
  Stream<bool> get muteStream => _player.stream.mute;
  bool get isMuted => _player.state.mute;
  Future<void> setMute(bool muted) async {
    await _player.setMute(muted);
    afLog('audio', 'mute=$muted');
  }

  // ---------------------------------------------------------------------------
  // Audio quality info
  // ---------------------------------------------------------------------------

  /// Live audio bitrate (bytes/sec) — feed quality chip with real data.
  Stream<double?> get audioBitrateStream => _player.stream.audioBitrate;
  double? get audioBitrate => _player.state.audioBitrate;

  /// Decoder-side audio params (codec, sample rate before output conversion).
  Stream<AudioParams> get audioParamsStream => _player.stream.audioParams;
  AudioParams get audioParams => _player.state.audioParams;

  /// Prefetch lifecycle — "next track ready" indicator for gapless.
  Stream<MpvPrefetchState> get prefetchStateStream =>
      _player.stream.prefetchState;

  /// Error stream — playback failures and engine errors.
  Stream<MpvPlayerError> get errorStream => _player.stream.error;

  // ---------------------------------------------------------------------------
  // A-B Loop
  // ---------------------------------------------------------------------------

  /// Set the A marker (start of loop). Null disables.
  Future<void> setAbLoopA(Duration? position) async {
    await _player.setAbLoopA(position);
    afLog('audio', 'abLoopA=${position?.inMilliseconds}ms');
  }

  /// Set the B marker (end of loop). Null disables.
  Future<void> setAbLoopB(Duration? position) async {
    await _player.setAbLoopB(position);
    afLog('audio', 'abLoopB=${position?.inMilliseconds}ms');
  }

  /// Limit loop repetitions. Null = infinite.
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

  /// Replace the entire DSP effects bundle.
  Future<void> setAudioEffects(AudioEffects effects) async {
    final optimized = _autoBypassFlat(effects);
    await _player.setAudioEffects(optimized);
    afLog('audio', 'audioEffects set');
  }

  /// Mutate one or more DSP fields via copyWith mapper.
  Future<void> updateAudioEffects(
      AudioEffects Function(AudioEffects) mapper) async {
    await _player.updateAudioEffects((current) {
      final updated = mapper(current);
      return _autoBypassFlat(updated);
    });
    afLog('audio', 'audioEffects updated');
  }

  /// mpv_audio_kit strictly controls the 'af' chain via the typed bundle.
  /// To drop a flat filter from the graph, we intercept the update and flip
  /// its built-in `enabled` flag to false.
  AudioEffects _autoBypassFlat(AudioEffects fx) {
    return fx.copyWith(
      // Bypass bass shelf if gain (g) is 0
      bass: fx.bass.copyWith(
        enabled: fx.bass.enabled && fx.bass.g != 0,
      ),
      // Bypass treble shelf if gain (g) is 0
      treble: fx.treble.copyWith(
        enabled: fx.treble.enabled && fx.treble.g != 0,
      ),
      // Bypass 18-band graphic EQ if all active bands are flat
      superequalizer: fx.superequalizer.copyWith(
        enabled: fx.superequalizer.enabled &&
                 fx.superequalizer.params.values.any((gain) => gain != 0.0),
      ),
    );
  }

  Stream<AudioEffects> get audioEffectsStream => _player.stream.audioEffects;
  AudioEffects get audioEffects => _player.state.audioEffects;

  /// ReplayGain normalization settings.
  Future<void> setReplayGain(ReplayGainSettings settings) async {
    await _player.setReplayGain(settings);
    afLog('audio', 'replayGain mode=${settings.mode}');
  }

  Stream<ReplayGainSettings> get replayGainStream => _player.stream.replayGain;
  ReplayGainSettings get replayGain => _player.state.replayGain;

  // ---------------------------------------------------------------------------
  // Gapless & prefetch
  // ---------------------------------------------------------------------------

  /// Set gapless playback mode.
  Future<void> setGapless(Gapless mode) async {
    await _player.setGapless(mode);
    afLog('audio', 'gapless=${mode.name}');
  }

  Gapless get gaplessMode => _player.state.gapless;
  Stream<Gapless> get gaplessStream => _player.stream.gapless;

  /// Enable background prefetch of the next playlist entry.
  Future<void> setPrefetchPlaylist(bool enabled) async {
    await _player.setPrefetchPlaylist(enabled);
    afLog('audio', 'prefetchPlaylist=$enabled');
  }

  bool get prefetchPlaylist => _player.state.prefetchPlaylist;

  /// Real-time FFT spectrum — 64 log-spaced bands in [0, 1] at ~30 fps.
  /// No RECORD_AUDIO permission needed. Lazy: pipeline starts on first
  /// listener, stops on last cancel.
  ///
  /// Captured post-DSP (mpv `pcm-tap-frame`). A pre-DSP tap is not
  /// available in mpv_audio_kit 0.1.3; the visualizer therefore
  /// reflects processed audio when effects are active.
  Stream<FftFrame> get spectrumStream => _player.stream.spectrum;

  /// Configure the spectrum pipeline for visualizer use.
  /// Called once after the player is ready.
  ///
  /// The engine's native EMA (attack 0.65, release 0.15) handles all
  /// bounce physics in C++. The client renders bands instantly with no
  /// Dart-side smoothing — only a fade-out ticker runs when audio stops.
  ///
  ///   fftSize: 2048     — sub-50 Hz resolution at 48 kHz, <43 ms block
  ///   bandCount: 64     — matches renderer 1:1, no resampling
  ///   bandLowHz: 20     — full audible range (pipeline handles Nyquist)
  ///   bandHighHz: 20000
  ///   window: hann      — universal music-visualizer default
  ///   attackSmoothing 0.8  — fast attack for punch
  ///   releaseSmoothing 0.1 — slow release for bouncy decay
  ///   minDb -105 / maxDb 35 — very wide range for maximum dynamic headroom
  ///   emitInterval 8ms  — 120 fps motion
  Future<void> configureSpectrum() async {
    try {
      // Enable gapless playback — mpv pre-fetches the next track so
      // transitions are seamless and auto-advance works correctly.
      await _player.setGapless(Gapless.weak);
      // Use AAudio as the default audio output driver on Android.
      // AAudio provides lower latency and better compatibility than
      // OpenSL ES on Android 8.1+ (API 27+). Falls back gracefully
      // on older devices.
      await _player.setAudioDriver('aaudio');
      await _player.setSpectrum(const SpectrumSettings(
        fftSize: 2048,
        bandCount: 64,
        bandLowHz: 20.0,
        bandHighHz: 20000.0,
        // Engine C++ handles bounce physics now.
        attackSmoothing: 0.8,  // Fast attack for punch
        releaseSmoothing: 0.1, // Slow release for bouncy decay
        minDb: -105.0,          // Very wide range for maximum dynamic headroom
        maxDb: 35.0,
        emitInterval: Duration(milliseconds: 8),
      ));
    } catch (e) {
      afLog('audio', 'configureSpectrum failed', error: e);
    }
  }

  Duration get position => _player.state.position;
  List<AfTrack> get currentQueue => List.unmodifiable(_trackQueue);
  AfTrack? get currentTrack =>
      (_currentIndex >= 0 && _currentIndex < _trackQueue.length)
          ? _trackQueue[_currentIndex]
          : null;
  bool get isPlaying => _player.state.playing;
  bool get isShuffleEnabled => _shuffleEnabled;
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

    // Store the original order for shuffle restore.
    _originalQueue = _shuffleEnabled ? List.of(tracks) : [];

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

  /// Toggle shuffle mode using mpv's native playlist-shuffle / playlist-unshuffle
  /// commands which reorder the playlist WITHOUT interrupting playback.
  ///
  /// Behavior:
  /// - Toggle ON: mpv shuffles the playlist. We wait for the playlist
  ///   stream event to get the actual new order, then sync _trackQueue.
  /// - Toggle OFF: mpv restores original load order. Same sync.
  /// - Never changes the currently displayed/playing song.
  Future<void> setAfShuffleMode(bool enabled) async {
    if (_shuffleEnabled == enabled) return;
    _shuffleEnabled = enabled;
    _shuffleController.add(enabled);

    final playingTrack = currentTrack;
    if (_trackQueue.isEmpty) {
      afLog('data', 'shuffleMode source=live enabled=$enabled (queue empty)');
      return;
    }

    // Suppress playlist listener so it doesn't emit a track change.
    _suppressPlaylistSync = true;

    // Save original order before first shuffle.
    if (enabled && _originalQueue.isEmpty) {
      _originalQueue = List.of(_trackQueue);
    }

    // Call mpv's native shuffle/unshuffle — doesn't interrupt playback.
    await _player.setShuffle(enabled);

    // Wait for the playlist stream to emit the new order. This is the
    // only reliable way to get mpv's actual post-shuffle state — reading
    // _player.state.playlist synchronously can return stale data.
    try {
      final newPlaylist = await _player.stream.playlist
          .first
          .timeout(const Duration(seconds: 2));

      _syncTrackQueueFromMpv(newPlaylist.items, newPlaylist.index);
    } catch (e) {
      afLog('audio', 'shuffle playlist stream timeout, using state fallback', error: e);
      final mpvItems = _player.state.playlist.items;
      final newIdx = _player.state.playlist.index;
      _syncTrackQueueFromMpv(mpvItems, newIdx);
    }

    if (!enabled) _originalQueue = [];

    _suppressPlaylistSync = false;

    // Emit updated queue without changing the displayed track.
    _queueController.add(List.unmodifiable(_trackQueue));
    if (playingTrack != null) {
      _trackController.add(playingTrack);
    }

    afLog('data', 'shuffleMode source=live enabled=$enabled '
        'queueSize=${_trackQueue.length} currentIndex=$_currentIndex');
  }

  /// Syncs _trackQueue to match mpv's playlist order by extracting track
  /// IDs from Media URIs and looking them up in our known tracks.
  void _syncTrackQueueFromMpv(List<Media> mpvItems, int newIdx) {
    if (mpvItems.isEmpty) return;

    // Build lookup from ALL known tracks.
    final byId = <String, AfTrack>{};
    for (final t in _trackQueue) {
      byId[t.id] = t;
    }
    for (final t in _originalQueue) {
      byId[t.id] = t;
    }

    final reordered = <AfTrack>[];
    for (final media in mpvItems) {
      final id = _extractTrackId(media.uri);
      final track = id != null ? byId[id] : null;
      if (track != null) {
        reordered.add(track);
      }
    }

    if (reordered.length == mpvItems.length) {
      _trackQueue
        ..clear()
        ..addAll(reordered);
      _currentIndex = newIdx.clamp(0, _trackQueue.length - 1);
    }
  }

  /// Extracts the track ID from a stream URL.
  ///
  /// Supports both URL formats:
  ///   Jellyfin:  `.../Audio/{trackId}/stream?...`
  ///   Subsonic:  `.../rest/stream.view?id={trackId}&...`
  static String? _extractTrackId(String uri) {
    final parsed = Uri.tryParse(uri);
    if (parsed == null) return null;
    // Jellyfin: /Audio/{id}/stream
    final segments = parsed.pathSegments;
    for (var i = 0; i < segments.length - 1; i++) {
      if (segments[i].toLowerCase() == 'audio') {
        return segments[i + 1];
      }
    }
    // Subsonic: /rest/stream.view?id={id}
    final queryId = parsed.queryParameters['id'];
    if (queryId != null && queryId.isNotEmpty) return queryId;
    return null;
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

  /// Insert [track] immediately after the current track (play next).
  /// If nothing is playing, appends to the end.
  Future<void> playNext(
    AfTrack track, {
    required String Function(AfTrack) resolveStreamUrl,
  }) async {
    final insertAt = _currentIndex >= 0 && _currentIndex < _trackQueue.length
        ? _currentIndex + 1
        : _trackQueue.length;

    _trackQueue.insert(insertAt, track);
    await _player.sendRawCommand([
      'loadfile',
      resolveStreamUrl(track),
      'insert-at',
      '$insertAt',
    ]);
    _queueController.add(List.unmodifiable(_trackQueue));
    afLog('audio', 'playNext "${track.title}" at index=$insertAt');
  }

  /// Append [track] to the end of the queue.
  Future<void> addToQueue(
    AfTrack track, {
    required String Function(AfTrack) resolveStreamUrl,
  }) async {
    _trackQueue.add(track);
    await _player.sendRawCommand([
      'loadfile',
      resolveStreamUrl(track),
      'append',
    ]);
    _queueController.add(List.unmodifiable(_trackQueue));
    afLog('audio', 'addToQueue "${track.title}" at end');
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final s in _subs) {
      await s.cancel();
    }
    await _trackController.close();
    await _queueController.close();
    await _shuffleController.close();
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
      if (_suppressPlaylistSync) return;

      final indexChanged = idx != _currentIndex;

      // Capture the track that was playing *before* updating the index.
      final previousTrackId = (_currentIndex >= 0 &&
              _currentIndex < _trackQueue.length)
          ? _trackQueue[_currentIndex].id
          : null;

      _currentIndex = idx;

      if (indexChanged) {
        final track = _trackQueue[idx];

        // Guard: if the track identity hasn't actually changed (same ID),
        // skip the emission. This happens during shuffle — mpv reorders
        // the playlist and emits a new index, but the audio keeps playing
        // the same file.
        if (track.id == previousTrackId) return;

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

        // Force position to reset — mpv's state.position can remain at
        // the previous track's end position until the new file's demuxer
        // opens. A seek(0) kicks the position reporting back to life.
        unawaited(_player.seek(Duration.zero).catchError((_) {}));

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
    } catch (e) {
      afLog('audio', 'cover art persist failed', error: e);
    }
  }
}
