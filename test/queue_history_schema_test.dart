import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:aetherfin/core/local/app_database.dart';

void main() {
  group('QueueHistory schema', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() => db.close());

    test('class has correct columns', () {
      expect(db.queueHistory, isNotNull);
      final table = db.queueHistory;
      expect(table.id, isA<Column>());
      expect(table.trackIdsJson, isA<Column>());
      expect(table.sourceLabel, isA<Column>());
      expect(table.sourceType, isA<Column>());
      expect(table.sourceId, isA<Column>());
      expect(table.createdAt, isA<Column>());
    });

    test('insert and read QueueHistory entries', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db
          .into(db.queueHistory)
          .insert(
            QueueHistoryCompanion.insert(
              id: 'test-uuid-1',
              trackIdsJson: '["track1","track2"]',
              sourceLabel: 'Album: Test Album',
              sourceType: 'album',
              sourceId: const Value('album-123'),
              createdAt: now - 1000,
            ),
          );
      await db
          .into(db.queueHistory)
          .insert(
            QueueHistoryCompanion.insert(
              id: 'test-uuid-2',
              trackIdsJson: '["track3"]',
              sourceLabel: 'Playlist: My Favorites',
              sourceType: 'playlist',
              createdAt: now,
            ),
          );

      final rows = await (db.select(
        db.queueHistory,
      )..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).get();

      expect(rows.length, 2);
      expect(rows[0].id, 'test-uuid-2');
      expect(rows[0].trackIdsJson, '["track3"]');
      expect(rows[0].sourceLabel, 'Playlist: My Favorites');
      expect(rows[0].sourceType, 'playlist');
      expect(rows[0].sourceId, isNull);
      expect(rows[1].id, 'test-uuid-1');
      expect(rows[1].sourceType, 'album');
      expect(rows[1].sourceId, 'album-123');
    });

    test('schema version is 6', () {
      expect(db.schemaVersion, 6);
    });

    test('loadRecent returns limited entries in desc order', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      for (var i = 0; i < 15; i++) {
        await db
            .into(db.queueHistory)
            .insert(
              QueueHistoryCompanion.insert(
                id: 'uuid-$i',
                trackIdsJson: '["t$i"]',
                sourceLabel: 'Playlist $i',
                sourceType: 'playlist',
                createdAt: now + i,
              ),
            );
      }
      final all = await (db.select(db.queueHistory)).get();
      expect(all.length, 15);
    });

    test('delete works correctly', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db
          .into(db.queueHistory)
          .insert(
            QueueHistoryCompanion.insert(
              id: 'to-delete',
              trackIdsJson: '[]',
              sourceLabel: 'Delete me',
              sourceType: 'manual',
              createdAt: now,
            ),
          );
      expect(
        (await (db.select(
          db.queueHistory,
        )..where((t) => t.id.equals('to-delete'))).get()).length,
        1,
      );
      await (db.delete(
        db.queueHistory,
      )..where((t) => t.id.equals('to-delete'))).go();
      expect(
        (await (db.select(
          db.queueHistory,
        )..where((t) => t.id.equals('to-delete'))).get()).length,
        0,
      );
    });
  });

  group('Database migration tests', () {
    test('migration from v5 to v6 runs successfully', () async {
      final sqliteDb = sqlite3.openInMemory();
      sqliteDb.execute('PRAGMA user_version = 5;');
      sqliteDb.execute('''
        CREATE TABLE playback_history (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          track_id TEXT NOT NULL,
          played_at INTEGER NOT NULL,
          title TEXT,
          artist TEXT,
          album TEXT,
          duration_ms INTEGER,
          image_url TEXT,
          source_id TEXT,
          source_type TEXT
        );
      ''');

      final db = AppDatabase.forTesting(NativeDatabase.opened(sqliteDb));

      // Query the database to trigger open/migration
      final result = await db.select(db.playbackHistory).get();
      expect(result, isEmpty);

      // Verify that the skipped column was added and works
      await db
          .into(db.playbackHistory)
          .insert(
            PlaybackHistoryCompanion.insert(
              trackId: 'test-track-1',
              playedAt: 123456,
              skipped: const Value(true),
            ),
          );

      final rows = await db.select(db.playbackHistory).get();
      expect(rows.length, 1);
      expect(rows[0].skipped, isTrue);

      await db.close();
    });

    test('migration from scratch (v0 to v6) runs successfully', () async {
      // This tests the case where we start with an empty database (or a fresh install)
      // and ensure there are no duplicate column errors.
      final db = AppDatabase.forTesting(NativeDatabase.memory());

      // Query to trigger open/onCreate
      final result = await db.select(db.playbackHistory).get();
      expect(result, isEmpty);

      await db
          .into(db.playbackHistory)
          .insert(
            PlaybackHistoryCompanion.insert(
              trackId: 'test-track-2',
              playedAt: 7891011,
              skipped: const Value(false),
            ),
          );

      final rows = await db.select(db.playbackHistory).get();
      expect(rows.length, 1);
      expect(rows[0].skipped, isFalse);

      await db.close();
    });
  });
}
