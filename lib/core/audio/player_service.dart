import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../../utils/log.dart';
import '../jellyfin/models/items.dart';
import '../jellyfin/models/server.dart';
import 'artwork_manager.dart';
import 'audio_device_manager.dart';
import 'position_tracker.dart';
import 'queue_manager.dart';
import 'track_id_extractor.dart';

import 'spectrum_settings.dart';

/// Bridges [Player] (mpv_audio_kit) with a platform-native media session.
class AfPlayerService {
  final PlayerApi _player;
  late final AfPositionTracker _positionTracker;
  late final AfArtworkManager _artworkManager;
  late final AfAudioDeviceManager _audioDeviceManager;
  late final AfQueueManager _queueManager;

  void Function(AfTrack? track)? onTrackChanged;
  void Function(AfTrack track)? onTrackCompleted;
  final List<StreamSubscription<dynamic>> _subs = <StreamSubscription<dynamic>>[];

  bool _disposed = false;

  MethodChannel _channel = const MethodChannel('aetherfin.media_session');

  int _nudgeRetries = 0;
  static const _maxNudgeRetries = 3;

  int? _pendingPlayNudgeIdx;
  bool _userPaused = false;
  bool _isLoadingQueue = false;
  int _shuffleGen = 0;
  int _queueLoadGen = 0;
  int _playlistHandlerGen = 0;
  final AfAsyncLock _queueLock = AfAsyncLock();

  AfPlayerService() : _player = Player() {
    _positionTracker = AfPositionTracker(
      player: _player,
      shouldAdvancePosition: () => shouldAdvancePosition,
      isLoadingQueue: () => _isLoadingQueue,
    );
    _artworkManager = AfArtworkManager()
      ..onArtworkChanged = _pushStateToNative;
    _audioDeviceManager = AfAudioDeviceManager(player: _player);
    _queueManager = AfQueueManager();

    _channel.setMethodCallHandler(_handleMethodCall);

    // Set audio driver BEFORE binding streams. If setAudioDriver is called
    // after property observation starts, it can re-initialize the output
    // pipeline and break time-pos observation until output is re-selected.
    _player.setAudioDriver('aaudio').catchError((Object e, StackTrace? stack) {
      afLog('error', 'setAudioDriver failed', error: e, stackTrace: stack);
    });

    // 200 ms keeps background playback stable under Android Doze.
    _player.setAudioBuffer(const Duration(milliseconds: 200)).catchError((Object e, StackTrace? stack) {
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
    MethodChannel? channel,
  }) : _player = player {
    _positionTracker = AfPositionTracker(
      player: player,
      shouldAdvancePosition: () => shouldAdvancePosition,
      isLoadingQueue: () => _isLoadingQueue,
    );
    _artworkManager = AfArtworkManager()
      ..onArtworkChanged = _pushStateToNative;
    _audioDeviceManager = AfAudioDeviceManager(player: player);
    _queueManager = AfQueueManager();

    if (channel != null) {
      _channel = channel;
    }
    _channel.setMethodCallHandler(_handleMethodCall);

    // Skip setAudioDriver, setAudioBuffer, Future.delayed in test mode
    _bindStreams();
    _positionTracker.start();
  }

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
  Stream<Loop> get loopModeStream => _player.stream.loop;
  Stream<double> get speedStream => _player.stream.rate;

  Stream<List<Device>> get audioDevicesStream => _player.stream.audioDevices;
  Stream<Device> get audioDeviceStream => _player.stream.audioDevice;
  List<Device> get audioDevices => _player.state.audioDevices;
  Device get audioDevice => _player.state.audioDevice;

  Future<void> setAudioDevice(Device device) async {
    if (_disposed) return;
    if (_isLoadingQueue) return;
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
    if (_isLoadingQueue) return;
    await _player.setAudioExclusive(enabled);
    afLog('audio', 'audioExclusive=$enabled');
    _audioDeviceManager.nudge();
  }

  Future<void> setAudioSampleRate(int rate) async {
    if (_disposed) return;
    if (_isLoadingQueue) return;
    await _player.setAudioSampleRate(rate);
    afLog('audio', 'audioSampleRate=$rate');
  }

  Future<void> setAudioFormat(Format format) async {
    if (_disposed) return;
    if (_isLoadingQueue) return;
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
    if (_isLoadingQueue) return;
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
    if (_isLoadingQueue) return;
    await _player.setAudioBuffer(buffer);
    afLog('audio', 'audioBuffer=${buffer.inMilliseconds}ms');
  }

  Future<void> setAudioStreamSilence(bool enabled) async {
    if (_disposed) return;
    if (_isLoadingQueue) return;
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
    if (_disposed) return;
    if (_isLoadingQueue) return;
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
    if (_disposed) return;
    if (_isLoadingQueue) return;
    await _player.setReplayGain(settings);
    afLog('audio', 'replayGain mode=${settings.mode}');
  }

  Stream<ReplayGainSettings> get replayGainStream => _player.stream.replayGain;
  ReplayGainSettings get replayGain => _player.state.replayGain;

  // ---------------------------------------------------------------------------
  // Gapless & prefetch
  // ---------------------------------------------------------------------------

  Future<void> setGapless(Gapless mode) async {
    if (_disposed) return;
    if (_isLoadingQueue) return;
    await _player.setGapless(mode);
    afLog('audio', 'gapless=${mode.name}');
  }

  Gapless get gaplessMode => _player.state.gapless;
  Stream<Gapless> get gaplessStream => _player.stream.gapless;

  Future<void> setPrefetchPlaylist(bool enabled) async {
    if (_disposed) return;
    if (_isLoadingQueue) return;
    await _player.setPrefetchPlaylist(enabled);
    afLog('audio', 'prefetchPlaylist=$enabled');
  }

  bool get prefetchPlaylist => _player.state.prefetchPlaylist;

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
    if (_isLoadingQueue) return Future.value(Duration.zero);
    return _positionTracker.getRawPosition();
  }

  Future<Duration> getRawDuration() {
    if (_isLoadingQueue) return Future.value(Duration.zero);
    return _positionTracker.getRawDuration();
  }

  List<AfTrack> get currentQueue => _queueManager.currentQueue;

  AfTrack? get currentTrack => _queueManager.currentTrack;

  bool get isPlaying => _player.state.playing;
  bool get isCompleted => _player.state.completed;
  bool get isUserPaused => _userPaused;
  bool get isLoadingQueue => _isLoadingQueue;

  @visibleForTesting
  set isLoadingQueueForTesting(bool value) => _isLoadingQueue = value;

  @visibleForTesting
  set disposedForTesting(bool value) => _disposed = value;

  @visibleForTesting
  bool get isDisposedForTesting => _disposed;

  /// True when UI/notification progress should keep advancing even if mpv's
  /// reported `playing` flag is temporarily stale/false on an OEM pipeline.
  bool get shouldAdvancePosition {
    final hasTrack = currentTrack != null;
    final completedAtQueueEnd =
        _player.state.completed && _queueManager.isAtQueueEnd;
    return hasTrack && !completedAtQueueEnd && !_userPaused && !_isLoadingQueue;
  }

  bool get isShuffleEnabled => _queueManager.isShuffleEnabled;
  Loop get loopMode => _player.state.loop;
  double get speed => _player.state.rate;

  // ---------------------------------------------------------------------------
  // Playback control
  // ---------------------------------------------------------------------------

  void setAuthHeaders(Map<String, String> headers) {
    _artworkManager.setAuthHeaders(headers);
  }

  /// Set the queue manager's [TrackIdExtractor] based on the active
  /// [ServerType]. Called from [wirePlayerService] once the backend
  /// is known, and can be called again if the backend changes.
  void setTrackIdExtractorForServerType(ServerType type) {
    _queueManager.extractor = switch (type) {
      ServerType.jellyfin => const JellyfinTrackIdExtractor(),
      ServerType.subsonic => const SubsonicTrackIdExtractor(),
      ServerType.local => const LocalTrackIdExtractor(),
    };
  }

  Future<void> playQueue(
    List<AfTrack> tracks, {
    int startIndex = 0,
    required String Function(AfTrack track) resolveStreamUrl,
    Map<String, String> streamHeaders = const <String, String>{},
  }) async {
    if (tracks.isEmpty) return;

    _userPaused = false;
    final myGen = ++_queueLoadGen;
    ++_shuffleGen;

    return _queueLock.run(() async {
      if (myGen != _queueLoadGen) return;

      final safeIndex = startIndex.clamp(0, tracks.length - 1);
      if (streamHeaders.isNotEmpty) {
        _artworkManager.setAuthHeaders(streamHeaders);
      }

      _queueManager.replaceQueue(tracks, safeIndex);
      if (_queueManager.isShuffleEnabled) {
        _queueManager.setOriginalQueue(List<AfTrack>.of(tracks));
      }

      final startTrack = tracks[safeIndex];
      _queueManager.emitCurrentTrack(startTrack);
      onTrackChanged?.call(startTrack);
      afLog(
        'data',
        'playQueue source=live size=${tracks.length} '
            'startIndex=$safeIndex first="${startTrack.title}"',
      );

      final medias = tracks.map((t) {
        final url = resolveStreamUrl(t);
        return Media(url);
      }).toList();
      _queueManager.rebuildUrlMap(medias, tracks);

      _isLoadingQueue = true;
      var localSyncs = 0;
      try {
        _positionTracker.onTrackChanged();
        _queueManager.beginPlaylistSync();
        localSyncs++;

        final shouldPlay = !_userPaused;
        if (medias.length <= 5) {
          await _player.openAll(medias, index: safeIndex, play: shouldPlay);
          if (myGen != _queueLoadGen) return;
        } else {
          await _player.open(medias[safeIndex], play: shouldPlay);
          if (myGen != _queueLoadGen) return;

          for (var i = safeIndex + 1; i < medias.length; i++) {
            await _player.add(medias[i]);
            if (myGen != _queueLoadGen) return;
          }

          for (var i = safeIndex - 1; i >= 0; i--) {
            await _player.sendRawCommand([
              'loadfile',
              medias[i].uri,
              'insert-at',
              '0',
            ]);
            if (myGen != _queueLoadGen) return;
          }
        }

        if (_queueManager.isShuffleEnabled) {
          final playlistFuture = _player.stream.playlist.first;
          await _player.setShuffle(true);
          if (myGen != _queueLoadGen) return;
          try {
            final newPlaylist = await playlistFuture.timeout(const Duration(seconds: 2));
            if (myGen != _queueLoadGen) return;
            _queueManager.syncFromMpv(newPlaylist.items, newPlaylist.index);
          } catch (e, stack) {
            afLog(
              'audio',
              'playQueue shuffle sync timeout, using state fallback',
              error: e,
              stackTrace: stack,
            );
            if (myGen != _queueLoadGen) return;
            final mpvItems = _player.state.playlist.items;
            final newIdx = _player.state.playlist.index;
            _queueManager.syncFromMpv(mpvItems, newIdx);
          }
          _queueManager.emitQueue();

          final track = currentTrack;
          if (track != null) {
            _queueManager.emitCurrentTrack(track);
            onTrackChanged?.call(track);
          }
        } else {
          await _player.setShuffle(false);
          if (myGen != _queueLoadGen) return;
        }

        _audioDeviceManager.nudge();
      } catch (e, stack) {
        if (myGen != _queueLoadGen) return;
        afLog('audio', 'playQueue failed', error: e, stackTrace: stack);
        _userPaused = true;
        _queueManager.clear();
        try {
          await _player.stop();
        } catch (err, st) {
          afLog('audio', 'stop failed on playQueue cleanup', error: err, stackTrace: st);
        }
        rethrow;
      } finally {
        while (localSyncs > 0) {
          _queueManager.endPlaylistSync();
          localSyncs--;
        }
        if (myGen == _queueLoadGen) {
          _isLoadingQueue = false;
        }
      }
    });
  }

  Future<void> play() async {
    if (_disposed) return;
    return _queueLock.run(() async {
      _userPaused = false;
      _positionTracker.onPlay();
      try {
        await _player.play();
        _audioDeviceManager.nudge();
      } catch (e, stack) {
        afLog('audio', 'play failed', error: e, stackTrace: stack);
      }
    });
  }

  Future<void> pause() async {
    if (_disposed) return;
    return _queueLock.run(() async {
      _userPaused = true;
      _pendingPlayNudgeIdx = null;
      _positionTracker.onPause();
      try {
        await _player.pause();
      } catch (e, stack) {
        afLog('audio', 'pause failed', error: e, stackTrace: stack);
      }
    });
  }

  Future<void> stop() async {
    if (_disposed) return;
    _userPaused = true;
    _pendingPlayNudgeIdx = null;
    _positionTracker.onStop();
    try {
      await _player.stop();
    } catch (e, stack) {
      afLog('audio', 'stop failed', error: e, stackTrace: stack);
    }
  }

  Future<void> seek(Duration position) async {
    if (_disposed) return;
    if (_isLoadingQueue) return;
    _positionTracker.onSeek(position);

    return _queueLock.run(() async {
      try {
        await _player.seek(position);
        _updateMediaSession();
        _audioDeviceManager.nudge();
      } catch (e, stack) {
        afLog('audio', 'seek failed', error: e, stackTrace: stack);
      }
    });
  }

  Future<void> skipToNext() async {
    if (_isLoadingQueue) return;
    return _queueLock.run(() async {
      try {
        await _player.next();
      } catch (e, stack) {
        afLog('audio', 'skipToNext failed', error: e, stackTrace: stack);
      }
    });
  }

  Future<void> skipToPrevious() async {
    if (_isLoadingQueue) return;
    return _queueLock.run(() async {
      try {
        await _player.previous();
      } catch (e, stack) {
        afLog('audio', 'skipToPrevious failed', error: e, stackTrace: stack);
      }
    });
  }

  Future<void> skipToQueueItem(int index) async {
    if (_isLoadingQueue) return;
    return _queueLock.run(() async {
      try {
        await _player.jump(index);
      } catch (e, stack) {
        afLog('audio', 'skipToQueueItem failed', error: e, stackTrace: stack);
      }
    });
  }

  Future<void> setAfShuffleMode(bool enabled) async {
    if (_disposed) return;
    if (_isLoadingQueue) return;
    return _queueLock.run(() async {
      if (_queueManager.isShuffleEnabled == enabled) return;

      if (_queueManager.currentQueue.isEmpty) {
        afLog('data', 'shuffleMode source=live enabled=$enabled (queue empty)');
        return;
      }

      final myGen = ++_shuffleGen;
      var syncActive = false;

      try {
        _queueManager.beginPlaylistSync();
        syncActive = true;
        _queueManager.setShuffleEnabled(enabled);

        final playlistFuture = _player.stream.playlist.first;
        await _player.setShuffle(enabled);

        if (myGen != _shuffleGen) {
          return;
        }

        try {
          final newPlaylist = await playlistFuture.timeout(const Duration(seconds: 2));
          if (myGen != _shuffleGen) {
            return;
          }
          _queueManager.syncFromMpv(newPlaylist.items, newPlaylist.index);
        } catch (e, stack) {
          afLog(
            'audio',
            'shuffle playlist stream timeout, using state fallback',
            error: e,
            stackTrace: stack,
          );
          if (myGen != _shuffleGen) {
            return;
          }
          final mpvItems = _player.state.playlist.items;
          final newIdx = _player.state.playlist.index;
          _queueManager.syncFromMpv(mpvItems, newIdx);
        }

        if (!enabled) {
          _queueManager.clearOriginalQueueAfterSync();
        }

        _queueManager.emitQueue();

        final track = currentTrack;
        if (track != null) {
          _queueManager.emitCurrentTrack(track);
          onTrackChanged?.call(track);
        }

        afLog(
          'data',
          'shuffleMode source=live enabled=$enabled '
              'queueSize=${_queueManager.currentQueue.length} currentIndex=${_queueManager.currentIndex}',
        );
      } catch (e, stack) {
        afLog('audio', 'setAfShuffleMode failed', error: e, stackTrace: stack);
      } finally {
        if (syncActive) {
          _queueManager.endPlaylistSync();
        }
      }
    });
  }

  Future<void> setAfLoopMode(Loop mode) async {
    if (_disposed) return;
    if (_isLoadingQueue) return;
    return _queueLock.run(() async {
      try {
        await _player.setLoop(mode);
        afLog('data', 'loopMode source=live mode=${mode.name}');
      } catch (e, stack) {
        afLog('audio', 'setAfLoopMode failed', error: e, stackTrace: stack);
      }
    });
  }

  Future<void> setAfSpeed(double speed) async {
    if (_disposed) return;
    if (_isLoadingQueue) return;
    await _player.setRate(speed);
    afLog('data', 'playbackSpeed source=live speed=$speed');
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    return _queueLock.run(() async {
      if (_isLoadingQueue) {
        afLog('audio', 'reorderQueue ignored: queue is loading');
        return;
      }
      if (!_queueManager.canReorder(oldIndex, newIndex)) return;

      _queueManager.beginPlaylistSync();
      try {
        final insertIdx = _queueManager.reorder(oldIndex, newIndex);
        await _player.sendRawCommand(['playlist-move', '$oldIndex', '$insertIdx']);

        afLog(
          'audio',
          'reorderQueue oldIndex=$oldIndex newIndex=$newIndex '
              'currentIndex=${_queueManager.currentIndex} queueSize=${_queueManager.currentQueue.length}',
        );
      } catch (e, stack) {
        afLog('audio', 'reorderQueue failed', error: e, stackTrace: stack);
      } finally {
        _queueManager.endPlaylistSync();
      }
    });
  }

  /// Remove a track from the queue at [index]. Refuses to remove the
  /// currently-playing item. Returns `true` when the removal took effect.
  Future<bool> removeFromQueue(int index) async {
    return _queueLock.run(() async {
      if (_disposed) return false;
      if (_isLoadingQueue) {
        afLog('audio', 'removeFromQueue ignored: queue is loading');
        return false;
      }
      if (!_queueManager.canRemove(index)) {
        afLog('audio', 'removeFromQueue refused index=$index (currently playing)');
        return false;
      }

      _queueManager.beginPlaylistSync();
      try {
        await _player.sendRawCommand(['playlist-remove', '$index']);
        _queueManager.remove(index);
        afLog(
          'audio',
          'removeFromQueue index=$index currentIndex=${_queueManager.currentIndex} '
              'queueSize=${_queueManager.currentQueue.length}',
        );
        return true;
      } catch (e, stack) {
        afLog('audio', 'removeFromQueue failed', error: e, stackTrace: stack);
        return false;
      } finally {
        _queueManager.endPlaylistSync();
      }
    });
  }

  Future<void> insertIntoQueue(
    int index,
    AfTrack track, {
    required String Function(AfTrack) resolveStreamUrl,
  }) async {
    return _queueLock.run(() async {
      if (_disposed) return;
      if (_isLoadingQueue) {
        afLog('audio', 'insertIntoQueue ignored: queue is loading');
        return;
      }
      final url = resolveStreamUrl(track);

      _queueManager.beginPlaylistSync();
      try {
        await _player.sendRawCommand([
          'loadfile',
          url,
          'insert-at',
          '$index',
        ]);

        _queueManager.insert(index, track, url);
        afLog(
          'audio',
          'insertIntoQueue "${track.title}" at index=$index '
              'currentIndex=${_queueManager.currentIndex}',
        );
      } catch (e, stack) {
        afLog('audio', 'insertIntoQueue failed', error: e, stackTrace: stack);
      } finally {
        _queueManager.endPlaylistSync();
      }
    });
  }

  Future<void> playNext(
    AfTrack track, {
    required String Function(AfTrack) resolveStreamUrl,
  }) async {
    return _queueLock.run(() async {
      if (_isLoadingQueue) {
        afLog('audio', 'playNext ignored: queue is loading');
        return;
      }
      final insertAt = _queueManager.currentIndex >= 0
          ? _queueManager.currentIndex + 1
          : _queueManager.currentQueue.length;
      final url = resolveStreamUrl(track);

      _queueManager.beginPlaylistSync();
      try {
        await _player.sendRawCommand([
          'loadfile',
          url,
          'insert-at',
          '$insertAt',
        ]);

        _queueManager.insert(insertAt, track, url);
        afLog('audio', 'playNext "${track.title}" at index=$insertAt');
      } catch (e, stack) {
        afLog('audio', 'playNext failed', error: e, stackTrace: stack);
      } finally {
        _queueManager.endPlaylistSync();
      }
    });
  }

  Future<void> addToQueue(
    AfTrack track, {
    required String Function(AfTrack) resolveStreamUrl,
  }) async {
    return _queueLock.run(() async {
      if (_isLoadingQueue) {
        afLog('audio', 'addToQueue ignored: queue is loading');
        return;
      }
      final url = resolveStreamUrl(track);

      _queueManager.beginPlaylistSync();
      try {
        await _player.sendRawCommand([
          'loadfile',
          url,
          'append',
        ]);

        _queueManager.append(track, url);
        afLog('audio', 'addToQueue "${track.title}" at end');
      } catch (e, stack) {
        afLog('audio', 'addToQueue failed', error: e, stackTrace: stack);
      } finally {
        _queueManager.endPlaylistSync();
      }
    });
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _channel.setMethodCallHandler(null);
    _positionTracker.dispose();
    _queueManager.dispose();
    for (final s in _subs) {
      await s.cancel();
    }
    await _player.dispose();
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'play':
        unawaited(play());
      case 'pause':
        unawaited(pause());
      case 'next':
        unawaited(skipToNext());
      case 'previous':
        unawaited(skipToPrevious());
      case 'stop':
        unawaited(stop());
      case 'seek':
        final positionMs = call.arguments['positionMs'] as int?;
        if (positionMs != null) {
          unawaited(seek(Duration(milliseconds: positionMs)));
        }
      case 'skipTo':
        final queueIndex = call.arguments['queueIndex'] as int?;
        if (queueIndex != null) {
          unawaited(skipToQueueItem(queueIndex));
        }
      default:
        throw PlatformException(
          code: 'Unimplemented',
          details: 'Method ${call.method} is not implemented',
        );
    }
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

  Future<void> _jumpAndPlay(int index) async {
    if (_disposed) return;
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
    _subs.add(_player.stream.playlist.listen((playlist) async {
      final myGen = ++_playlistHandlerGen;
      try {
        final idx = playlist.index;
        if (idx < 0 || idx >= _queueManager.currentQueue.length) return;
        if (!_queueManager.canHandlePlaylistEvent) return;

        final trackChanged = _queueManager.processPlaylistEvent(idx);
        if (!trackChanged) return;
        final track = _queueManager.currentTrack;
        if (track == null) return;

        _positionTracker.onTrackChanged();
        _queueManager.emitCurrentTrack(track);
        afLog(
          'data',
          'currentTrack source=live id=${track.id} '
              'title="${track.title}" index=$idx',
        );
        onTrackChanged?.call(track);
        _updateMediaSession();

        try {
          await _reconfigureSpectrumOnTrackChange();
        } catch (e, stack) {
          afLog('audio', 'spectrum configuration failed', error: e, stackTrace: stack);
        }

        if (myGen != _playlistHandlerGen) return;
        _nudgeRetries = 0;
        _pendingPlayNudgeIdx = idx;

        if (!_player.state.playing && !_userPaused) {
          if (_nudgeRetries < _maxNudgeRetries) {
            _nudgeRetries++;
            try {
              await _player.play();
              afLog('audio',
                  'auto-advance nudge (playlist event) play() at index=$idx (attempt $_nudgeRetries)');
            } catch (e, stack) {
              afLog('audio', 'auto-advance nudge play failed', error: e, stackTrace: stack);
            }
          } else {
            _pendingPlayNudgeIdx = null;
            afLog('audio',
                'auto-advance nudge exhausted after $_maxNudgeRetries attempts at index=$idx');
          }
        } else {
          _pendingPlayNudgeIdx = null;
        }
      } catch (e, stack) {
        afLog('audio', 'playlist handler failed', error: e, stackTrace: stack);
      }
    }));

    _subs.add(_player.stream.playing.listen((playing) async {
      try {
        _updateMediaSession();
        if (playing) {
          _pendingPlayNudgeIdx = null;
          _userPaused = false;
          _nudgeRetries = 0;
        } else if (!_userPaused &&
            _pendingPlayNudgeIdx != null &&
            _pendingPlayNudgeIdx == _queueManager.currentIndex) {
          if (_nudgeRetries < _maxNudgeRetries) {
            _nudgeRetries++;
            try {
              await _player.play();
              afLog('audio',
                  'auto-advance nudge play() at index=${_queueManager.currentIndex} (attempt $_nudgeRetries)');
            } catch (e, stack) {
              afLog('audio', 'auto-advance nudge play failed', error: e, stackTrace: stack);
            }
          } else {
            _pendingPlayNudgeIdx = null;
            afLog('audio',
                'auto-advance nudge exhausted after $_maxNudgeRetries attempts at index=${_queueManager.currentIndex}');
          }
        }
      } catch (e, stack) {
        afLog('audio', 'playing handler failed', error: e, stackTrace: stack);
      }
    }));

    _subs.add(_player.stream.position.listen((_) => _updateMediaSession()));
    _subs.add(_player.stream.buffering.listen((_) => _updateMediaSession()));

    _subs.add(_player.stream.completed.listen((completed) async {
      try {
        if (_disposed) return;
        if (_isLoadingQueue) return;
        _updateMediaSession();
        if (!completed) return;

        // Snapshot state at event time to prevent race with setAfLoopMode
        // changing _player.state.loop while the lock action is queued.
        final loopAtEvent = _player.state.loop;
        final playlistIndexAtEvent = _player.state.playlist.index;
        final playingAtEvent = _player.state.playing;

        await _queueLock.run(() async {
          final finishedTrack = _queueManager.currentTrack;
          final nextIdx = _queueManager.currentIndex + 1;
          final isAtEnd = nextIdx >= _queueManager.currentQueue.length;
          if (!isAtEnd && loopAtEvent == Loop.file) {
            if (!playingAtEvent) {
              await _player.play();
            }
            afLog('audio', 'completed: replay file (loop=file) — mpv handles internally');
          } else if (!isAtEnd) {
            if (playlistIndexAtEvent == _queueManager.currentIndex) {
              await _jumpAndPlay(nextIdx);
              afLog('audio', 'completed: jump+play to index=$nextIdx');
            }
          } else {
            switch (loopAtEvent) {
              case Loop.off:
                _userPaused = true;
                _pendingPlayNudgeIdx = null;
                _positionTracker.onStop();
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
                await _jumpAndPlay(0);
                afLog('audio', 'queue end, looping playlist');
              case Loop.file:
                if (!playingAtEvent) {
                  await _player.play();
                }
                afLog('audio', 'queue end, looping file — mpv handles internally');
            }
          }

          if (finishedTrack != null) {
            unawaited(Future.microtask(() => onTrackCompleted?.call(finishedTrack)));
          }
        });
      } catch (e, stack) {
        afLog('audio', 'completed handler failed', error: e, stackTrace: stack);
      }
    }));

    _subs.add(_player.stream.rate.listen((_) => _updateMediaSession()));
    _subs.add(_player.stream.duration.listen((dur) {
      if (dur > Duration.zero) {
        _updateMediaSession();
      }
    }));
    _subs.add(_player.stream.coverArt.listen((raw) async {
      try {
        try {
          await _artworkManager.persistCover(raw);
        } catch (e, stack) {
          afLog('audio', 'persistCover failed', error: e, stackTrace: stack);
        }
        _updateMediaSession();
      } catch (e, stack) {
        afLog('audio', 'coverArt handler failed', error: e, stackTrace: stack);
      }
    }));

    _subs.add(_player.stream.audioDevice.listen((newDevice) async {
      if (_isLoadingQueue) return;
      try {
        if (!_audioDeviceManager.isRealDeviceChange(newDevice.name)) return;
        try {
          await _audioDeviceManager.reapplyPersistedEffects();
        } catch (e, stack) {
          afLog('audio', 'reapplyPersistedEffects failed', error: e, stackTrace: stack);
        }
      } catch (e, stack) {
        afLog('audio', 'audioDevice handler failed', error: e, stackTrace: stack);
      }
    }));

  }

  /// Push the current state through the platform channel.
  /// Sends `updateState` when there is an active track,
  /// or `clear` when the queue is empty.
  void _updateMediaSession() {
    if (_disposed) return;
    final track = _queueManager.currentTrack;
    if (track == null) {
      _channel.invokeMethod('clear').catchError((Object e) {
        afLog('error', 'Failed to clear native media state', error: e);
      });
      return;
    }

    final s = _player.state;
    final isQueueEnd = s.completed && _queueManager.isAtQueueEnd;
    final effectivePlaying =
        isQueueEnd ? false : (s.playing || shouldAdvancePosition);

    final mpvDur = _isLoadingQueue ? Duration.zero : s.duration;
    final effectiveDuration = mpvDur > Duration.zero ? mpvDur : track.duration;

    final artUri = _artworkManager.artUri(track);
    final artPath =
        artUri != null && artUri.isScheme('file') ? artUri.toFilePath() : null;

    final args = <String, dynamic>{
      'playing': effectivePlaying,
      'buffering': s.buffering,
      'positionMs': _positionTracker.lastKnownPosition.inMilliseconds,
      'durationMs': effectiveDuration.inMilliseconds,
      'speed': s.rate,
      'title': track.title,
      'artist': track.artistName,
      'album': track.albumName,
      'artPath': artPath,
      'queueIndex':
          _queueManager.currentIndex >= 0 ? _queueManager.currentIndex : null,
      'queueSize': _queueManager.currentQueue.length,
      'needsArtworkDownload':
          artUri == null && _artworkManager.needsRemoteArtwork(track),
    };

    _channel.invokeMethod('updateState', args).catchError((Object e) {
      afLog('error', 'Failed to update native media state', error: e);
    });
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
      enabled: fx.bass.enabled && fx.bass.g.abs() > 0.001,
    ),
    treble: fx.treble.copyWith(
      enabled: fx.treble.enabled && fx.treble.g.abs() > 0.001,
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

class AfAsyncLock {
  Future<void> _chain = Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _chain = _chain.then(
      (_) async {
        try {
          final result = await action();
          completer.complete(result);
        } catch (e, st) {
          completer.completeError(e, st);
        }
      },
    ).catchError((Object _) {});
    return completer.future;
  }
}
