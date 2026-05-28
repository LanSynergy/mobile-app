import 'dart:async' show unawaited, Timer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart'
    show Loop, FftFrame, MpvPlayerError;

import '../core/audio/af_loop_mode.dart';
import '../core/audio/jellyfin_playback_reporter.dart';
import '../core/audio/player_service.dart';
import '../core/audio/shuffle_mode.dart';
import '../core/backend/music_backend.dart';
import '../core/jellyfin/models/items.dart';
import 'app_mode_providers.dart';
import 'local_library_providers.dart';
import 'music_backend_providers.dart';
import 'settings_providers.dart';
import 'favorite_providers.dart';
import '../utils/log.dart';

void wirePlayerService(Ref ref, AfPlayerService svc) {
  // Asynchronously load the saved play queue from the backend if it exists
  Future<void> loadSavedQueue() async {
    final backend = ref.read(musicBackendProvider);
    if (backend == null) return;
    try {
      final saved = await backend.getPlayQueue();
      if (saved != null && saved.tracks.isNotEmpty) {
        afLog(
          'audio',
          'Loaded saved queue from backend: count=${saved.tracks.length} current=${saved.currentIndex}',
        );
        await svc.playQueue(
          saved.tracks,
          startIndex: saved.currentIndex,
          resolveStreamUrl: (track) => backend.trackStreamUrl(track.id),
        );
        if (saved.position > Duration.zero) {
          await svc.seek(saved.position);
        }
        await svc.pause();
      }
    } catch (e, stack) {
      afLog(
        'audio',
        'Failed to load saved queue on boot',
        error: e,
        stackTrace: stack,
      );
    }
  }

  // Load initially if backend is already available
  if (ref.read(musicBackendProvider) != null) {
    unawaited(loadSavedQueue());
  }

  // Save play queue to the backend on updates, debounced
  Timer? saveQueueDebounce;
  void triggerSaveQueue() {
    saveQueueDebounce?.cancel();
    saveQueueDebounce = Timer(const Duration(milliseconds: 1500), () async {
      final backend = ref.read(musicBackendProvider);
      if (backend == null) return;

      final tracks = svc.currentQueue;
      if (tracks.isEmpty) return;

      final trackIds = tracks.map((t) => t.id).toList();
      final currentIndex = svc.currentIndex;
      final position = svc.position;

      try {
        await backend.savePlayQueue(
          trackIds,
          currentIndex: currentIndex >= 0 ? currentIndex : 0,
          position: position,
        );
      } catch (e) {
        afLog('audio', 'Failed to save play queue', error: e);
      }
    });
  }

  final queueSub = svc.queueStream.listen((_) => triggerSaveQueue());
  final trackSub = svc.currentTrackStream.listen((_) => triggerSaveQueue());

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
      final existingIds = svc.currentQueue.map((t) => t.id).toSet();
      const targetSize = 20;
      final results = <AfTrack>[];
      final seenIds = Set<String>.from(existingIds);

      // 1. Initial similar mix query
      final mix = await backend.instantMix(lastTrack.id, limit: targetSize);
      for (final t in mix) {
        if (results.length >= targetSize) break;
        if (seenIds.add(t.id)) {
          results.add(t);
        }
      }

      // 2. Similarity Propagation (Graph Walk)
      // If we don't have enough tracks, walk the graph of recommendations using the last added track
      int lastLength = results.length;
      for (int step = 0; step < 3 && results.length < targetSize; step++) {
        final nextSeed = results.isNotEmpty ? results.last : lastTrack;
        try {
          final nextMix = await backend.instantMix(nextSeed.id, limit: targetSize);
          for (final t in nextMix) {
            if (results.length >= targetSize) break;
            if (seenIds.add(t.id)) {
              results.add(t);
            }
          }
        } catch (_) {
          break; // Stop propagation on error
        }
        if (results.length == lastLength) {
          break; // No new tracks added
        }
        lastLength = results.length;
      }

      // 3. Artist Top Tracks Fallback
      if (results.length < targetSize) {
        final artistId = lastTrack.artistId;
        if (artistId != null && artistId.isNotEmpty) {
          try {
            final topTracks = await backend.artistTopTracks(artistId, limit: targetSize);
            for (final t in topTracks) {
              if (results.length >= targetSize) break;
              if (seenIds.add(t.id)) {
                results.add(t);
              }
            }
          } catch (_) {}
        }
      }

      // 4. Search Fallback (by artist name)
      if (results.length < targetSize) {
        final artistName = lastTrack.artistName;
        if (artistName.isNotEmpty) {
          try {
            final searchRes = await backend.search(artistName);
            for (final t in searchRes.tracks) {
              if (results.length >= targetSize) break;
              if (seenIds.add(t.id)) {
                results.add(t);
              }
            }
          } catch (_) {}
        }
      }

      // 5. Album Fallback
      if (results.length < targetSize) {
        final albumId = lastTrack.albumId;
        if (albumId != null && albumId.isNotEmpty) {
          try {
            final albumData = await backend.album(albumId);
            if (albumData != null) {
              for (final t in albumData.tracks) {
                if (results.length >= targetSize) break;
                if (seenIds.add(t.id)) {
                  results.add(t);
                }
              }
            }
          } catch (_) {}
        }
      }

      // 6. Recently Played Fallback
      if (results.length < targetSize) {
        try {
          final recent = await backend.recentlyPlayed(limit: targetSize);
          for (final t in recent) {
            if (results.length >= targetSize) break;
            if (seenIds.add(t.id)) {
              results.add(t);
            }
          }
        } catch (_) {}
      }

      return results;
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

  final reporter = JellyfinPlaybackReporter(
    svc,
    () => ref.read(musicBackendProvider),
    ref.read(appDatabaseProvider),
  );

  unawaited(svc.configureSpectrum());

  ref.listen<MusicBackend?>(musicBackendProvider, (prev, next) {
    if (prev != null && next == null) {
      reporter.requestStopOnDispose();
      unawaited(reporter.dispose());
    } else if (prev == null && next != null) {
      // User signed in or backend loaded, load the saved queue from server
      unawaited(loadSavedQueue());
    }
  });

  ref.onDispose(() async {
    saveQueueDebounce?.cancel();
    await queueSub.cancel();
    await trackSub.cancel();
    await errorSub.cancel();
    await reporter.dispose();
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
