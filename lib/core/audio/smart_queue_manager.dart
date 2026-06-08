import 'dart:async';
import 'dart:isolate';
import 'dart:math';

import 'package:drift/drift.dart';

import '../../utils/log.dart';
import '../backend/music_backend.dart';
import '../jellyfin/models/items.dart';
import '../lastfm/lastfm_client.dart';
import '../local/app_database.dart';
import '../local/local_db.dart';

// ---------------------------------------------------------------------------
// Top-level scoring functions (runnable in a background isolate)
// ---------------------------------------------------------------------------

/// Lightweight stats data for isolate transfer (replaces [TrackStatsEntity]
/// which carries drift internals that are not sendable across isolates).
class SimpleTrackStats {
  const SimpleTrackStats(this.avgCompletion, this.skipCount);
  final double avgCompletion;
  final int skipCount;
}

/// Parameters for the background scoring isolate.
class ScoringParams {
  const ScoringParams({
    required this.seed,
    required this.candidates,
    required this.recentlyPlayedIds,
    required this.statsMap,
    required this.coCountsMap,
    required this.maxCo,
  });

  final AfTrack seed;
  final List<AfTrack> candidates;
  final List<String> recentlyPlayedIds;
  final Map<String, SimpleTrackStats> statsMap;
  final Map<String, int> coCountsMap;
  final int maxCo;
}

/// Top-level scoring function executed in a background isolate.
/// Scores every [ScoringParams.candidates] against the seed and returns
/// them sorted by relevance (highest first).
List<AfTrack> scoreTracksInBackground(ScoringParams params) {
  final random = Random();
  final results = <MapEntry<AfTrack, double>>[];
  for (final candidate in params.candidates) {
    final score = scoreOneTrack(
      candidate,
      params.seed,
      params.recentlyPlayedIds,
      stats: params.statsMap[candidate.id],
      coCount: params.coCountsMap[candidate.id] ?? 0,
      maxCo: params.maxCo,
      random: random,
    );
    results.add(MapEntry(candidate, score));
  }
  results.sort((a, b) => b.value.compareTo(a.value));
  return results.map((e) => e.key).toList();
}

/// Score a single candidate against the seed. Extracted as a top-level
/// function so it can be used both from the background isolate and from
/// the in-process buffer scoring path.
double scoreOneTrack(
  AfTrack candidate,
  AfTrack seed,
  List<String> recentlyPlayedIds, {
  required SimpleTrackStats? stats,
  required int coCount,
  required int maxCo,
  required Random random,
}) {
  double s = 0.0;

  // 1. Co-occurrence (0.35)
  if (maxCo > 0) {
    s += (coCount / maxCo) * 0.35;
  }

  // 2. Genre match (0.20)
  if (candidate.genre != null &&
      seed.genre != null &&
      candidate.genre!.isNotEmpty &&
      candidate.genre == seed.genre) {
    s += 0.20;
  }

  // 3. Artist match (0.15)
  if (candidate.artistName == seed.artistName) {
    s += 0.15;
  }

  // 4. User affinity (0.20)
  if (stats != null) {
    final skipPenalty = stats.skipCount * 0.05;
    final affinity = (stats.avgCompletion - skipPenalty).clamp(0.0, 1.0);
    s += affinity * 0.20;
  } else {
    // Cold-start boost for tracks never played before
    s += 0.05;
  }

  // 5. Recency penalty (-0.15)
  final recentIndex = recentlyPlayedIds.indexOf(candidate.id);
  if (recentIndex != -1 && recentlyPlayedIds.isNotEmpty) {
    s -= (1.0 - recentIndex / recentlyPlayedIds.length) * 0.15;
  }

  // 6. Randomness (+0.10)
  s += random.nextDouble() * 0.10;

  return s.clamp(0.0, 1.0);
}

/// Smart queue manager: learns from listening behavior to suggest relevant
/// next tracks. Operates in two modes:
///   - **Local mode:** uses [LocalDb] for genre/artist/co-occurrence queries.
///   - **Server mode:** uses [MusicBackend.instantMix] + co-occurrence data.
///
/// Maintains an internal buffer of scored candidates. The player service
/// pulls from this buffer when the playback queue runs low.
class SmartQueueManager {
  SmartQueueManager({this.localDb, this.backend, this.lastfmClient});

  final LocalDb? localDb;
  final MusicBackend? backend;
  final LastFmClient? lastfmClient;

  /// Reused across scoring passes to avoid entropy-seeded allocations.
  final Random _random = Random();

  /// TTL cache for [_getRecentlyPlayedIds] — avoids redundant DB queries
  /// when both `refillBuffer` and `scoreAndSort` execute in the same cycle.
  Set<String>? _recentlyPlayedCache;
  DateTime? _recentlyPlayedCacheTime;
  static const Duration _recentlyPlayedTtl = Duration(seconds: 5);

  // ── Buffer ──────────────────────────────────────────────────────────────

  final List<AfTrack> _buffer = [];
  static const int bufferSize = 15;
  static const int refillThreshold = 5;

  bool get isBufferLow => _buffer.length < refillThreshold;
  int get bufferLength => _buffer.length;

  /// Dequeue up to [count] tracks from the buffer.
  List<AfTrack> dequeueBatch(int count) {
    if (_buffer.isEmpty) return const [];
    final actual = count > _buffer.length ? _buffer.length : count;
    final batch = _buffer.sublist(0, actual);
    _buffer.removeRange(0, actual);
    return batch;
  }

  /// Peek at the next track without removing it.
  AfTrack? peekNext() => _buffer.isNotEmpty ? _buffer.first : null;

  /// Clear the buffer entirely.
  void clearBuffer() => _buffer.clear();

  // ── Feedback loop ──────────────────────────────────────────────────────

  /// Record a completed play (track finished or advanced).
  Future<void> recordPlayback(
    AfTrack track, {
    required double completionRate,
    bool isSkipped = false,
  }) async {
    final stats = localDb?.trackStats;
    if (stats == null) return;
    try {
      if (isSkipped) {
        await stats.recordSkip(track.id, completionRate: completionRate);
      } else {
        await stats.recordPlay(track.id, completionRate: completionRate);
      }
      // Invalidate recently-played cache since history changed.
      _recentlyPlayedCache = null;
      _recentlyPlayedCacheTime = null;
    } on Exception catch (e, stack) {
      afLog(
        'error',
        'SmartQueue.recordPlayback failed',
        error: e,
        stackTrace: stack,
      );
    }
  }

  /// Record a transition from [from] → [to] when completion is >80%.
  Future<void> recordTransition(
    AfTrack from,
    AfTrack to, {
    required double completionRate,
  }) async {
    if (completionRate < 0.8) return;
    final co = localDb?.coOccurrences;
    if (co == null) return;
    try {
      await co.increment(from.id, to.id);
    } on Exception catch (e, stack) {
      afLog(
        'error',
        'SmartQueue.recordTransition failed',
        error: e,
        stackTrace: stack,
      );
    }
  }

  // ── Refill buffer ──────────────────────────────────────────────────────

  /// Refill the buffer if it's below the threshold, using [current] as seed.
  Future<void> refillBuffer(AfTrack current) async {
    if (_buffer.length >= bufferSize) return;
    try {
      final recentlyPlayedIds = await _getRecentlyPlayedIds();
      final candidates = await _getCandidates(current, recentlyPlayedIds);
      if (candidates.isEmpty) return;
      final scored = await _scoreAll(candidates, current, recentlyPlayedIds);
      final need = bufferSize - _buffer.length;
      final toAdd = scored.take(need).map((e) => e.key).toList();
      _buffer.addAll(toAdd);
    } on Exception catch (e, stack) {
      afLog(
        'error',
        'SmartQueue.refillBuffer failed',
        error: e,
        stackTrace: stack,
      );
    }
  }

  // ── Candidate provider ─────────────────────────────────────────────────

  Future<Set<AfTrack>> _getCandidates(
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

  Future<Set<String>> _getRecentlyPlayedIds({int limit = 20}) async {
    if (localDb == null) return {};
    // Return cached result if still within TTL.
    final now = DateTime.now();
    if (_recentlyPlayedCache != null && _recentlyPlayedCacheTime != null) {
      if (now.difference(_recentlyPlayedCacheTime!) < _recentlyPlayedTtl) {
        return _recentlyPlayedCache!;
      }
    }
    try {
      final rows = await localDb!.db
          .customSelect(
            'SELECT DISTINCT track_id FROM playback_history ORDER BY played_at DESC LIMIT ?1',
            variables: [Variable<int>(limit)],
            readsFrom: {localDb!.db.playbackHistory},
          )
          .get();
      final result = rows.map((r) => r.read<String>('track_id')).toSet();
      _recentlyPlayedCache = result;
      _recentlyPlayedCacheTime = now;
      return result;
    } catch (_) {
      return {};
    }
  }

  // ── Scoring engine ─────────────────────────────────────────────────────

  Future<List<MapEntry<AfTrack, double>>> _scoreAll(
    Set<AfTrack> candidates,
    AfTrack seed,
    Set<String> recentlyPlayedIds,
  ) async {
    final results = <MapEntry<AfTrack, double>>[];
    if (candidates.isEmpty) return results;

    final recentlyList = recentlyPlayedIds.toList();

    final candidateIds = candidates.map((c) => c.id).toList();

    final statsMap = localDb != null
        ? await localDb!.trackStats.getStatsForTracks(candidateIds)
        : const <String, TrackStatsEntity>{};

    final coCountsMap = localDb != null
        ? await localDb!.coOccurrences.getCountsForSeed(seed.id, candidateIds)
        : const <String, int>{};

    final maxCo = localDb != null
        ? await localDb!.coOccurrences.getMaxCount(seed.id)
        : 0;

    for (final candidate in candidates) {
      final rawStats = statsMap[candidate.id];
      final score = scoreOneTrack(
        candidate,
        seed,
        recentlyList,
        stats: rawStats != null
            ? SimpleTrackStats(rawStats.avgCompletion, rawStats.skipCount)
            : null,
        coCount: coCountsMap[candidate.id] ?? 0,
        maxCo: maxCo,
        random: _random,
      );
      results.add(MapEntry(candidate, score));
    }

    results.sort((a, b) => b.value.compareTo(a.value));
    return results;
  }

  /// Public scoring: score all [candidates] against [seed], return sorted.
  ///
  /// Runs the CPU-heavy scoring loop in a background isolate so large
  /// libraries (50K+ tracks) don't freeze the UI.
  Future<List<AfTrack>> scoreAndSort(
    AfTrack seed,
    List<AfTrack> candidates,
  ) async {
    if (candidates.isEmpty) return candidates;
    final recentlyPlayedIds = (await _getRecentlyPlayedIds(limit: 20)).toList();

    final candidateIds = candidates.map((c) => c.id).toList();

    final statsMap = localDb != null
        ? await localDb!.trackStats.getStatsForTracks(candidateIds)
        : const <String, TrackStatsEntity>{};

    final coCountsMap = localDb != null
        ? await localDb!.coOccurrences.getCountsForSeed(seed.id, candidateIds)
        : const <String, int>{};

    final maxCo = localDb != null
        ? await localDb!.coOccurrences.getMaxCount(seed.id)
        : 0;

    // Convert drift entities to lightweight sendable data.
    final simpleStats = <String, SimpleTrackStats>{};
    for (final entry in statsMap.entries) {
      simpleStats[entry.key] = SimpleTrackStats(
        entry.value.avgCompletion,
        entry.value.skipCount,
      );
    }

    final params = ScoringParams(
      seed: seed,
      candidates: candidates,
      recentlyPlayedIds: recentlyPlayedIds,
      statsMap: simpleStats,
      coCountsMap: coCountsMap,
      maxCo: maxCo,
    );

    return Isolate.run(() => scoreTracksInBackground(params));
  }
}
