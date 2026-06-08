import '../../utils/log.dart';
import '../backend/music_backend.dart';
import '../jellyfin/models/items.dart';
import '../lastfm/lastfm_client.dart';
import '../local/local_db.dart';

/// Resolves candidate tracks for the smart queue from multiple sources
/// (local DB, server instant-mix, Last.fm similar tracks).
class QueueCandidateProvider {
  const QueueCandidateProvider({this.localDb, this.backend, this.lastfmClient});

  final LocalDb? localDb;
  final MusicBackend? backend;
  final LastFmClient? lastfmClient;

  /// Gather candidate tracks from all available sources, excluding the
  /// seed itself and recently played tracks.
  Future<Set<AfTrack>> getCandidates(
    AfTrack seed,
    Set<String> recentlyPlayedIds,
  ) async {
    final candidates = <AfTrack>{};

    if (localDb != null) {
      await _addLocalCandidates(seed, candidates);
    }

    if (backend != null) {
      await _addServerCandidates(seed, candidates);
    }

    if (lastfmClient != null && localDb != null) {
      await _addLastFmCandidates(seed, candidates);
    }

    candidates.remove(seed);
    candidates.removeWhere((t) => recentlyPlayedIds.contains(t.id));

    return candidates;
  }

  Future<void> _addLocalCandidates(
    AfTrack seed,
    Set<AfTrack> candidates,
  ) async {
    final db = localDb!;
    try {
      if (seed.genre != null && seed.genre!.isNotEmpty) {
        final byGenre = await db.tracksByGenre(seed.genre!);
        candidates.addAll(byGenre.take(20));
      }
      final byArtist = await db.tracksByArtist(seed.artistName);
      candidates.addAll(byArtist.take(10));

      final coOccurred = await db.coOccurrences.getTopCoOccurred(
        seed.id,
        limit: 15,
      );
      if (coOccurred.isNotEmpty) {
        final coTracks = await db.tracksByIds(coOccurred);
        candidates.addAll(coTracks);
      }
    } on Exception catch (e, stack) {
      afLog(
        'error',
        'SmartQueue._addLocalCandidates failed',
        error: e,
        stackTrace: stack,
      );
    }
  }

  Future<void> _addServerCandidates(
    AfTrack seed,
    Set<AfTrack> candidates,
  ) async {
    try {
      final mix = await backend!.instantMix(seed.id, limit: 50);
      candidates.addAll(mix);
    } on Exception catch (e, stack) {
      afLog(
        'error',
        'SmartQueue._addServerCandidates failed',
        error: e,
        stackTrace: stack,
      );
    }
  }

  Future<void> _addLastFmCandidates(
    AfTrack seed,
    Set<AfTrack> candidates,
  ) async {
    try {
      // Check cache first
      final cached = await localDb!.lastfm.get(seed.id);
      if (cached != null && cached.isNotEmpty) {
        final cachedTracks = await localDb!.tracksByIds(cached);
        candidates.addAll(cachedTracks);
        return;
      }
      // Fetch from API
      final List<({String artist, String title})> results = await lastfmClient!
          .getSimilar(artistName: seed.artistName, trackTitle: seed.title);
      if (results.isEmpty) return;
      // Batch-fetch tracks for all unique artists in one query.
      final uniqueArtists = results
          .where((r) => r.artist.isNotEmpty && r.title.isNotEmpty)
          .map((r) => r.artist)
          .toSet();
      final Map<String, List<AfTrack>> artistTrackMap = await localDb!
          .tracksByArtists(uniqueArtists);
      // Match results to local tracks
      final matched = <String>[];
      for (final ({String artist, String title}) r in results) {
        if (r.artist.isEmpty || r.title.isEmpty) continue;
        for (final AfTrack t
            in (artistTrackMap[r.artist] ?? const <AfTrack>[])) {
          if (_fuzzyMatch(t.title, r.title)) {
            candidates.add(t);
            matched.add(t.id);
            break;
          }
        }
      }
      // Cache matched IDs
      if (matched.isNotEmpty) {
        await localDb!.lastfm.set(seed.id, matched);
      }
    } on Exception catch (e, stack) {
      afLog(
        'error',
        'SmartQueue._addLastFmCandidates failed',
        error: e,
        stackTrace: stack,
      );
    }
  }

  bool _fuzzyMatch(String a, String b) {
    return a.trim().toLowerCase() == b.trim().toLowerCase();
  }
}
