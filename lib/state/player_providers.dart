import 'dart:async' show unawaited;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart'
    show Loop, FftFrame, MpvPlayerError;

import '../core/audio/af_loop_mode.dart';
import '../core/audio/jellyfin_playback_reporter.dart';
import '../core/audio/player_service.dart';
import '../core/audio/shuffle_mode.dart';
import '../core/jellyfin/models/items.dart';
import 'app_mode_providers.dart';
import 'auth_providers.dart';
import 'music_backend_providers.dart';
import 'settings_providers.dart';
import 'favorite_providers.dart';
import '../utils/log.dart';

void wirePlayerService(Ref ref, AfPlayerService svc) {
  svc.onTrackChanged = (track) {
    ref.read(currentTrackProvider.notifier).state = track;
    ref.read(currentArtworkUriProvider.notifier).state = track != null
        ? svc.currentArtworkUri
        : null;
    ref.read(positionStreamProvider.notifier).state = Duration.zero;
    ref
        .read(durationStreamProvider.notifier)
        .state = (track != null && track.duration > Duration.zero)
        ? track.duration
        : Duration.zero;
    ref.read(abLoopAProvider.notifier).state = null;
    ref.read(abLoopBProvider.notifier).state = null;
  };

  svc.onArtworkUpdated = (artUri) {
    ref.read(currentArtworkUriProvider.notifier).state = artUri;
  };

  svc.onToggleFavorite = () async {
    final track = ref.read(currentTrackProvider);
    if (track != null) {
      try {
        await ref.read(favoriteToggleProvider)(track);
      } catch (_) {}
    }
  };

  svc.onTrackCompleted = (track) {
    final enabled = ref.read(offlineCacheEnabledProvider);
    if (!enabled) return;
    final mode = ref.read(appModeProvider);
    if (mode == AppMode.local) return;
    final backend = ref.read(musicBackendProvider);
    if (backend == null) return;
    final cache = ref.read(offlineCacheServiceProvider);
    final maxBitrate = ref.read(maxBitrateProvider);
    final url = backend.trackStreamUrl(
      track.id,
      maxBitrateKbps: maxBitrate == 0 ? null : maxBitrate,
    );
    unawaited(cache.cacheTrack(track.id, url, headers: backend.authHeaders));
  };

  svc.onGetSimilarTracks = (lastTrack) async {
    final autoplay = ref.read(autoplayEnabledProvider);
    if (!autoplay) return const <AfTrack>[];
    final backend = ref.read(musicBackendProvider);
    if (backend == null) return const <AfTrack>[];
    try {
      final mix = await backend.instantMix(lastTrack.id, limit: 20);
      final existingIds = svc.currentQueue.map((t) => t.id).toSet();
      return mix.where((t) => !existingIds.contains(t.id)).toList();
    } catch (e, stack) {
      afLog(
        'audio',
        'failed to fetch autoplay tracks',
        error: e,
        stackTrace: stack,
      );
      return const <AfTrack>[];
    }
  };

  _startPositionPolling(ref, svc);

  final errorSub = svc.errorStream.listen((error) {
    ref.read(playbackErrorProvider.notifier).state = error;
  });

  final mode = ref.read(appModeProvider);
  JellyfinPlaybackReporter? reporter;
  if (mode != AppMode.local) {
    reporter = JellyfinPlaybackReporter(
      svc,
      () => ref.read(musicBackendProvider),
    );
  }

  unawaited(svc.configureSpectrum());

  ref.listen(authProvider, (prev, next) {
    if (prev != null && next == null) {
      reporter?.requestStopOnDispose();
      unawaited(reporter?.dispose());
    }
  });

  ref.onDispose(() async {
    await errorSub.cancel();
    await reporter?.dispose();
    await svc.dispose();
  });
}

final playerServiceProvider = Provider<AfPlayerService>((ref) {
  final svc = AfPlayerService();
  wirePlayerService(ref, svc);
  return svc;
});

final playerQueueProvider = StreamProvider.autoDispose<List<AfTrack>>((ref) {
  final svc = ref.watch(playerServiceProvider);
  return Stream<List<AfTrack>>.multi((controller) {
    controller.add(svc.currentQueue);
    final sub = svc.queueStream.listen(controller.add);
    controller.onCancel = sub.cancel;
  });
});

final positionStreamProvider = StateProvider<Duration>((ref) => Duration.zero);
final durationStreamProvider = StateProvider<Duration>((ref) => Duration.zero);
final playbackErrorProvider = StateProvider<MpvPlayerError?>((ref) => null);
final abLoopAProvider = StateProvider<Duration?>((ref) => null);
final abLoopBProvider = StateProvider<Duration?>((ref) => null);

/// Bridges [AfPlayerService] position/duration streams into Riverpod
/// providers and handles EOF state reset.
void _startPositionPolling(Ref ref, AfPlayerService svc) {
  var disposed = false;

  ref.onDispose(() {
    disposed = true;
  });

  final posSub = svc.positionStream.listen((pos) {
    ref.read(positionStreamProvider.notifier).state = pos;
  });

  final durSub = svc.durationStream.listen((dur) {
    if (dur > Duration.zero) {
      final current = ref.read(durationStreamProvider);
      if (dur != current) {
        ref.read(durationStreamProvider.notifier).state = dur;
      }
    }
  });

  // Duration poll loop — recursive Future.delayed instead of
  // Timer.periodic so the async callback never overlaps with itself.
  // Timer.periodic does NOT await the callback; if getRawDuration()
  // takes longer than 250 ms the ticks pile up, causing redundant
  // state writes and wasted work.
  int loopGeneration = 0;
  bool loopRunning = false;

  Future<void> runDurationPollLoop() async {
    final gen = loopGeneration;
    while (loopRunning && gen == loopGeneration) {
      await Future.delayed(const Duration(milliseconds: 1000));
      if (!loopRunning || gen != loopGeneration || disposed) break;

      final rawDur = await svc.getRawDuration();
      if (!loopRunning || gen != loopGeneration || disposed) return;

      if (rawDur > Duration.zero) {
        if (disposed) return;
        final current = ref.read(durationStreamProvider);
        if (rawDur != current) {
          ref.read(durationStreamProvider.notifier).state = rawDur;
        }
      } else {
        final track = ref.read(currentTrackProvider);
        if (track != null && track.duration > Duration.zero) {
          if (disposed) return;
          ref.read(durationStreamProvider.notifier).state = track.duration;
        }
      }
    }
  }

  void cancelTimer() {
    loopRunning = false;
  }

  void ensureTimer() {
    if (disposed || loopRunning) return;
    loopGeneration++;
    loopRunning = true;
    runDurationPollLoop();
  }

  ensureTimer();

  ref.listen(currentTrackProvider, (prev, next) {
    if (prev != null && next == null) {
      cancelTimer();
    } else if (prev == null && next != null) {
      ensureTimer();
    }
    if (next != null && prev?.isFavorite != next.isFavorite) {
      svc.updateTrackFavorite(next.id, next.isFavorite);
    }
  });

  ref.onDispose(() {
    cancelTimer();
    unawaited(posSub.cancel());
    unawaited(durSub.cancel());
  });
}

final playingStreamProvider = StreamProvider.autoDispose<bool>((ref) {
  final svc = ref.watch(playerServiceProvider);
  return svc.playingStream;
});

final shuffleModeProvider = StreamProvider.autoDispose<ShuffleMode>((ref) {
  final svc = ref.watch(playerServiceProvider);
  return Stream<ShuffleMode>.multi((controller) {
    controller.add(
      svc.isShuffleEnabled
          ? (svc.isTailShuffle ? ShuffleMode.tail : ShuffleMode.all)
          : ShuffleMode.off,
    );
    final sub = svc.shuffleModeStream.listen((enabled) {
      controller.add(
        enabled
            ? (svc.isTailShuffle ? ShuffleMode.tail : ShuffleMode.all)
            : ShuffleMode.off,
      );
    });
    controller.onCancel = sub.cancel;
  });
});

AfLoopMode _loopToAfLoopMode(Loop loop) {
  switch (loop) {
    case Loop.off:
      return AfLoopMode.off;
    case Loop.file:
      return AfLoopMode.file;
    case Loop.playlist:
      return AfLoopMode.playlist;
  }
}

final loopModeProvider = StreamProvider.autoDispose<AfLoopMode>((ref) {
  final svc = ref.watch(playerServiceProvider);
  final forNtimesActive = ref.watch(forNtimesModeProvider);
  if (forNtimesActive) {
    return Stream.value(AfLoopMode.forNtimes);
  }
  return Stream<AfLoopMode>.multi((controller) {
    controller.add(_loopToAfLoopMode(svc.loopMode));
    final sub = svc.loopModeStream.listen((loop) {
      controller.add(_loopToAfLoopMode(loop));
    });
    controller.onCancel = sub.cancel;
  });
});

final playbackSpeedProvider = StreamProvider.autoDispose<double>((ref) {
  final svc = ref.watch(playerServiceProvider);
  return Stream<double>.multi((controller) {
    controller.add(svc.speed);
    final sub = svc.speedStream.listen(controller.add);
    controller.onCancel = sub.cancel;
  });
});

final fftSpectrumProvider = StreamProvider.autoDispose<FftFrame>((ref) {
  final svc = ref.watch(playerServiceProvider);
  return svc.spectrumStream;
});

final currentTrackProvider = StateProvider<AfTrack?>((ref) => null);
final currentArtworkUriProvider = StateProvider<Uri?>((ref) => null);

final ntimesCountProvider = StateProvider<int>((ref) => 2);

/// The current N value for forNtimes repeat mode. Defaults to 2.
final repeatCountProvider = StateProvider<int>((ref) => 2);

/// Whether forNtimes loop mode is currently active.
final forNtimesModeProvider = StateProvider<bool>((ref) => false);

final hasActivePlaybackProvider = Provider<bool>((ref) {
  return ref.watch(currentTrackProvider) != null;
});
