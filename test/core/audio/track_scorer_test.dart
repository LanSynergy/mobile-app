import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:aetherfin/core/audio/track_scorer.dart';
import 'package:aetherfin/core/jellyfin/models/items.dart';

/// Shared seed track used across tests.
AfTrack _seed() => const AfTrack(
  id: 'seed-1',
  title: 'Seed Track',
  artistName: 'Seed Artist',
  albumName: 'Seed Album',
  genre: 'Rock',
);

/// Helper: score one track with sensible defaults.
double _score(
  AfTrack candidate, {
  AfTrack? seed,
  List<String> recentlyPlayedIds = const [],
  SimpleTrackStats? stats,
  int coCount = 0,
  int maxCo = 0,
  Random? random,
}) {
  return scoreOneTrack(
    candidate,
    seed ?? _seed(),
    recentlyPlayedIds,
    stats: stats,
    coCount: coCount,
    maxCo: maxCo,
    random: random ?? Random(42),
  );
}

void main() {
  // ---------------------------------------------------------------
  // 1. Seed track itself
  // ---------------------------------------------------------------
  test('seed track scored against itself with no boosts scores low', () {
    final seed = _seed();
    // Seed scored against itself: genre matches (+0.20), artist matches
    // (+0.15), no co-occurrence, no stats → cold-start +0.05.
    // If also recently played first (most recent), recency penalty
    // brings it down further. The caller is expected to exclude the
    // seed from candidates; this verifies scoreOneTrack doesn't
    // artificially boost the seed.
    final score = _score(
      seed,
      recentlyPlayedIds: [seed.id],
      stats: null,
      random: Random(0), // deterministic
    );
    // With recency penalty at index 0 of length 1: -(1 - 0/1)*0.15 = -0.15
    // Total: 0.20 + 0.15 + 0.05 - 0.15 + random*0.10 ≈ 0.25 + random*0.10
    // Should not be the highest possible score.
    expect(score, lessThanOrEqualTo(0.35));
  });

  // ---------------------------------------------------------------
  // 2. Same artist boost
  // ---------------------------------------------------------------
  test('same artist scores higher than different artist', () {
    final seed = _seed();
    const sameArtist = AfTrack(
      id: 'c1',
      title: 'Other Song',
      artistName: 'Seed Artist', // same
      albumName: 'Other Album',
      genre: 'Pop', // different genre to isolate artist effect
    );
    const diffArtist = AfTrack(
      id: 'c2',
      title: 'Another Song',
      artistName: 'Different Artist',
      albumName: 'Another Album',
      genre: 'Pop', // same genre as c1
    );
    final r = Random(42);
    final s1 = _score(sameArtist, seed: seed, random: r);
    final s2 = _score(diffArtist, seed: seed, random: r);
    // sameArtist should get +0.15 artist bonus over diffArtist
    expect(s1, greaterThan(s2));
  });

  // ---------------------------------------------------------------
  // 3. Same genre boost
  // ---------------------------------------------------------------
  test('same genre scores higher than different genre', () {
    final seed = _seed();
    const sameGenre = AfTrack(
      id: 'g1',
      title: 'Rock Song',
      artistName: 'Other Artist',
      albumName: 'Album',
      genre: 'Rock', // same
    );
    const diffGenre = AfTrack(
      id: 'g2',
      title: 'Pop Song',
      artistName: 'Other Artist',
      albumName: 'Album',
      genre: 'Pop',
    );
    final r = Random(42);
    final s1 = _score(sameGenre, seed: seed, random: r);
    final s2 = _score(diffGenre, seed: seed, random: r);
    // sameGenre should get +0.20 genre bonus over diffGenre
    expect(s1, greaterThan(s2));
  });

  // ---------------------------------------------------------------
  // 4. Co-occurrence boost
  // ---------------------------------------------------------------
  test('higher co-occurrence scores higher', () {
    const lowCo = AfTrack(
      id: 'low',
      title: 'Low Co',
      artistName: 'X',
      albumName: 'A',
    );
    const highCo = AfTrack(
      id: 'high',
      title: 'High Co',
      artistName: 'X',
      albumName: 'A',
    );
    final r = Random(42);
    final sLow = _score(lowCo, coCount: 2, maxCo: 10, random: r);
    final sHigh = _score(highCo, coCount: 9, maxCo: 10, random: r);
    // highCo gets (9/10)*0.35 = 0.315 vs (2/10)*0.35 = 0.07
    expect(sHigh, greaterThan(sLow));
  });

  // ---------------------------------------------------------------
  // 5. Recency penalty
  // ---------------------------------------------------------------
  test('recently played tracks score lower', () {
    const candidate = AfTrack(
      id: 'rec',
      title: 'Recent',
      artistName: 'X',
      albumName: 'A',
    );
    final r = Random(42);
    final sRecent = _score(
      candidate,
      recentlyPlayedIds: [candidate.id], // index 0 = most recent
      random: r,
    );
    final sNever = _score(
      candidate,
      recentlyPlayedIds: const [], // never played
      random: r,
    );
    // Recently played gets a -0.15 penalty
    expect(sRecent, lessThan(sNever));
  });

  test('recency penalty decreases for older tracks', () {
    const candidate = AfTrack(
      id: 'rec',
      title: 'Recent',
      artistName: 'X',
      albumName: 'A',
    );
    final list = ['other-1', 'other-2', candidate.id]; // index 2 of 3
    final r = Random(42);
    final sOlder = _score(candidate, recentlyPlayedIds: list, random: r);
    final listFresh = [candidate.id, 'other-1', 'other-2']; // index 0 of 3
    final sFresh = _score(candidate, recentlyPlayedIds: listFresh, random: r);
    // Fresh (index 0) has stronger penalty than older (index 2)
    expect(sFresh, lessThan(sOlder));
  });

  // ---------------------------------------------------------------
  // 6. Completion rate impact
  // ---------------------------------------------------------------
  test('high-completion track scores higher than frequently skipped track', () {
    const candidate = AfTrack(
      id: 'cmp',
      title: 'Song',
      artistName: 'X',
      albumName: 'A',
    );
    final r = Random(42);
    final sLoved = _score(
      candidate,
      stats: const SimpleTrackStats(0.95, 0), // 95% completion, 0 skips
      random: r,
    );
    final sHated = _score(
      candidate,
      stats: const SimpleTrackStats(0.10, 5), // 10% completion, 5 skips
      random: r,
    );
    // Loved: affinity = (0.95 - 0)*0.20 = 0.19
    // Hated: affinity = (0.10 - 0.25)→0.0*0.20 = 0.0
    expect(sLoved, greaterThan(sHated));
  });

  test('cold-start (no stats) scores higher than skipped track', () {
    const candidate = AfTrack(
      id: 'cold',
      title: 'Song',
      artistName: 'X',
      albumName: 'A',
    );
    final r = Random(42);
    final sCold = _score(
      candidate,
      stats: null, // cold-start → +0.05
      random: r,
    );
    final sSkipped = _score(
      candidate,
      stats: const SimpleTrackStats(0.0, 10), // 0% completion, 10 skips → 0.0
      random: r,
    );
    expect(sCold, greaterThan(sSkipped));
  });

  // ---------------------------------------------------------------
  // 7. Score range [0.0, 1.0]
  // ---------------------------------------------------------------
  test('all scores are between 0.0 and 1.0 inclusive', () {
    final rng = Random(123);
    final candidates = [
      const AfTrack(
        id: 'a',
        title: 'A',
        artistName: 'Art1',
        albumName: 'Alb',
        genre: 'Rock',
      ),
      const AfTrack(
        id: 'b',
        title: 'B',
        artistName: 'Art2',
        albumName: 'Alb',
        genre: 'Pop',
      ),
      const AfTrack(id: 'c', title: 'C', artistName: 'Art1', albumName: 'Alb'),
      const AfTrack(
        id: 'd',
        title: 'D',
        artistName: 'Art3',
        albumName: 'Alb',
        genre: 'Rock',
      ),
    ];
    final recentlyPlayed = ['a', 'b'];
    final statsMap = {
      'a': const SimpleTrackStats(0.8, 1),
      'c': const SimpleTrackStats(0.0, 10),
    };
    for (final c in candidates) {
      final score = _score(
        c,
        recentlyPlayedIds: recentlyPlayed,
        stats: statsMap[c.id],
        coCount: rng.nextInt(20),
        maxCo: 15,
        random: rng,
      );
      expect(score, greaterThanOrEqualTo(0.0));
      expect(score, lessThanOrEqualTo(1.0));
    }
  });

  // ---------------------------------------------------------------
  // 8. Determinism
  // ---------------------------------------------------------------
  test('same inputs produce same output with fixed random seed', () {
    const candidate = AfTrack(
      id: 'det',
      title: 'Deterministic',
      artistName: 'Art',
      albumName: 'Alb',
      genre: 'Rock',
    );
    const stats = SimpleTrackStats(0.7, 2);
    final recentlyPlayed = ['x', 'det', 'y'];

    double run() => _score(
      candidate,
      recentlyPlayedIds: recentlyPlayed,
      stats: stats,
      coCount: 5,
      maxCo: 10,
      random: Random(42),
    );

    // Run 3 times with identical inputs; all must match.
    final s1 = run();
    final s2 = run();
    final s3 = run();
    expect(s1, equals(s2));
    expect(s2, equals(s3));
  });

  // ---------------------------------------------------------------
  // 9. Different random seeds produce different scores
  // ---------------------------------------------------------------
  test('different random seeds can produce different scores', () {
    const candidate = AfTrack(
      id: 'rnd',
      title: 'Random',
      artistName: 'Art',
      albumName: 'Alb',
    );
    final s1 = _score(candidate, random: Random(1));
    final s2 = _score(candidate, random: Random(999));
    // With different seeds, the randomness component differs.
    // It's possible (but extremely unlikely) they coincidentally match.
    // This test documents that randomness is actually used.
    expect(s1, isNot(equals(s2)));
  });
}
