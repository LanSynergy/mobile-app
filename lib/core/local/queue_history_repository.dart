import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:uuid/uuid.dart';

import 'app_database.dart';
import '../../utils/log.dart';

/// Structured queue history entry returned by the repository.
class QueueHistoryItem {
  const QueueHistoryItem({
    required this.id,
    required this.trackIds,
    required this.sourceLabel,
    required this.sourceType,
    this.sourceId,
    required this.createdAt,
  });

  final String id;
  final List<String> trackIds;
  final String sourceLabel;
  final String sourceType;
  final String? sourceId;
  final int createdAt; // epoch ms
}

/// Repository for queue history persistence.
///
/// Stores lightweight snapshots (track IDs + source metadata) so users
/// can restore previous play sessions. Deduplication prevents saving
/// the same source back-to-back — only new queue sources create entries.
class QueueHistoryRepository {
  QueueHistoryRepository(this._db);
  final AppDatabase _db;
  static const _uuid = Uuid();

  /// Save a new queue history entry with deduplication.
  ///
  /// If the most recent entry has the same [sourceType] + [sourceId]
  /// combination (and sourceId is non-null), the save is skipped to
  /// avoid cluttering history with repeated plays of the same source.
  Future<void> save({
    required List<String> trackIds,
    required String sourceLabel,
    required String sourceType,
    String? sourceId,
  }) async {
    // Deduplication: check the most recent entry with same sourceType+sourceId
    if (sourceId != null) {
      final latest =
          await (_db.select(_db.queueHistory)
                ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
                ..limit(1))
              .getSingleOrNull();
      if (latest != null &&
          latest.sourceType == sourceType &&
          latest.sourceId == sourceId) {
        afLog(
          'data',
          'queueHistory dedup skipped type=$sourceType id=$sourceId',
        );
        return;
      }
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    await _db
        .into(_db.queueHistory)
        .insert(
          QueueHistoryCompanion.insert(
            id: _uuid.v4(),
            trackIdsJson: jsonEncode(trackIds),
            sourceLabel: sourceLabel,
            sourceType: sourceType,
            sourceId: Value<String?>(sourceId),
            createdAt: now,
          ),
        );
    afLog(
      'data',
      'queueHistory saved type=$sourceType label=$sourceLabel tracks=${trackIds.length}',
    );

    // Enforce a maximum of 50 entries — delete oldest beyond that
    await deleteOldest(keep: 50);
  }

  /// Load the most recent N history entries.
  Future<List<QueueHistoryItem>> loadRecent({int limit = 10}) async {
    final rows =
        await (_db.select(_db.queueHistory)
              ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
              ..limit(limit))
            .get();
    return rows.map(_rowToItem).toList();
  }

  /// Delete a single entry by ID.
  Future<void> deleteEntry(String id) async {
    await (_db.delete(_db.queueHistory)..where((t) => t.id.equals(id))).go();
  }

  /// Delete all entries except the latest [keep] ones.
  Future<void> deleteOldest({int keep = 50}) async {
    // Use raw SQL to avoid loading all rows into memory.
    await _db.customStatement(
      'DELETE FROM queue_history WHERE id NOT IN '
      '(SELECT id FROM queue_history ORDER BY created_at DESC LIMIT ?)',
      [keep],
    );
  }

  QueueHistoryItem _rowToItem(QueueHistoryEntity row) {
    final ids = switch (jsonDecode(row.trackIdsJson)) {
      final List<dynamic> list => list.cast<String>(),
      _ => <String>[],
    };
    return QueueHistoryItem(
      id: row.id,
      trackIds: ids,
      sourceLabel: row.sourceLabel,
      sourceType: row.sourceType,
      sourceId: row.sourceId,
      createdAt: row.createdAt,
    );
  }
}
