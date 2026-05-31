import 'package:drift/drift.dart';
import 'app_database.dart';

class TrackStatsRepository {
  TrackStatsRepository(this.db);
  final AppDatabase db;

  Future<TrackStatsEntity?> getStats(String trackId) async {
    final query = db.select(db.trackStats)
      ..where((t) => t.trackId.equals(trackId));
    return query.getSingleOrNull();
  }

  Future<Map<String, TrackStatsEntity>> getStatsForTracks(
    List<String> trackIds,
  ) async {
    if (trackIds.isEmpty) return const {};
    final result = <String, TrackStatsEntity>{};
    const chunkSize = 500;
    for (var i = 0; i < trackIds.length; i += chunkSize) {
      final chunk = trackIds.sublist(
        i,
        i + chunkSize > trackIds.length ? trackIds.length : i + chunkSize,
      );
      final query = db.select(db.trackStats)
        ..where((t) => t.trackId.isIn(chunk));
      final rows = await query.get();
      for (final row in rows) {
        result[row.trackId] = row;
      }
    }
    return result;
  }

  Future<void> recordPlay(
    String trackId, {
    required double completionRate,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = await getStats(trackId);
    if (existing == null) {
      await db
          .into(db.trackStats)
          .insert(
            TrackStatsCompanion.insert(
              trackId: trackId,
              playCount: const Value(1),
              avgCompletion: Value(completionRate),
              lastPlayed: Value(now),
            ),
          );
    } else {
      final newAvg =
          ((existing.avgCompletion * existing.playCount) + completionRate) /
          (existing.playCount + 1);
      await (db.update(
        db.trackStats,
      )..where((t) => t.trackId.equals(trackId))).write(
        TrackStatsCompanion(
          playCount: Value(existing.playCount + 1),
          avgCompletion: Value(newAvg),
          lastPlayed: Value(now),
        ),
      );
    }
  }

  Future<void> recordSkip(
    String trackId, {
    required double completionRate,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = await getStats(trackId);
    if (existing == null) {
      await db
          .into(db.trackStats)
          .insert(
            TrackStatsCompanion.insert(
              trackId: trackId,
              skipCount: const Value(1),
              avgCompletion: Value(completionRate),
              lastPlayed: Value(now),
            ),
          );
    } else {
      final newAvg =
          ((existing.avgCompletion * existing.playCount) + completionRate) /
          (existing.playCount + 1);
      await (db.update(
        db.trackStats,
      )..where((t) => t.trackId.equals(trackId))).write(
        TrackStatsCompanion(
          skipCount: Value(existing.skipCount + 1),
          avgCompletion: Value(newAvg),
          lastPlayed: Value(now),
        ),
      );
    }
  }

  Future<void> deleteStats(String trackId) async {
    await (db.delete(
      db.trackStats,
    )..where((t) => t.trackId.equals(trackId))).go();
  }
}
