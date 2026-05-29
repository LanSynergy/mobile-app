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

    test('schema version is 9', () {
      expect(db.schemaVersion, 9);
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
    test('migration from v8 to v9 runs successfully', () async {
      final sqliteDb = sqlite3.openInMemory();
      sqliteDb.execute('PRAGMA user_version = 8;');
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
          source_type TEXT,
          skipped INTEGER NOT NULL DEFAULT 0,
          completion_rate REAL NOT NULL DEFAULT 0.0
        );
      ''');
      sqliteDb.execute('''
        CREATE TABLE track_stats (
          track_id TEXT NOT NULL PRIMARY KEY,
          play_count INTEGER NOT NULL DEFAULT 0,
          skip_count INTEGER NOT NULL DEFAULT 0,
          avg_completion REAL NOT NULL DEFAULT 0.0,
          last_played INTEGER
        );
      ''');
      sqliteDb.execute('''
        CREATE TABLE track_co_occurrences (
          track_a_id TEXT NOT NULL,
          track_b_id TEXT NOT NULL,
          count INTEGER NOT NULL DEFAULT 0,
          PRIMARY KEY (track_a_id, track_b_id)
        );
      ''');
      sqliteDb.execute('''
        CREATE TABLE tracks (id TEXT PRIMARY KEY, title TEXT NOT NULL, artist TEXT DEFAULT "", album TEXT DEFAULT "", album_artist TEXT DEFAULT "", track_number INTEGER, duration_ms INTEGER DEFAULT 0, year INTEGER, genre TEXT DEFAULT "", file_path TEXT NOT NULL, file_size INTEGER, last_modified INTEGER, cover_path TEXT, codec TEXT DEFAULT "", bitrate INTEGER, sample_rate INTEGER)
      ''');
      sqliteDb.execute('''
        CREATE TABLE folders (uri TEXT PRIMARY KEY, display_path TEXT NOT NULL, added_at INTEGER NOT NULL)
      ''');

      final db = AppDatabase.forTesting(NativeDatabase.opened(sqliteDb));

      // Verify lastfm_similar_cache table was added
      await db
          .into(db.lastfmSimilarCache)
          .insert(
            LastfmSimilarCacheCompanion.insert(
              trackId: 'test-track',
              similarTrackIds: '["track-a","track-b"]',
              cachedAt: DateTime.now().millisecondsSinceEpoch,
            ),
          );
      final rows = await db.select(db.lastfmSimilarCache).get();
      expect(rows.length, 1);
      expect(rows[0].trackId, 'test-track');

      await db.close();
    });

    test('migration from v6 to v9 runs successfully', () async {
      final sqliteDb = sqlite3.openInMemory();
      sqliteDb.execute('PRAGMA user_version = 6;');
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
          source_type TEXT,
          skipped INTEGER NOT NULL DEFAULT 0
        );
      ''');
      // Create all other tables that existed at v6
      sqliteDb.execute(
        'CREATE TABLE tracks (id TEXT PRIMARY KEY, title TEXT NOT NULL, artist TEXT DEFAULT "", album TEXT DEFAULT "", album_artist TEXT DEFAULT "", track_number INTEGER, duration_ms INTEGER DEFAULT 0, year INTEGER, genre TEXT DEFAULT "", file_path TEXT NOT NULL, file_size INTEGER, last_modified INTEGER, cover_path TEXT, codec TEXT DEFAULT "", bitrate INTEGER, sample_rate INTEGER)',
      );
      sqliteDb.execute(
        'CREATE TABLE folders (uri TEXT PRIMARY KEY, display_path TEXT NOT NULL, added_at INTEGER NOT NULL)',
      );

      final db = AppDatabase.forTesting(NativeDatabase.opened(sqliteDb));

      // Verify completionRate column was added
      await db
          .into(db.playbackHistory)
          .insert(
            PlaybackHistoryCompanion.insert(
              trackId: 'test-track-1',
              playedAt: 123456,
              skipped: const Value(true),
              completionRate: const Value(0.85),
            ),
          );
      final rows = await db.select(db.playbackHistory).get();
      expect(rows.length, 1);
      expect(rows[0].completionRate, 0.85);

      // Verify new tables exist
      await db
          .into(db.trackStats)
          .insert(TrackStatsCompanion.insert(trackId: 'stats-1'));
      final statsRows = await db.select(db.trackStats).get();
      expect(statsRows.length, 1);

      await db
          .into(db.trackCoOccurrences)
          .insert(
            TrackCoOccurrencesCompanion.insert(
              trackAId: 'track-a',
              trackBId: 'track-b',
            ),
          );
      final coRows = await db.select(db.trackCoOccurrences).get();
      expect(coRows.length, 1);

      await db.close();
    });

    test('migration from scratch (v0 to v9) runs successfully', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());

      // Verify playback_history with completionRate works
      await db
          .into(db.playbackHistory)
          .insert(
            PlaybackHistoryCompanion.insert(
              trackId: 'test-track-2',
              playedAt: 7891011,
              skipped: const Value(false),
              completionRate: const Value(0.92),
            ),
          );
      var rows = await db.select(db.playbackHistory).get();
      expect(rows.length, 1);
      expect(rows[0].completionRate, 0.92);

      // Verify track_stats works
      await db
          .into(db.trackStats)
          .insert(
            TrackStatsCompanion.insert(
              trackId: 'local:track:test',
              playCount: const Value(5),
            ),
          );
      var statsRows = await db.select(db.trackStats).get();
      expect(statsRows.length, 1);
      expect(statsRows[0].playCount, 5);

      // Verify track_co_occurrences works
      await db
          .into(db.trackCoOccurrences)
          .insert(
            TrackCoOccurrencesCompanion.insert(
              trackAId: 'alice',
              trackBId: 'bob',
              count: const Value(3),
            ),
          );
      var coRows = await db.select(db.trackCoOccurrences).get();
      expect(coRows.length, 1);
      expect(coRows[0].count, 3);

      await db.close();
    });
  });
}
