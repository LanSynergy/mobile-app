import 'dart:async';
import 'dart:math';

import 'package:drift/drift.dart';

import '../../utils/log.dart';
import '../backend/music_backend.dart';
import '../jellyfin/models/items.dart';
import '../lastfm/lastfm_client.dart';
import '../local/app_database.dart';
import '../local/local_db.dart';

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
    } catch (e, stack) {
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
    } catch (e, stack) {
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
    } catch (e, stack) {
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
    } catch (e, stack) {
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
    } catch (e, stack) {
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
    } catch (e, stack) {
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
    try {
      final rows = await localDb!.db
          .customSelect(
            'SELECT DISTINCT track_id FROM playback_history ORDER BY played_at DESC LIMIT ?1',
            variables: [Variable<int>(limit)],
            readsFrom: {localDb!.db.playbackHistory},
          )
          .get();
      return rows.map((r) => r.read<String>('track_id')).toSet();
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
      final score = _scoreOneSync(
        candidate,
        seed,
        recentlyList,
        stats: statsMap[candidate.id],
        coCount: coCountsMap[candidate.id] ?? 0,
        maxCo: maxCo,
      );
      results.add(MapEntry(candidate, score));
    }

    results.sort((a, b) => b.value.compareTo(a.value));
    return results;
  }

  double _scoreOneSync(
    AfTrack candidate,
    AfTrack seed,
    List<String> recentlyPlayedIds, {
    required TrackStatsEntity? stats,
    required int coCount,
    required int maxCo,
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
    s += _random.nextDouble() * 0.10;

    return s.clamp(0.0, 1.0);
  }

  /// Public scoring: score all [candidates] against [seed], return sorted.
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

    final scored = <MapEntry<AfTrack, double>>[];
    for (final c in candidates) {
      final s = _scoreOneSync(
        c,
        seed,
        recentlyPlayedIds,
        stats: statsMap[c.id],
        coCount: coCountsMap[c.id] ?? 0,
        maxCo: maxCo,
      );
      scored.add(MapEntry(c, s));
    }
    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.map((e) => e.key).toList();
  }
}
