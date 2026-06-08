import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../../utils/log.dart';
import '../backend/music_backend.dart';
import '../jellyfin/models/items.dart';
import '../youtube/youtube_music_client.dart';

/// Resolve the stream URL for [track] across local, server, and YouTube modes.
FutureOr<String> resolveStreamUrl(AfTrack track, Ref ref) async {
  final mode = ref.read(appModeProvider);
  final backend = ref.read(musicBackendProvider);

  if (mode == AppMode.local) return track.id;

  // YouTube Music: resolve actual stream URL via youtube_explode.
  if (backend is YouTubeMusicClient) {
    afLog(
      'aetherfin:youtube',
      'resolveStreamUrl start: id=${track.id} title=${track.title}',
    );
    try {
      final url = await backend.resolveStreamUrl(track.id);
      afLog(
        'aetherfin:youtube',
        'resolveStreamUrl OK: url=${url.substring(0, 100)}',
      );
      return url;
    } on Exception catch (e) {
      afLog(
        'aetherfin:error',
        'resolveStreamUrl failed for id=${track.id}',
        error: e,
      );
      return 'about:blank';
    }
  }

  final cache = ref.read(offlineCacheServiceProvider);
  if (ref.read(offlineCacheEnabledProvider)) {
    final cachedUri = await cache.cachedFileUri(track.id);
    if (cachedUri != null) return cachedUri;
  }
  if (backend != null) {
    final maxBitrate = ref.read(maxBitrateProvider);
    return backend.trackStreamUrl(
      track.id,
      maxBitrateKbps: maxBitrate == 0 ? null : maxBitrate,
    );
  }
  return 'about:blank';
}

/// Find similar tracks for [seed] from the local library or server instant mix.
Future<List<AfTrack>> getSimilarTracks(
  AfTrack seed,
  Set<String> seenIds,
  Ref ref,
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
    } on Exception catch (e, stack) {
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
    } on Exception catch (e, stack) {
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
    } on Exception catch (e, stack) {
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
  } on Exception catch (e) {
    afLog('audio', 'Artist tracks query failed during instant mix', error: e);
  }

  return results;
}

/// Backfill the queue to reach at least [targetSize] tracks using similarity
/// propagation, artist top tracks, search, and album fallbacks.
Future<List<AfTrack>> backfillQueue(
  MusicBackend backend,
  List<AfTrack> initialQueue,
  Ref ref, {
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
  } on Exception catch (e, stack) {
    afLog(
      'play-actions',
      'Failed to load recently skipped track IDs',
      error: e,
      stackTrace: stack,
    );
  }

  // 1. Similarity Propagation (Graph Walk)
  int lastQueueLength = queue.length;
  for (int step = 0; step < 4 && queue.length < targetSize; step++) {
    if (queue.isEmpty) break;
    final nextSeed = queue.last;
    try {
      final nextMix = await backend.instantMix(nextSeed.id, limit: targetSize);
      final newTracks = nextMix.where((t) => !seenIds.contains(t.id)).toList();
      if (newTracks.isEmpty) break;
      for (final t in newTracks) {
        if (queue.length >= targetSize) break;
        if (seenIds.add(t.id)) queue.add(t);
      }
    } on Exception catch (e, stack) {
      afLog(
        'audio',
        'Propagation step failed for track=${nextSeed.id}',
        error: e,
        stackTrace: stack,
      );
      break;
    }
    if (queue.length == lastQueueLength) break;
    lastQueueLength = queue.length;
  }

  // 2. Artist Top Tracks Fallback
  if (queue.length < targetSize && queue.isNotEmpty) {
    final seed = queue.first;
    final artistId = seed.artistId;
    final artistName = seed.artistName;
    if (artistId != null &&
        artistId.isNotEmpty &&
        !isGenericArtist(artistName)) {
      try {
        final topTracks = await backend.artistTopTracks(
          artistId,
          limit: targetSize,
        );
        for (final t in topTracks) {
          if (queue.length >= targetSize) break;
          if (seenIds.add(t.id)) queue.add(t);
        }
      } on Exception catch (e, stack) {
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
  if (queue.length < targetSize && queue.isNotEmpty) {
    final seed = queue.first;
    final artistName = seed.artistName;
    if (artistName.isNotEmpty && !isGenericArtist(artistName)) {
      try {
        final searchRes = await backend.search(artistName);
        final cleanArtistName = artistName.trim().toLowerCase();
        for (final t in searchRes.tracks) {
          if (queue.length >= targetSize) break;
          if (t.artistName.trim().toLowerCase() == cleanArtistName) {
            if (seenIds.add(t.id)) queue.add(t);
          }
        }
      } on Exception catch (e, stack) {
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
  if (queue.length < targetSize && queue.isNotEmpty) {
    final seed = queue.first;
    final albumId = seed.albumId;
    final albumName = seed.albumName;
    if (albumId != null && albumId.isNotEmpty && !isGenericAlbum(albumName)) {
      try {
        final albumData = await backend.album(albumId);
        if (albumData != null) {
          for (final t in albumData.tracks) {
            if (queue.length >= targetSize) break;
            if (seenIds.add(t.id)) queue.add(t);
          }
        }
      } on Exception catch (e, stack) {
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

bool isGenericArtist(String name) {
  final clean = name.trim().toLowerCase();
  return clean.isEmpty ||
      clean == 'unknown' ||
      clean == 'unknown artist' ||
      clean == 'various' ||
      clean == 'various artists';
}

bool isGenericAlbum(String name) {
  final clean = name.trim().toLowerCase();
  return clean.isEmpty || clean == 'unknown' || clean == 'unknown album';
}

String computeSourceLabel(List<AfTrack> tracks) {
  if (tracks.isEmpty) return 'Unknown';
  final first = tracks.first;
  if (first.albumName.isNotEmpty) return 'Album: ${first.albumName}';
  if (first.artistName.isNotEmpty) return 'Artist: ${first.artistName}';
  if (tracks.length == 1) return 'Single: ${first.title}';
  return 'Queue (${tracks.length} tracks)';
}

String computeSourceType() => 'manual';
