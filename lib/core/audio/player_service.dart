import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../../utils/log.dart';
import '../jellyfin/models/items.dart';

/// Stores a snapshot of playback position for elapsed-time extrapolation.
/// Used when mpv's observe_property/getRawProperty for time-pos stalls.
class _PositionAnchor {
  Duration lastKnownPos = Duration.zero;
  DateTime lastUpdateTime = DateTime.now();
  bool wasPlaying = false;
}

/// Bridges [Player] (mpv_audio_kit) with [audio_service] so the OS
/// lock-screen / notification controls drive playback.
class AfPlayerService extends BaseAudioHandler with SeekHandler, QueueHandler {
  final Player _player;

  final List<AfTrack> _trackQueue = <AfTrack>[];
  int _currentIndex = -1;
  List<AfTrack> _originalQueue = <AfTrack>[];
  final Map<String, AfTrack> _urlToTrack = <String, AfTrack>{};

  bool _shuffleEnabled = false;
  final _shuffleController = StreamController<bool>.broadcast();
  final _trackController = StreamController<AfTrack?>.broadcast();
  final _queueController = StreamController<List<AfTrack>>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();

  final _positionAnchor = _PositionAnchor();
  Timer? _positionPollTimer;
  bool _isSeeking = false;
  Timer? _seekResetTimer;
  bool _isPolling = false;

  /// Last raw mpv time-pos observed by the poller.
  ///
  /// Samsung One UI can get stuck returning the same non-zero value after a
  /// seek. The old fallback only handled rawPos == 0, so it kept trusting the
  /// frozen seek value forever. These fields detect a stale non-zero raw
  /// position and let the Dart-side extrapolator take over.
  Duration? _lastRawPolledPos;
  int _staleRawPollTicks = 0;
  static const _rawStaleTolerance = Duration(milliseconds: 250);
  static const _rawStaleAfterTicks = 4;

  void Function(AfTrack track)? onTrackChanged;
  final List<StreamSubscription<dynamic>> _subs = <StreamSubscription<dynamic>>[];

  int _coverCounter = 0;
  String? _coverPath;
  String? _networkCoverPath;
  static final HttpClient _httpClient = HttpClient();
  Map<String, String> _authHeaders = const <String, String>{};
  String? _networkCoverTrackId;
  bool _disposed = false;
  int _suppressPlaylistSyncGen = 0;
  int _activePlaylistSyncGen = 0;
  int _nudgeGen = 0;

  DateTime _lastPlaybackStatePush = DateTime.fromMillisecondsSinceEpoch(0);
  bool _lastPushedPlaying = false;
  bool _lastPushedBuffering = false;

  int _nudgeRetries = 0;
  static const _maxNudgeRetries = 3;

  /// Last `audio-device` name observed from mpv. Used by the
  /// `_player.stream.audioDevice` listener to skip duplicate
  /// emissions (mpv re-emits the same device on some property
  /// polls), so we only re-apply the filter chain on *real*
  /// device transitions. `null` until the first emission.
  String? _lastObservedAudioDevice;

  int? _pendingPlayNudgeIdx;
  bool _userPaused = false;

  AfPlayerService() : _player = Player() {
    // Set audio driver BEFORE binding streams. If setAudioDriver is called
    // after property observation starts, it can re-initialize the output
    // pipeline and break time-pos observation until output is re-selected.
    _player.setAudioDriver('aaudio');

    // 200 ms keeps background playback stable under Android Doze.
    _player.setAudioBuffer(const Duration(milliseconds: 200));
    _bindStreams();

    // Default to 'auto' (Autoselect devices) after streams are bound.
    // mpv starts on a specific device; we switch to 'auto' so the UI
    // shows "Autoselect devices" on first launch. setAudioDevice() no
    // longer calls _nudgeAudioDevice(), so the selection won't bounce back.
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

  // ---------------------------------------------------------------------------
  // Public stream surface
  // ---------------------------------------------------------------------------

  Stream<Duration> get positionStream => _positionController.stream;
  Stream<bool> get playingStream => _player.stream.playing;
  Stream<Duration> get audioPtsStream => _player.stream.audioPts;
  Stream<double> get percentPosStream => _player.stream.percentPos;
  double get percentPos => _player.state.percentPos;
  Stream<AfTrack?> get currentTrackStream => _trackController.stream;
  Stream<List<AfTrack>> get queueStream => _queueController.stream;
  Stream<bool> get shuffleModeStream => _shuffleController.stream;
  Stream<Loop> get loopModeStream => _player.stream.loop;
  Stream<double> get speedStream => _player.stream.rate;

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

  Future<void> setAudioDriver(String driver) async {
    await _player.setAudioDriver(driver);
    afLog('audio', 'audioDriver set to $driver');
  }

  Future<void> setAudioExclusive(bool enabled) async {
    await _player.setAudioExclusive(enabled);
    afLog('audio', 'audioExclusive=$enabled');
    _nudgeAudioDevice();
  }

  Future<void> setAudioSampleRate(int rate) async {
    await _player.setAudioSampleRate(rate);
    afLog('audio', 'audioSampleRate=$rate');
  }

  Future<void> setAudioFormat(Format format) async {
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
    await _player.setAudioBuffer(buffer);
    afLog('audio', 'audioBuffer=${buffer.inMilliseconds}ms');
  }

  Future<void> setAudioStreamSilence(bool enabled) async {
    await _player.setAudioStreamSilence(enabled);
    afLog('audio', 'audioStreamSilence=$enabled');
  }

  bool get audioExclusive => _player.state.audioExclusive;
  Stream<bool> get audioExclusiveStream => _player.stream.audioExclusive;
  bool get audioStreamSilence => _player.state.audioStreamSilence;
  Stream<bool> get audioStreamSilenceStream => _player.stream.audioStreamSilence;
  Duration get audioBuffer => _player.state.audioBuffer;
  Stream<Duration> get audioBufferStream => _player.stream.audioBuffer;

  // ---------------------------------------------------------------------------
  // Playback state & buffering
  // ---------------------------------------------------------------------------

  Stream<MpvPlaybackState> get mpvPlaybackStateStream =>
      _player.stream.playbackState;
  Stream<bool> get bufferingStream => _player.stream.buffering;
  bool get isBuffering => _player.state.buffering;
  Stream<double> get bufferingPercentageStream => _player.stream.bufferingPercentage;
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
    final optimized = _autoBypassFlat(effects);
    await _player.setAudioEffects(optimized);
    afLog('audio', 'audioEffects set');
  }

  Future<void> updateAudioEffects(AudioEffects Function(AudioEffects) mapper) async {
    await _player.updateAudioEffects((current) {
      final updated = mapper(current);
      return _autoBypassFlat(updated);
    });
    afLog('audio', 'audioEffects updated');
  }

  AudioEffects _autoBypassFlat(AudioEffects fx) => autoBypassFlat(fx);

  Stream<AudioEffects> get audioEffectsStream => _player.stream.audioEffects;
  AudioEffects get audioEffects => _player.state.audioEffects;

  Future<void> setReplayGain(ReplayGainSettings settings) async {
    await _player.setReplayGain(settings);
    afLog('audio', 'replayGain mode=${settings.mode}');
  }

  Stream<ReplayGainSettings> get replayGainStream => _player.stream.replayGain;
  ReplayGainSettings get replayGain => _player.state.replayGain;

  // ---------------------------------------------------------------------------
  // Gapless & prefetch
  // ---------------------------------------------------------------------------

  Future<void> setGapless(Gapless mode) async {
    await _player.setGapless(mode);
    afLog('audio', 'gapless=${mode.name}');
  }

  Gapless get gaplessMode => _player.state.gapless;
  Stream<Gapless> get gaplessStream => _player.stream.gapless;

  Future<void> setPrefetchPlaylist(bool enabled) async {
    await _player.setPrefetchPlaylist(enabled);
    afLog('audio', 'prefetchPlaylist=$enabled');
  }

  bool get prefetchPlaylist => _player.state.prefetchPlaylist;

  Stream<FftFrame> get spectrumStream => _player.stream.spectrum;

  Future<void> configureSpectrum() async {
    try {
      await _player.setSpectrum(const SpectrumSettings(
        fftSize: 2048,
        bandCount: 64,
        bandLowHz: 20.0,
        bandHighHz: 20000.0,
        attackSmoothing: 0.8,
        releaseSmoothing: 0.1,
        minDb: -105.0,
        maxDb: 35.0,
        emitInterval: Duration(milliseconds: 8),
      ));
    } catch (e) {
      afLog('audio', 'configureSpectrum failed', error: e);
    }
  }

  Duration get position => _player.state.position;
  Duration get duration => _player.state.duration;
  Stream<Duration> get durationStream => _player.stream.duration;

  Future<Duration> getRawPosition() async {
    try {
      final raw = await _player.getRawProperty('time-pos');
      if (raw == null) return Duration.zero;
      final secs = double.tryParse(raw);
      if (secs == null || secs < 0) return Duration.zero;
      return Duration(milliseconds: (secs * 1000).round());
    } catch (_) {
      return Duration.zero;
    }
  }

  Future<Duration> getRawDuration() async {
    try {
      final raw = await _player.getRawProperty('duration');
      if (raw == null) return Duration.zero;
      final secs = double.tryParse(raw);
      if (secs == null || secs <= 0) return Duration.zero;
      return Duration(milliseconds: (secs * 1000).round());
    } catch (_) {
      return Duration.zero;
    }
  }

  List<AfTrack> get currentQueue => List<AfTrack>.unmodifiable(_trackQueue);

  AfTrack? get currentTrack =>
      (_currentIndex >= 0 && _currentIndex < _trackQueue.length)
          ? _trackQueue[_currentIndex]
          : null;

  bool get isPlaying => _player.state.playing;
  bool get isCompleted => _player.state.completed;
  bool get isUserPaused => _userPaused;

  /// True when UI/notification progress should keep advancing even if mpv's
  /// reported `playing` flag is temporarily stale/false on an OEM pipeline.
  bool get shouldAdvancePosition {
    final hasTrack = currentTrack != null;
    final completedAtQueueEnd =
        _player.state.completed && _currentIndex >= _trackQueue.length - 1;
    return hasTrack &&
        !completedAtQueueEnd &&
        !_userPaused &&
        _pendingPlayNudgeIdx == null;
  }

  bool get isShuffleEnabled => _shuffleEnabled;
  Loop get loopMode => _player.state.loop;
  double get speed => _player.state.rate;

  // ---------------------------------------------------------------------------
  // Playback control
  // ---------------------------------------------------------------------------

  void setAuthHeaders(Map<String, String> headers) {
    _authHeaders = headers;
  }

  Future<void> playQueue(
    List<AfTrack> tracks, {
    int startIndex = 0,
    required String Function(AfTrack track) resolveStreamUrl,
    Map<String, String> streamHeaders = const <String, String>{},
  }) async {
    if (tracks.isEmpty) return;

    final safeIndex = startIndex.clamp(0, tracks.length - 1);
    if (streamHeaders.isNotEmpty) {
      _authHeaders = streamHeaders;
    }

    _trackQueue
      ..clear()
      ..addAll(tracks);
    _currentIndex = safeIndex;
    _queueController.add(List<AfTrack>.unmodifiable(_trackQueue));
    _originalQueue = _shuffleEnabled ? List<AfTrack>.of(tracks) : <AfTrack>[];

    final startTrack = tracks[safeIndex];
    _trackController.add(startTrack);
    onTrackChanged?.call(startTrack);
    afLog(
      'data',
      'playQueue source=live size=${tracks.length} '
          'startIndex=$safeIndex first="${startTrack.title}"',
    );

    _urlToTrack.clear();
    final medias = tracks.map((t) {
      final url = resolveStreamUrl(t);
      _urlToTrack[url] = t;
      return Media(url);
    }).toList();

    try {
      // Reset position before opening new tracks. The playlist listener
      // won't fire indexChanged when the new index equals the old one
      // (e.g. tapping a different album at index 0), so we must reset here.
      _positionAnchor.lastKnownPos = Duration.zero;
      _positionAnchor.lastUpdateTime = DateTime.now();
      _positionAnchor.wasPlaying = true;
      _positionController.add(Duration.zero);
      _resetRawPositionStaleDetector(Duration.zero);

      if (medias.length <= 5) {
        await _player.openAll(medias, index: safeIndex, play: true);
      } else {
        _suppressPlaylistSyncGen++;
        _activePlaylistSyncGen = _suppressPlaylistSyncGen;
        await _player.open(medias[safeIndex], play: true);

        // Await all append adds so the playlist sync gen isn't reset
        // until mpv's playlist matches our Dart queue. If we reset
        // early, the playlist listener could see a partial mpv
        // playlist and corrupt _trackQueue.
        final addFutures = <Future<void>>[];
        for (var i = safeIndex + 1; i < medias.length; i++) {
          addFutures.add(_player.add(medias[i]));
        }
        await Future.wait(addFutures);

        for (var i = safeIndex - 1; i >= 0; i--) {
          await _player.sendRawCommand([
            'loadfile',
            medias[i].uri,
            'insert-at',
            '0',
          ]);
        }

        _currentIndex = safeIndex;
        _activePlaylistSyncGen = 0;
      }

      _nudgeAudioDevice();
    } catch (e, stack) {
      _activePlaylistSyncGen = 0;
      afLog('audio', 'playQueue failed', error: e, stackTrace: stack);
      _trackQueue.clear();
      _currentIndex = -1;
      _queueController.add(const <AfTrack>[]);
      _trackController.add(null);
      rethrow;
    }
  }

  @override
  Future<void> play() async {
    _userPaused = false;
    _positionAnchor.wasPlaying = true;
    _positionAnchor.lastKnownPos = _player.state.position;
    _positionAnchor.lastUpdateTime = DateTime.now();
    await _player.play();
    _nudgeAudioDevice();
  }

  @override
  Future<void> pause() async {
    _userPaused = true;
    _pendingPlayNudgeIdx = null;
    _positionAnchor.wasPlaying = false;
    _positionAnchor.lastKnownPos = _player.state.position;
    _positionAnchor.lastUpdateTime = DateTime.now();
    await _player.pause();
  }

  @override
  Future<void> stop() async {
    _userPaused = true;
    _pendingPlayNudgeIdx = null;
    _positionAnchor.wasPlaying = false;
    _positionAnchor.lastKnownPos = Duration.zero;
    _positionAnchor.lastUpdateTime = DateTime.now();
    _resetRawPositionStaleDetector(Duration.zero);
    _positionController.add(Duration.zero);
    await _player.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    _isSeeking = true;
    final now = DateTime.now();
    _positionAnchor.lastKnownPos = position;
    _positionAnchor.lastUpdateTime = now;
    _resetRawPositionStaleDetector(position);
    _positionController.add(position);
    _updatePlaybackState();

    try {
      await _player.seek(position);

      // Seeking is one reproducible trigger for the One UI freeze: raw
      // time-pos can keep returning the seeked value until the output pipeline
      // is nudged. This mirrors the manual "switch output device" fix.
      _nudgeAudioDevice();
    } finally {
      _seekResetTimer?.cancel();
      _seekResetTimer = Timer(const Duration(milliseconds: 300), () {
        if (!_disposed) _isSeeking = false;
      });
    }
  }

  @override
  Future<void> skipToNext() => _player.next();

  @override
  Future<void> skipToPrevious() => _player.previous();

  @override
  Future<void> skipToQueueItem(int index) => _player.jump(index);

  Future<void> setAfShuffleMode(bool enabled) async {
    if (_shuffleEnabled == enabled) return;
    _shuffleEnabled = enabled;
    _shuffleController.add(enabled);

    final playingTrack = currentTrack;
    if (_trackQueue.isEmpty) {
      afLog('data', 'shuffleMode source=live enabled=$enabled (queue empty)');
      return;
    }

    _suppressPlaylistSyncGen++;
    _activePlaylistSyncGen = _suppressPlaylistSyncGen;
    if (enabled && _originalQueue.isEmpty) {
      _originalQueue = List<AfTrack>.of(_trackQueue);
    }

    await _player.setShuffle(enabled);

    try {
      final newPlaylist = await _player.stream.playlist.first
          .timeout(const Duration(seconds: 2));
      _syncTrackQueueFromMpv(newPlaylist.items, newPlaylist.index);
    } catch (e) {
      afLog('audio', 'shuffle playlist stream timeout, using state fallback', error: e);
      final mpvItems = _player.state.playlist.items;
      final newIdx = _player.state.playlist.index;
      _syncTrackQueueFromMpv(mpvItems, newIdx);
    }

    if (!enabled) _originalQueue = <AfTrack>[];
    _activePlaylistSyncGen = 0;

    _queueController.add(List<AfTrack>.unmodifiable(_trackQueue));
    if (playingTrack != null) {
      _trackController.add(playingTrack);
    }

    afLog('data', 'shuffleMode source=live enabled=$enabled '
        'queueSize=${_trackQueue.length} currentIndex=$_currentIndex');
  }

  void _syncTrackQueueFromMpv(List<Media> mpvItems, int newIdx) {
    if (mpvItems.isEmpty) return;

    final byId = <String, AfTrack>{};
    for (final t in _trackQueue) {
      byId[t.id] = t;
    }
    for (final t in _originalQueue) {
      byId[t.id] = t;
    }

    final reordered = <AfTrack>[];
    for (final media in mpvItems) {
      var track = _urlToTrack[media.uri];
      if (track == null) {
        final id = _extractTrackId(media.uri);
        track = id != null ? byId[id] : null;
      }
      if (track != null) reordered.add(track);
    }

    if (reordered.length == mpvItems.length) {
      _trackQueue
        ..clear()
        ..addAll(reordered);
      _currentIndex = newIdx.clamp(0, _trackQueue.length - 1);
    } else if (reordered.isNotEmpty) {
      afLog(
        'audio',
        '_syncTrackQueueFromMpv partial sync: '
            'resolved ${reordered.length}/${mpvItems.length} tracks, '
            'updating with resolved subset',
      );
      _trackQueue
        ..clear()
        ..addAll(reordered);
      _currentIndex = newIdx.clamp(0, _trackQueue.length - 1);
    } else {
      afLog(
        'audio',
        '_syncTrackQueueFromMpv full sync failure: '
            'resolved 0/${mpvItems.length} tracks, clearing queue',
      );
      _trackQueue.clear();
      _currentIndex = 0;
    }
  }

  static String? _extractTrackId(String uri) {
    final parsed = Uri.tryParse(uri);
    if (parsed == null) return null;

    final segments = parsed.pathSegments;
    for (var i = 0; i < segments.length - 1; i++) {
      if (segments[i].toLowerCase() == 'audio') {
        return segments[i + 1];
      }
    }

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

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (oldIndex < 0 ||
        oldIndex >= _trackQueue.length ||
        newIndex < 0 ||
        newIndex > _trackQueue.length ||
        oldIndex == newIndex) {
      return;
    }

    final track = _trackQueue.removeAt(oldIndex);
    // After removal the list shrank by one. If the target was after the
    // removed item, shift the insertion index down.
    final insertIdx = newIndex > oldIndex ? newIndex - 1 : newIndex;
    _trackQueue.insert(insertIdx, track);
    await _player.sendRawCommand(['playlist-move', '$oldIndex', '$insertIdx']);

    if (_currentIndex == oldIndex) {
      _currentIndex = insertIdx;
    } else if (oldIndex < _currentIndex && insertIdx >= _currentIndex) {
      _currentIndex -= 1;
    } else if (oldIndex > _currentIndex && insertIdx <= _currentIndex) {
      _currentIndex += 1;
    }

    _queueController.add(List<AfTrack>.unmodifiable(_trackQueue));
    afLog(
      'audio',
      'reorderQueue oldIndex=$oldIndex newIndex=$newIndex '
          'currentIndex=$_currentIndex queueSize=${_trackQueue.length}',
    );
  }

  /// Remove a track from the queue at [index]. Refuses to remove the
  /// currently-playing item — callers should disable the affordance for
  /// the active row rather than rely on a silent no-op (so the user
  /// understands why the swipe was rejected). Returns `true` when the
  /// removal actually took effect.
  Future<bool> removeFromQueue(int index) async {
    if (_disposed) return false;
    if (index < 0 || index >= _trackQueue.length) return false;
    if (index == _currentIndex) {
      afLog('audio', 'removeFromQueue refused index=$index (currently playing)');
      return false;
    }

    // Send the mpv command first so the playlist index matches.
    // If mpv rejects it, the Dart queue stays intact.
    await _player.sendRawCommand(['playlist-remove', '$index']);

    _trackQueue.removeAt(index);

    // Removing an entry before the playhead shifts _currentIndex down by
    // one so the active track is still pointed at after mpv collapses
    // the playlist. Removing an entry after the playhead leaves
    // _currentIndex untouched.
    if (index < _currentIndex) {
      _currentIndex -= 1;
    }

    _queueController.add(List<AfTrack>.unmodifiable(_trackQueue));
    afLog(
      'audio',
      'removeFromQueue index=$index currentIndex=$_currentIndex '
          'queueSize=${_trackQueue.length}',
    );
    return true;
  }

  /// Insert [track] at an arbitrary [index] in the queue. Used to
  /// recover from a swipe-to-remove undo — the caller already knows
  /// the exact index the track came from, so we don't have to fall
  /// back to "play next" semantics.
  ///
  /// Indices outside `[0, _trackQueue.length]` are clamped. If the
  /// insertion lands at or before the currently playing index,
  /// `_currentIndex` shifts by one so the active track keeps pointing
  /// at the same audio entry after mpv expands the playlist.
  Future<void> insertIntoQueue(
    int index,
    AfTrack track, {
    required String Function(AfTrack) resolveStreamUrl,
  }) async {
    if (_disposed) return;
    final clamped = index.clamp(0, _trackQueue.length);
    final url = resolveStreamUrl(track);

    // Send mpv command first so the playlist index matches.
    await _player.sendRawCommand([
      'loadfile',
      url,
      'insert-at',
      '$clamped',
    ]);

    _trackQueue.insert(clamped, track);
    if (clamped <= _currentIndex) {
      _currentIndex += 1;
    }
    _queueController.add(List<AfTrack>.unmodifiable(_trackQueue));
    afLog(
      'audio',
      'insertIntoQueue "${track.title}" at index=$clamped '
          'currentIndex=$_currentIndex',
    );
  }

  Future<void> playNext(
    AfTrack track, {
    required String Function(AfTrack) resolveStreamUrl,
  }) async {
    final insertAt = _currentIndex >= 0 && _currentIndex < _trackQueue.length
        ? _currentIndex + 1
        : _trackQueue.length;
    final url = resolveStreamUrl(track);

    await _player.sendRawCommand([
      'loadfile',
      url,
      'insert-at',
      '$insertAt',
    ]);

    _trackQueue.insert(insertAt, track);
    _queueController.add(List<AfTrack>.unmodifiable(_trackQueue));
    afLog('audio', 'playNext "${track.title}" at index=$insertAt');
  }

  Future<void> addToQueue(
    AfTrack track, {
    required String Function(AfTrack) resolveStreamUrl,
  }) async {
    final url = resolveStreamUrl(track);

    await _player.sendRawCommand([
      'loadfile',
      url,
      'append',
    ]);

    _trackQueue.add(track);
    _queueController.add(List<AfTrack>.unmodifiable(_trackQueue));
    afLog('audio', 'addToQueue "${track.title}" at end');
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _positionPollTimer?.cancel();
    _seekResetTimer?.cancel();
    for (final s in _subs) {
      await s.cancel();
    }
    await _trackController.close();
    await _queueController.close();
    await _positionController.close();
    await _shuffleController.close();
    await _player.dispose();
  }

  void _nudgeAudioDevice() {
    _nudgeGen++;
    unawaited(_nudgeAudioDeviceWithRetry(0, _nudgeGen));
  }

  static const _nudgeDelaysMs = [300, 1000, 2500];

  Future<void> _nudgeAudioDeviceWithRetry(int attempt, int gen) async {
    if (attempt >= _nudgeDelaysMs.length || _disposed) return;

    await Future.delayed(Duration(milliseconds: _nudgeDelaysMs[attempt]));
    if (_disposed || gen != _nudgeGen) return;

    try {
      var current = _player.state.audioDevice;

      if (current.name == 'auto') {
        final devices = _player.state.audioDevices;
        final preferred = devices.where((d) => d.name != 'auto').toList();
        if (preferred.isNotEmpty) {
          current = preferred.firstWhere(
            (d) => d.name == 'aaudio',
            orElse: () => preferred.first,
          );
        }
      }

      await _player.setAudioDevice(current);
      afLog('audio', 'nudged audioDevice: ${current.name} (attempt $attempt)');

      // After the first successful nudge, check if the pipeline recovered.
      // If the player is actively playing, the freeze is resolved — skip
      // remaining attempts to avoid unnecessary audio pipeline rebuilds.
      // Position may still be zero on a fresh track, so we rely on the
      // playing flag (which tracks mpv's core-idle inverted).
      if (attempt == 0 && _player.state.playing) {
        afLog('audio', 'nudge succeeded on first attempt, skipping retries');
        return;
      }
    } catch (e) {
      afLog('audio', 'nudgeAudioDevice attempt $attempt failed', error: e);
    }

    unawaited(_nudgeAudioDeviceWithRetry(attempt + 1, gen));
  }

  /// Re-apply the *current* in-memory audio effects to mpv after an
  /// output-device change.
  ///
  /// On some Android audio outputs (USB DAC, certain Bluetooth
  /// codecs) the `af` filter chain detaches from the output pipeline
  /// when mpv rebuilds it, leaving the user with un-filtered audio
  /// even though `_player.state.audioEffects` still reports the
  /// filters as enabled. Re-issuing `setAudioEffects(current)`
  /// re-attaches the chain.
  ///
  /// This used to load from `SharedPreferences` instead of the live
  /// player state, which raced with `_apply()` in the EQ screen —
  /// `_apply()` issues `setAudioEffects(newFx)` + `saveAudioEffects(newFx)`
  /// as two unawaited futures, so any audioDevice event firing in
  /// between (e.g. from `_nudgeAudioDevice` after `play()`/`seek()`)
  /// would read the *previous* persisted state and clobber the
  /// user's just-applied slider change. Using `_player.state` makes
  /// the operation a pure no-op when nothing has actually changed,
  /// and preserves any pending UI update that's already been pushed
  /// to mpv.
  Future<void> _reapplyPersistedEffects() async {
    if (_disposed) return;
    try {
      final current = _player.state.audioEffects;
      await _player.setAudioEffects(current);
      afLog('audio', 're-applied audio effects after device change');
    } catch (e) {
      afLog('audio', 'reapplyPersistedEffects failed', error: e);
    }
  }

  Future<void> _reconfigureSpectrumOnTrackChange() async {
    if (_disposed) return;
    try {
      await Future.delayed(const Duration(milliseconds: 250));
      if (_disposed) return;
      await _player.setSpectrum(const SpectrumSettings(
        fftSize: 2048,
        bandCount: 64,
        bandLowHz: 20.0,
        bandHighHz: 20000.0,
        attackSmoothing: 0.8,
        releaseSmoothing: 0.1,
        minDb: -105.0,
        maxDb: 35.0,
        emitInterval: Duration(milliseconds: 8),
      ));
      afLog('audio', 'spectrum re-configured after track change');
    } catch (e) {
      afLog('audio', 'reconfigureSpectrumOnTrackChange failed', error: e);
    }
  }

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
    _subs.add(_player.stream.playlist.listen((playlist) {
      final idx = playlist.index;
      if (idx < 0 || idx >= _trackQueue.length) return;
      if (_activePlaylistSyncGen != 0) return;

      final indexChanged = idx != _currentIndex;
      final previousTrackId =
          (_currentIndex >= 0 && _currentIndex < _trackQueue.length)
              ? _trackQueue[_currentIndex].id
              : null;
      _currentIndex = idx;

      if (indexChanged) {
        final track = _trackQueue[idx];
        if (track.id == previousTrackId) return;

        _positionAnchor.lastKnownPos = Duration.zero;
        _positionAnchor.lastUpdateTime = DateTime.now();
        _positionController.add(Duration.zero);
        _resetRawPositionStaleDetector(Duration.zero);

        _trackController.add(track);
        afLog(
          'data',
          'currentTrack source=live id=${track.id} '
              'title="${track.title}" index=$idx',
        );
        onTrackChanged?.call(track);
        _updateMediaItem();

        unawaited(_reconfigureSpectrumOnTrackChange());
        _nudgeRetries = 0;
        _pendingPlayNudgeIdx = idx;

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

    _subs.add(_player.stream.playing.listen((playing) {
      _updatePlaybackState();
      if (playing) {
        _pendingPlayNudgeIdx = null;
        _userPaused = false;
        _nudgeRetries = 0;
      } else if (!_userPaused &&
          _pendingPlayNudgeIdx != null &&
          _pendingPlayNudgeIdx == _currentIndex) {
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

    _subs.add(_player.stream.completed.listen((completed) {
      _updatePlaybackState();
      if (!completed) return;
      final nextIdx = _currentIndex + 1;
      if (nextIdx < _trackQueue.length) {
        final currentMpvIdx = _player.state.playlist.index;
        if (currentMpvIdx == _currentIndex) {
          _jumpAndPlay(nextIdx);
          afLog('audio', 'completed fallback: jump+play to index=$nextIdx');
        }
      } else if (_player.state.loop == Loop.off) {
        pause();
        afLog('audio', 'queue end reached, auto-stop (loop=off)');
      }
    }));

    _subs.add(_player.stream.rate.listen((_) => _updatePlaybackState()));
    _subs.add(_player.stream.duration.listen((dur) {
      if (dur > Duration.zero) {
        _updateMediaItem();
      }
    }));
    _subs.add(_player.stream.coverArt.listen(_persistCover));

    _subs.add(_player.stream.audioDevice.listen((newDevice) {
      // Re-apply effects after a *real* device change — on some
      // devices the audio filter chain (af) doesn't properly attach
      // to the output pipeline on first init. Re-issuing the chain
      // after device change re-wires the filters.
      //
      // Skip when the stream re-emits the same device (mpv re-emits
      // on every property poll on some platforms). Without this
      // guard, every position tick can fire `_reapplyPersistedEffects`,
      // which competes with in-flight UI changes from the EQ screen.
      if (newDevice.name == _lastObservedAudioDevice) return;
      _lastObservedAudioDevice = newDevice.name;
      unawaited(_reapplyPersistedEffects());
    }));

    _positionPollTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (_disposed) return;
      _pollAndEmitPosition();
    });
  }

  void _resetRawPositionStaleDetector([Duration? seed]) {
    _lastRawPolledPos = seed;
    _staleRawPollTicks = 0;
  }

  bool _isRawPositionStale(Duration rawPos) {
    final previous = _lastRawPolledPos;
    _lastRawPolledPos = rawPos;

    if (previous == null) {
      _staleRawPollTicks = 0;
      return false;
    }

    final deltaMs = (rawPos - previous).inMilliseconds.abs();
    if (deltaMs <= _rawStaleTolerance.inMilliseconds) {
      _staleRawPollTicks++;
    } else {
      _staleRawPollTicks = 0;
    }

    return _staleRawPollTicks >= _rawStaleAfterTicks;
  }

  /// Polls mpv for current position. Falls back to elapsed-time extrapolation
  /// when mpv returns 0 OR when mpv returns the same non-zero raw position for
  /// several ticks while playback should be advancing.
  Future<void> _pollAndEmitPosition() async {
    if (_isSeeking || _isPolling) return;
    _isPolling = true;

    try {
      final rawPos = await getRawPosition();
      final now = DateTime.now();
      final playing = _player.state.playing;
      final shouldAdvance = playing || shouldAdvancePosition;

      if (rawPos > Duration.zero) {
        final rawBehindAnchor = shouldAdvance &&
            rawPos.inMilliseconds + 500 <
                _positionAnchor.lastKnownPos.inMilliseconds;
        final rawStale =
            shouldAdvance && (_isRawPositionStale(rawPos) || rawBehindAnchor);

        if (!rawStale) {
          _positionAnchor.lastKnownPos = rawPos;
          _positionAnchor.lastUpdateTime = now;
          _positionAnchor.wasPlaying = playing;
          _positionController.add(rawPos);
          return;
        }

        if (_staleRawPollTicks == _rawStaleAfterTicks || rawBehindAnchor) {
          afLog('audio',
              'raw time-pos stale at ${rawPos.inMilliseconds}ms; using extrapolated position');
        }
      }

      if (shouldAdvance) {
        final elapsed = now.difference(_positionAnchor.lastUpdateTime);
        final speed = _player.state.rate;
        final extrapolated = _positionAnchor.lastKnownPos +
            Duration(milliseconds: (elapsed.inMilliseconds * speed).round());
        _positionAnchor.lastKnownPos = extrapolated;
        _positionAnchor.lastUpdateTime = now;
        _positionAnchor.wasPlaying = true;
        _positionController.add(extrapolated);
      } else if (rawPos == Duration.zero) {
        _resetRawPositionStaleDetector(Duration.zero);
      }
    } finally {
      _isPolling = false;
    }
  }

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
    final effectivePlaying = s.playing || shouldAdvancePosition;

    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          effectivePlaying ? MediaControl.pause : MediaControl.play,
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
        playing: effectivePlaying,
        updatePosition: _positionAnchor.lastKnownPos,
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
    Uri? artUri;

    if (_coverPath != null) {
      artUri = Uri.file(_coverPath!);
    } else if (_networkCoverPath != null && _networkCoverTrackId == track.id) {
      artUri = Uri.file(_networkCoverPath!);
    } else if (track.imageUrl != null && track.imageUrl!.startsWith('file://')) {
      artUri = Uri.parse(track.imageUrl!);
    } else if (track.imageUrl != null) {
      unawaited(_downloadArtworkForNotification(track));
    }

    final mpvDur = _player.state.duration;
    final effectiveDuration = mpvDur > Duration.zero ? mpvDur : track.duration;

    mediaItem.add(
      MediaItem(
        id: track.id,
        title: track.title,
        artist: track.artistName,
        album: track.albumName,
        duration: effectiveDuration == Duration.zero ? null : effectiveDuration,
        artUri: artUri,
        extras: {
          'albumId': track.albumId,
          'artistId': track.artistId,
        },
      ),
    );
  }

  Future<void> _downloadArtworkForNotification(AfTrack track) async {
    if (_disposed) return;
    final imageUrl = track.imageUrl;
    if (imageUrl == null || imageUrl.isEmpty) return;
    if (_networkCoverTrackId == track.id && _networkCoverPath != null) return;

    if (imageUrl.startsWith('file://')) {
      _networkCoverTrackId = track.id;
      _networkCoverPath = imageUrl.substring('file://'.length);
      _updateMediaItem();
      return;
    }

    try {
      final uri = Uri.parse(imageUrl);
      final request = await _httpClient.getUrl(uri);
      _authHeaders.forEach((key, value) {
        request.headers.set(key, value);
      });

      final response = await request.close();
      if (response.statusCode != 200) {
        await response.drain<int>(0);
        return;
      }

      final contentType = response.headers.contentType;
      var ext = 'jpg';
      if (contentType != null && contentType.subType.isNotEmpty) {
        ext = contentType.subType == 'jpeg' ? 'jpg' : contentType.subType;
      }

      final id = ++_coverCounter;
      final tmpDir = Directory.systemTemp.path;
      final path = '$tmpDir${Platform.pathSeparator}aetherfin_notif_$id.$ext';

      if (_networkCoverPath != null) {
        try {
          final prev = File(_networkCoverPath!);
          if (await prev.exists()) await prev.delete();
        } catch (_) {}
      }

      if (_coverPath != null) {
        try {
          final prev = File(_coverPath!);
          if (await prev.exists()) await prev.delete();
        } catch (_) {}
      }

      final file = File(path);
      final sink = file.openWrite();
      try {
        await response.pipe(sink);
      } finally {
        await sink.close();
      }

      if (_disposed) return;
      final currentTrackNow = currentTrack;
      if (currentTrackNow?.id != track.id) return;

      _networkCoverPath = path;
      _networkCoverTrackId = track.id;
      _updateMediaItem();
    } catch (e) {
      afLog('audio', 'artwork download for notification failed', error: e);
    }
  }

  Future<void> _persistCover(CoverArt? raw) async {
    if (_disposed) return;
    if (raw == null) {
      _coverPath = null;
      _updateMediaItem();
      return;
    }

    // Use mpv_audio_kit's mime → extension mapping so we agree with
    // `_downloadArtworkForNotification` (which already maps image/jpeg
    // → .jpg) and so unknown mime types fall back to `.jpg` instead of
    // a literal `.octet-stream` or empty extension. The bytes are
    // played-back/decoded by path on Android's MediaSession so a sane
    // extension matters for MediaStore / Notification panel previewers.
    final ext = raw.extension.isNotEmpty ? raw.extension : 'jpg';
    final id = ++_coverCounter;
    final tmpDir = Directory.systemTemp.path;
    final path = '$tmpDir${Platform.pathSeparator}aetherfin_cover_$id.$ext';

    try {
      if (_coverPath != null) {
        final prev = File(_coverPath!);
        if (await prev.exists()) {
          await prev.delete();
        }
      }

      await File(path).writeAsBytes(raw.bytes);
      _coverPath = path;

      // Don't delete _networkCoverPath here — it may still be in use by
      // an in-flight _downloadArtworkForNotification. The temp file will
      // be cleaned up by the OS eventually, and the next notification
      // cover download will overwrite it anyway.
      _networkCoverPath = null;
      _networkCoverTrackId = null;
      _updateMediaItem();
    } catch (e) {
      afLog('audio', 'cover art persist failed', error: e);
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
    bass: fx.bass.copyWith(
      enabled: fx.bass.enabled && fx.bass.g != 0,
    ),
    treble: fx.treble.copyWith(
      enabled: fx.treble.enabled && fx.treble.g != 0,
    ),
    superequalizer: fx.superequalizer.copyWith(
      enabled:
          fx.superequalizer.enabled && fx.superequalizer.params.isNotEmpty,
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
