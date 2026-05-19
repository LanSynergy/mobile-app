// Regression test for LocalDb.trackById.
//
// Replaces the `library.tracks(limit: 5000).firstWhere(...)` pattern
// LocalBackend.instantMix used to do. Single-row PK lookup now.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aetherfin/core/local/app_database.dart';
import 'package:aetherfin/core/local/local_db.dart';

void main() {
  group('LocalDb.trackById', () {
    late LocalDb db;

    setUp(() async {
      db = LocalDb(
        database: AppDatabase.forTesting(NativeDatabase.memory()),
      );
      await db.upsertTracks([
        {
          'id': 'content://uri/seed',
          'title': 'Seed',
          'artist': 'Una',
          'album': 'Coastlines',
          'album_artist': '',
          'duration_ms': 180000,
          'genre': 'Pop',
          'file_path': '/storage/coastlines/1.mp3',
          'codec': 'mp3',
        },
        {
          'id': 'content://uri/other',
          'title': 'Other',
          'artist': 'Dos',
          'album': 'Coastlines',
          'album_artist': '',
          'duration_ms': 200000,
          'genre': 'Pop',
          'file_path': '/storage/coastlines/2.mp3',
          'codec': 'mp3',
        },
      ]);
    });

    tearDown(() => db.close());

    test('returns the matching track', () async {
      final t = await db.trackById('content://uri/seed');
      expect(t, isNotNull);
      expect(t!.id, 'content://uri/seed');
      expect(t.title, 'Seed');
      expect(t.artistName, 'Una');
    });

    test('returns null for an unknown id', () async {
      final t = await db.trackById('content://uri/missing');
      expect(t, isNull);
    });

    test('returns null on an empty library', () async {
      await db.deleteAllTracks();
      final t = await db.trackById('content://uri/seed');
      expect(t, isNull);
    });
  });
}
