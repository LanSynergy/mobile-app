import 'dart:convert';

import 'package:drift/drift.dart';

import 'app_database.dart';

class LastFmCacheRepository {
  LastFmCacheRepository(this.db);
  final AppDatabase db;

  static const _ttl = Duration(days: 7);

  Future<List<String>?> get(String trackId) async {
    final query = db.select(db.lastfmSimilarCache)
      ..where((t) => t.trackId.equals(trackId));
    final row = await query.getSingleOrNull();
    if (row == null) return null;
    final age = DateTime.now().millisecondsSinceEpoch - row.cachedAt;
    if (age > _ttl.inMilliseconds) {
      // Delete expired entry to prevent unbounded table growth
      await (db.delete(
        db.lastfmSimilarCache,
      )..where((t) => t.trackId.equals(trackId))).go();
      return null;
    }
    final list = jsonDecode(row.similarTrackIds) as List;
    return list.cast<String>();
  }

  Future<void> set(String trackId, List<String> similarTrackIds) async {
    await db
        .into(db.lastfmSimilarCache)
        .insert(
          LastfmSimilarCacheCompanion.insert(
            trackId: trackId,
            similarTrackIds: jsonEncode(similarTrackIds),
            cachedAt: DateTime.now().millisecondsSinceEpoch,
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  /// Delete all expired cache entries. Called periodically to reclaim space.
  Future<int> pruneExpired() async {
    final cutoff = DateTime.now().millisecondsSinceEpoch - _ttl.inMilliseconds;
    await db.customStatement(
      'DELETE FROM lastfm_similar_cache WHERE cached_at < ?',
      [cutoff],
    );
    return 0; // customStatement returns void
  }
}
