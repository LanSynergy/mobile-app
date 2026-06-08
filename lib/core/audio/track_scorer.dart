import 'dart:math';

import '../jellyfin/models/items.dart';

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
