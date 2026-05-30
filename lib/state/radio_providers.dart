import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/backend/music_backend.dart';
import '../core/jellyfin/models/items.dart';
import 'local_library_providers.dart';
import 'music_backend_providers.dart';
import 'settings_providers.dart';

final radioGeneratorProvider = Provider<RadioGenerator>((ref) {
  return RadioGenerator(ref);
});

class RadioGenerator {
  RadioGenerator(this.ref);
  final Ref ref;

  /// Generates a radio queue seeded by a single track.
  Future<List<AfTrack>> generateTrackRadio(AfTrack seed) async {
    final client = ref.read(lastFmClientProvider);
    final backend = ref.read(musicBackendProvider);
    if (backend == null) return [seed];

    // 1. Try Last.fm similar tracks if connected
    if (client != null) {
      try {
        final candidates = await client.getSimilar(
          artistName: seed.artistName,
          trackTitle: seed.title,
          limit: 25,
        );

        if (candidates.isNotEmpty) {
          final resolved = await _resolveCandidates(backend, candidates);
          if (resolved.isNotEmpty) {
            // Prepend seed track so it plays first
            return [seed, ...resolved];
          }
        }
      } catch (_) {}
    }

    // 2. Fallback to backend instant mix
    try {
      final mix = await backend.instantMix(seed.id, limit: 30);
      if (mix.isNotEmpty) {
        return [seed, ...mix];
      }
    } catch (_) {}

    // 3. Fallback to local SQLite similar tracks if local backend
    if (backend.serverType == ServerType.local) {
      try {
        final db = ref.read(localLibraryProvider).db;
        final list = await db.getSimilarTracks(seed.id, limit: 30);
        return [seed, ...list];
      } catch (_) {}
    }

    return [seed];
  }

  /// Generates a radio queue seeded by an artist name.
  Future<List<AfTrack>> generateArtistRadio(
    String artistName,
    String? artistId,
  ) async {
    final client = ref.read(lastFmClientProvider);
    final backend = ref.read(musicBackendProvider);
    if (backend == null) return const [];

    // 1. Try Last.fm to get similar artists
    if (client != null) {
      try {
        final similarArtists = await client.getSimilarArtists(
          artistName: artistName,
          limit: 15,
        );

        if (similarArtists.isNotEmpty) {
          final resolved = await _resolveArtistsTracks(backend, similarArtists);
          if (resolved.isNotEmpty) {
            return resolved;
          }
        }
      } catch (_) {}
    }

    // 2. Fallback to artist top tracks or general artist query search
    try {
      if (artistId != null) {
        final top = await backend.artistTopTracks(artistId, limit: 20);
        if (top.isNotEmpty) return top;
      } else {
        final results = await backend.search(artistName);
        if (results.tracks.isNotEmpty) return results.tracks;
      }
    } catch (_) {}

    return const [];
  }

  /// Concurrently resolve track candidates using batch searches.
  Future<List<AfTrack>> _resolveCandidates(
    MusicBackend backend,
    List<({String artist, String title})> candidates,
  ) async {
    final resolved = <AfTrack>[];

    // Process in batches of 5 to avoid overloading connections
    const batchSize = 5;
    for (var i = 0; i < candidates.length; i += batchSize) {
      final batch = candidates.skip(i).take(batchSize);
      final futures = batch.map((c) async {
        try {
          if (backend.serverType == ServerType.local) {
            final db = ref.read(localLibraryProvider).db;
            return await db.searchTrackByArtistAndTitle(c.artist, c.title);
          } else {
            final results = await backend.search('${c.artist} ${c.title}');
            for (final track in results.tracks) {
              if (track.title.toLowerCase() == c.title.toLowerCase() &&
                  track.artistName.toLowerCase() == c.artist.toLowerCase()) {
                return track;
              }
            }
            // Soft match
            for (final track in results.tracks) {
              if (track.title.toLowerCase().contains(c.title.toLowerCase()) &&
                  track.artistName.toLowerCase().contains(
                    c.artist.toLowerCase(),
                  )) {
                return track;
              }
            }
          }
        } catch (_) {}
        return null;
      });

      final results = await Future.wait(futures);
      resolved.addAll(results.whereType<AfTrack>());

      // Cap resolved queue size to 15 similar tracks
      if (resolved.length >= 15) break;
    }

    return resolved;
  }

  /// Resolve 1-2 tracks for each similar artist name.
  Future<List<AfTrack>> _resolveArtistsTracks(
    MusicBackend backend,
    List<String> artistNames,
  ) async {
    final resolved = <AfTrack>[];

    // Process in batches of 4
    const batchSize = 4;
    for (var i = 0; i < artistNames.length; i += batchSize) {
      final batch = artistNames.skip(i).take(batchSize);
      final futures = batch.map((name) async {
        try {
          if (backend.serverType == ServerType.local) {
            final db = ref.read(localLibraryProvider).db;
            final tracks = await db.tracksByArtist(name);
            return tracks.take(2).toList();
          } else {
            final results = await backend.search(name);
            final artistTracks = results.tracks
                .where((t) => t.artistName.toLowerCase() == name.toLowerCase())
                .take(2)
                .toList();
            if (artistTracks.isNotEmpty) return artistTracks;

            return results.tracks
                .where(
                  (t) =>
                      t.artistName.toLowerCase().contains(name.toLowerCase()),
                )
                .take(2)
                .toList();
          }
        } catch (_) {}
        return <AfTrack>[];
      });

      final results = await Future.wait(futures);
      for (final list in results) {
        resolved.addAll(list);
      }

      if (resolved.length >= 20) break;
    }

    return resolved;
  }
}
