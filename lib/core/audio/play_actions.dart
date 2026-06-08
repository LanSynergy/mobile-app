import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../../utils/log.dart';
import '../backend/music_backend.dart';
import '../jellyfin/models/items.dart';
import '../youtube/youtube_music_client.dart';

/// Cross-cutting "Play" entry points used by every screen so that we
/// don't replicate the wiring (and so the spectral provider always
/// updates first — per spec §3.4).
class PlayActions {
  PlayActions(this.ref);
  final Ref ref;

  /// Replace the queue with [tracks] and start playback at [startIndex].
  /// If shuffle mode is ON, the selected track plays first and the rest
  /// are shuffled below it.
  Future<void> playQueue(List<AfTrack> tracks, {int startIndex = 0}) async {
    if (tracks.isEmpty) return;
    final svc = ref.read(playerServiceProvider);
    final mode = ref.read(appModeProvider);
    final backend = ref.read(musicBackendProvider);

    // In local mode, the track ID is the content:// URI itself.
    // In server mode, check offline cache first, then the backend.
    // For YouTube Music, resolve the actual stream URL asynchronously.
    FutureOr<String> resolveStreamUrl(AfTrack t) async {
      if (mode == AppMode.local) return t.id;

      // YouTube Music: resolve actual stream URL via youtube_explode.
      if (backend is YouTubeMusicClient) {
        afLog(
          'aetherfin:youtube',
          'resolveStreamUrl start: id=${t.id} title=${t.title}',
        );
        try {
          final url = await backend.resolveStreamUrl(t.id);
          afLog(
            'aetherfin:youtube',
            'resolveStreamUrl OK: url=${url.substring(0, 100)}',
          );
          return url;
        } catch (e) {
          afLog(
            'aetherfin:error',
            'resolveStreamUrl failed for id=${t.id}',
            error: e,
          );
          return 'about:blank';
        }
      }

      final cache = ref.read(offlineCacheServiceProvider);
      if (ref.read(offlineCacheEnabledProvider)) {
        final cachedUri = await cache.cachedFileUri(t.id);
        if (cachedUri != null) return cachedUri;
      }
      if (backend != null) {
        final maxBitrate = ref.read(maxBitrateProvider);
        return backend.trackStreamUrl(
          t.id,
          maxBitrateKbps: maxBitrate == 0 ? null : maxBitrate,
        );
      }
      return 'about:blank';
    }

    final safeIndex = startIndex < 0
        ? 0
        : (startIndex >= tracks.length ? tracks.length - 1 : startIndex);

    // Don't pre-shuffle here — let mpv's shuffle mode handle randomization.
    // Pre-shuffling corrupts _originalQueue so that toggling shuffle off
    // later restores to the shuffled order instead of the original.
    final wasShuffleEnabled = svc.isShuffleEnabled == true;
    try {
      await svc.playQueue(
        tracks,
        startIndex: safeIndex,
        resolveStreamUrl: resolveStreamUrl,
        // No auth headers needed for local files.
        streamHeaders: mode == AppMode.local
            ? const {}
            : (backend?.authHeaders ?? const {}),
      );
      if (wasShuffleEnabled) {
        await svc.setAfShuffleMode(true);
      }
      ref.read(currentTrackProvider.notifier).state = tracks[safeIndex];

      // Save to queue history (non-critical — log warnings, don't throw)
      try {
        final repo = ref.read(queueHistoryRepositoryProvider);
        final sourceLabel = _computeSourceLabel(tracks);
        final sourceType = _computeSourceType();
        final sourceId = tracks.isNotEmpty
            ? tracks[0].albumId ?? tracks[0].artistId
            : null;
        await repo.save(
          trackIds: tracks.map((t) => t.id).toList(),
          sourceLabel: sourceLabel,
          sourceType: sourceType,
          sourceId: sourceId,
        );
      } catch (e, stack) {
        afLog('data', 'queueHistory save failed', error: e, stackTrace: stack);
      }
    } catch (e, stack) {
      afLog('audio', 'playQueue failed', error: e, stackTrace: stack);
      rethrow;
    }
  }

  Future<void> playAlbum(List<AfTrack> tracks) => playQueue(tracks);

  Future<void> playSingle(AfTrack track) async {
    await playQueue([track], startIndex: 0);

    final svc = ref.read(playerServiceProvider);
    final mode = ref.read(appModeProvider);
    final backend = ref.read(musicBackendProvider);

    FutureOr<String> resolveStreamUrl(AfTrack t) async {
      if (mode == AppMode.local) return t.id;

      // YouTube Music: resolve actual stream URL via youtube_explode.
      if (backend is YouTubeMusicClient) {
        afLog('aetherfin:youtube', 'resolveStreamUrl (playSingle): id=${t.id}');
        try {
          final url = await backend.resolveStreamUrl(t.id);
          afLog(
            'aetherfin:youtube',
            'resolveStreamUrl (playSingle) OK: ${url.substring(0, 100)}',
          );
          return url;
        } catch (e) {
          afLog(
            'aetherfin:error',
            'resolveStreamUrl (playSingle) failed for id=${t.id}',
            error: e,
          );
          return 'about:blank';
        }
      }

      final cache = ref.read(offlineCacheServiceProvider);
      if (ref.read(offlineCacheEnabledProvider)) {
        final cachedUri = await cache.cachedFileUri(t.id);
        if (cachedUri != null) return cachedUri;
      }
      if (backend != null) {
        final maxBitrate = ref.read(maxBitrateProvider);
        return backend.trackStreamUrl(
          t.id,
          maxBitrateKbps: maxBitrate == 0 ? null : maxBitrate,
        );
      }
      return 'about:blank';
    }

    final existingIds = svc.currentQueue.map((t) => t.id).toSet();
    final toAppend = <AfTrack>[];

    // 1. Smart queue buffer
    if (ref.read(smartQueueEnabledProvider)) {
      final sq = ref.read(smartQueueManagerProvider);
      await sq.refillBuffer(track);
      for (final t in sq.dequeueBatch(20)) {
        if (toAppend.length >= 20) break;
        if (existingIds.add(t.id)) toAppend.add(t);
      }
    }

    // 2. Fallback until we hit 20
    if (toAppend.length < 20) {
      final similar = await _getSimilarTracks(track, existingIds);
      for (final t in similar) {
        if (toAppend.length >= 20) break;
        if (existingIds.add(t.id)) toAppend.add(t);
      }
    }

    if (toAppend.isEmpty) return;
    await svc.appendQueue(toAppend, resolveStreamUrl: resolveStreamUrl);
  }

  /// Play a track followed by all other tracks scored and sorted by smart queue.
  /// Most relevant (genre/artist/affinity) come first, least relevant last.
  /// Skips and plays refine the scoring over time.
  Future<void> playSmartQueue(AfTrack seed, List<AfTrack> allTracks) async {
    if (allTracks.isEmpty) return;
    final sqEnabled = ref.read(smartQueueEnabledProvider);

    List<AfTrack> sorted;
    if (sqEnabled && allTracks.length > 1) {
      sorted = await ref
          .read(smartQueueManagerProvider)
          .scoreAndSort(seed, allTracks);
    } else {
      sorted = List.from(allTracks);
    }

    // Ensure seed is first
    final seedIdx = sorted.indexWhere((t) => t.id == seed.id);
    if (seedIdx > 0) {
      sorted.removeAt(seedIdx);
      sorted.insert(0, seed);
    }

    await playQueue(sorted, startIndex: 0);
  }

  Future<List<AfTrack>> _getSimilarTracks(
    AfTrack seed,
    Set<String> seenIds,
  ) async {
    final mode = ref.read(appModeProvider);

    if (mode == AppMode.server) {
      final backend = ref.read(musicBackendProvider);
      if (backend == null) return const [];
      try {
        final mix = await backend.instantMix(seed.id, limit: 30);
        return mix
            .where((t) => t.id != seed.id && seenIds.add(t.id))
            .take(20)
            .toList();
      } catch (e, stack) {
        afLog(
          'play-actions',
          'Instant mix failed for seed=${seed.id}',
          error: e,
          stackTrace: stack,
        );
        return const [];
      }
    }

    // Local mode
    final localLib = ref.read(localLibraryProvider);
    final db = localLib.db;
    final results = <AfTrack>[];

    if (seed.genre != null && seed.genre!.isNotEmpty) {
      try {
        for (final t in await db.tracksByGenre(seed.genre!)) {
          if (results.length >= 20) break;
          if (seenIds.add(t.id)) results.add(t);
        }
      } catch (e, stack) {
        afLog(
          'play-actions',
          'Genre lookup failed for genre=${seed.genre}',
          error: e,
          stackTrace: stack,
        );
      }

      try {
        for (final t in await db.tracksByArtist(seed.artistName)) {
          if (results.length >= 20) break;
          if (seenIds.add(t.id)) results.add(t);
        }
      } catch (e, stack) {
        afLog(
          'play-actions',
          'Artist lookup failed for artist=${seed.artistName}',
          error: e,
          stackTrace: stack,
        );
      }
    }

    try {
      for (final t in await db.tracksByArtist(seed.artistName)) {
        if (results.length >= 20) break;
        if (seenIds.add(t.id)) results.add(t);
      }
    } catch (_) {}

    return results;
  }

  /// Replace the queue with the seed track followed by [Jellyfin's Instant
  /// Mix](https://api.jellyfin.org/#tag/InstantMix/operation/GetInstantMixFromItem)
  /// of similar songs. Implements the user's "generate queue related song
  /// based on the song played" feature.
  ///
  /// On signed-out / demo builds this falls back to playing the single track
  /// because there's no server to query — surfacing an error toast would be
  /// noisier than silently playing what we have.
  Future<void> playInstantMix(AfTrack seed, {bool wait = false}) async {
    // 1. Play the seed track immediately so the user doesn't wait
    await playQueue([seed], startIndex: 0);

    final backend = ref.read(musicBackendProvider);
    if (backend == null) return;

    // 2. Fetch the mix and backfill
    final future = () async {
      try {
        final localLib = ref.read(localLibraryProvider);
        final skippedIds = await localLib.db
            .getRecentlySkippedTrackIds()
            .catchError((_) => <String>[]);
        final mix = await backend.instantMix(seed.id);

        var queue = <AfTrack>[
          for (final t in mix)
            if (t.id != seed.id && !skippedIds.contains(t.id)) t,
        ];

        if (queue.length < 29) {
          // 29 because we already have seed in play
          final backfillSeedQueue = <AfTrack>[seed, ...queue];
          final backfilled = await _backfillQueue(
            backend,
            backfillSeedQueue,
            targetSize: 30,
          );
          queue = backfilled.where((t) => t.id != seed.id).toList();
        }

        if (queue.isNotEmpty) {
          final svc = ref.read(playerServiceProvider);
          // Only append if the active track is still the seed track
          if (svc.currentTrack?.id == seed.id) {
            final mode = ref.read(appModeProvider);
            FutureOr<String> resolveStreamUrl(AfTrack t) async {
              if (mode == AppMode.local) return t.id;
              final cache = ref.read(offlineCacheServiceProvider);
              if (ref.read(offlineCacheEnabledProvider)) {
                final cachedUri = await cache.cachedFileUri(t.id);
                if (cachedUri != null) return cachedUri;
              }
              final maxBitrate = ref.read(maxBitrateProvider);
              return backend.trackStreamUrl(
                t.id,
                maxBitrateKbps: maxBitrate == 0 ? null : maxBitrate,
              );
            }

            await svc.appendQueue(queue, resolveStreamUrl: resolveStreamUrl);
          }
        }
      } catch (e, stack) {
        afLog(
          'audio',
          'background instantMix/backfill failed',
          error: e,
          stackTrace: stack,
        );
      }
    }();

    if (wait) {
      await future;
    } else {
      unawaited(future);
    }
  }

  /// Backfill the queue to reach at least [targetSize] tracks using similarity propagation,
  /// artist top tracks, and other fallback strategies.
  Future<List<AfTrack>> _backfillQueue(
    MusicBackend backend,
    List<AfTrack> initialQueue, {
    int targetSize = 30,
  }) async {
    final queue = List<AfTrack>.from(initialQueue);
    final seenIds = queue.map((t) => t.id).toSet();
    try {
      final localLib = ref.read(localLibraryProvider);
      final skippedIds = await localLib.db
          .getRecentlySkippedTrackIds()
          .catchError((_) => <String>[]);
      seenIds.addAll(skippedIds);
    } catch (e, stack) {
      afLog(
        'play-actions',
        'Failed to load recently skipped track IDs',
        error: e,
        stackTrace: stack,
      );
    }

    // 1. Similarity Propagation (Graph Walk)
    // If we have some tracks but not enough, iteratively query instantMix for the last track.
    int lastQueueLength = queue.length;
    // Limit iterations to prevent infinite loops or excessive network requests (max 4 steps)
    for (int step = 0; step < 4 && queue.length < targetSize; step++) {
      if (queue.isEmpty) break;
      final nextSeed = queue.last;
      try {
        final nextMix = await backend.instantMix(
          nextSeed.id,
          limit: targetSize,
        );
        final newTracks = nextMix
            .where((t) => !seenIds.contains(t.id))
            .toList();
        if (newTracks.isEmpty) {
          break; // No new tracks found, stop propagation
        }
        for (final t in newTracks) {
          if (queue.length >= targetSize) break;
          if (seenIds.add(t.id)) {
            queue.add(t);
          }
        }
      } catch (e, stack) {
        afLog(
          'audio',
          'Propagation step failed for track=${nextSeed.id}',
          error: e,
          stackTrace: stack,
        );
        break; // Stop propagation on error
      }
      // If we didn't add any new tracks, stop
      if (queue.length == lastQueueLength) {
        break;
      }
      lastQueueLength = queue.length;
    }

    // 2. Artist Top Tracks Fallback
    // If still not enough, fetch top tracks from the seed's artist
    if (queue.length < targetSize && queue.isNotEmpty) {
      final seed = queue.first; // the original seed track
      final artistId = seed.artistId;
      final artistName = seed.artistName;
      if (artistId != null &&
          artistId.isNotEmpty &&
          !_isGenericArtist(artistName)) {
        try {
          final topTracks = await backend.artistTopTracks(
            artistId,
            limit: targetSize,
          );
          for (final t in topTracks) {
            if (queue.length >= targetSize) break;
            if (seenIds.add(t.id)) {
              queue.add(t);
            }
          }
        } catch (e, stack) {
          afLog(
            'audio',
            'Artist top tracks backfill failed for artistId=$artistId',
            error: e,
            stackTrace: stack,
          );
        }
      }
    }

    // 3. Search Fallback (by artist name)
    // If still not enough, search for the artist name to get related tracks
    if (queue.length < targetSize && queue.isNotEmpty) {
      final seed = queue.first;
      final artistName = seed.artistName;
      if (artistName.isNotEmpty && !_isGenericArtist(artistName)) {
        try {
          final searchRes = await backend.search(artistName);
          final cleanArtistName = artistName.trim().toLowerCase();
          for (final t in searchRes.tracks) {
            if (queue.length >= targetSize) break;
            // Strict filtering to ensure only tracks by the actual artist are added
            if (t.artistName.trim().toLowerCase() == cleanArtistName) {
              if (seenIds.add(t.id)) {
                queue.add(t);
              }
            }
          }
        } catch (e, stack) {
          afLog(
            'audio',
            'Search backfill failed for artistName=$artistName',
            error: e,
            stackTrace: stack,
          );
        }
      }
    }

    // 4. Album Fallback
    // If still not enough, try to fetch the album of the seed track
    if (queue.length < targetSize && queue.isNotEmpty) {
      final seed = queue.first;
      final albumId = seed.albumId;
      final albumName = seed.albumName;
      if (albumId != null &&
          albumId.isNotEmpty &&
          !_isGenericAlbum(albumName)) {
        try {
          final albumData = await backend.album(albumId);
          if (albumData != null) {
            for (final t in albumData.tracks) {
              if (queue.length >= targetSize) break;
              if (seenIds.add(t.id)) {
                queue.add(t);
              }
            }
          }
        } catch (e, stack) {
          afLog(
            'audio',
            'Album backfill failed for albumId=$albumId',
            error: e,
            stackTrace: stack,
          );
        }
      }
    }

    return queue;
  }

  bool _isGenericArtist(String name) {
    final clean = name.trim().toLowerCase();
    return clean.isEmpty ||
        clean == 'unknown' ||
        clean == 'unknown artist' ||
        clean == 'various' ||
        clean == 'various artists';
  }

  bool _isGenericAlbum(String name) {
    final clean = name.trim().toLowerCase();
    return clean.isEmpty || clean == 'unknown' || clean == 'unknown album';
  }

  String _computeSourceLabel(List<AfTrack> tracks) {
    if (tracks.isEmpty) return 'Unknown';
    final first = tracks.first;
    if (first.albumName.isNotEmpty) return 'Album: ${first.albumName}';
    if (first.artistName.isNotEmpty) return 'Artist: ${first.artistName}';
    if (tracks.length == 1) return 'Single: ${first.title}';
    return 'Queue (${tracks.length} tracks)';
  }

  String _computeSourceType() {
    return 'manual';
  }
}

final playActionsProvider = Provider<PlayActions>(PlayActions.new);
