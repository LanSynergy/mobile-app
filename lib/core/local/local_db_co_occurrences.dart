import 'package:drift/drift.dart';
import 'app_database.dart';

class CoOccurrenceRepository {
  CoOccurrenceRepository(this.db);
  final AppDatabase db;

  Future<void> increment(String trackAId, String trackBId) async {
    final query = db.select(db.trackCoOccurrences)
      ..where((t) => t.trackAId.equals(trackAId) & t.trackBId.equals(trackBId));
    final existing = await query.getSingleOrNull();
    if (existing == null) {
      await db
          .into(db.trackCoOccurrences)
          .insert(
            TrackCoOccurrencesCompanion.insert(
              trackAId: trackAId,
              trackBId: trackBId,
              count: const Value(1),
            ),
          );
    } else {
      await (db.update(db.trackCoOccurrences)..where(
            (t) => t.trackAId.equals(trackAId) & t.trackBId.equals(trackBId),
          ))
          .write(TrackCoOccurrencesCompanion(count: Value(existing.count + 1)));
    }
  }

  Future<int> getCount(String trackAId, String trackBId) async {
    final query = db.select(db.trackCoOccurrences)
      ..where((t) => t.trackAId.equals(trackAId) & t.trackBId.equals(trackBId));
    final row = await query.getSingleOrNull();
    return row?.count ?? 0;
  }

  Future<int> getMaxCount(String trackAId) async {
    final query = db.customSelect(
      'SELECT MAX(count) AS max_count FROM track_co_occurrences WHERE track_a_id = ?1',
      variables: [Variable<String>(trackAId)],
      readsFrom: {db.trackCoOccurrences},
    );
    final row = await query.getSingleOrNull();
    return row?.read<int>('max_count') ?? 0;
  }

  Future<List<String>> getTopCoOccurred(
    String trackAId, {
    int limit = 15,
  }) async {
    final query = db.customSelect(
      'SELECT track_b_id FROM track_co_occurrences WHERE track_a_id = ?1 ORDER BY count DESC LIMIT ?2',
      variables: [Variable<String>(trackAId), Variable<int>(limit)],
      readsFrom: {db.trackCoOccurrences},
    );
    final rows = await query.get();
    return rows.map((r) => r.read<String>('track_b_id')).toList();
  }

  Future<void> prune({int keep = 10000}) async {
    await db.customStatement(
      'DELETE FROM track_co_occurrences WHERE rowid NOT IN (SELECT rowid FROM track_co_occurrences ORDER BY count DESC LIMIT ?1)',
      [keep],
    );
  }
}
