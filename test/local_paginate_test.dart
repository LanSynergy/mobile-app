// Regression test for LocalDb.allAlbums + allTracks pagination.
//
// LocalBackend.allAlbums and allTracks used to fetch the entire
// library and slice in Dart for every page. SQL LIMIT/OFFSET keeps
// the per-page cost flat instead of growing with the scroll position.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aetherfin/core/local/app_database.dart';
import 'package:aetherfin/core/local/local_db.dart';

void main() {
  group('LocalDb pagination', () {
    late LocalDb db;

    setUp(() async {
      db = LocalDb(
        database: AppDatabase.forTesting(NativeDatabase.memory()),
      );
      // 5 albums (each 2 tracks) — easy to reason about pages of 2.
      final tracks = <Map<String, dynamic>>[];
      // Track titles sort alphabetically as: T01 .. T10.
      for (var i = 0; i < 5; i++) {
        final albumIdx = (i + 1).toString().padLeft(2, '0');
        // album names: Album01..05 sort alphabetically.
        for (var j = 0; j < 2; j++) {
          tracks.add({
            'id': 'content://uri/$albumIdx-$j',
            'title': 'T${(i * 2 + j + 1).toString().padLeft(2, '0')}',
            'artist': 'Artist',
            'album': 'Album$albumIdx',
            'album_artist': 'Artist',
            'duration_ms': 100000,
            'genre': 'Pop',
            'file_path': '/a/$albumIdx-$j.mp3',
            'codec': 'mp3',
          });
        }
      }
      await db.upsertTracks(tracks);
    });

    tearDown(() => db.close());

    test('allAlbums supports limit+offset', () async {
      final page1 = await db.allAlbums(limit: 2, offset: 0);
      expect(page1.map((a) => a.name), ['Album01', 'Album02']);

      final page2 = await db.allAlbums(limit: 2, offset: 2);
      expect(page2.map((a) => a.name), ['Album03', 'Album04']);

      final page3 = await db.allAlbums(limit: 2, offset: 4);
      expect(page3.map((a) => a.name), ['Album05']);

      final past = await db.allAlbums(limit: 2, offset: 10);
      expect(past, isEmpty);
    });

    test('allAlbums with no limit returns every album', () async {
      final all = await db.allAlbums();
      expect(all, hasLength(5));
    });

    test('allTracks supports limit+offset', () async {
      final page1 = await db.allTracks(limit: 3, offset: 0);
      expect(page1.map((t) => t.title), ['T01', 'T02', 'T03']);

      final page2 = await db.allTracks(limit: 3, offset: 3);
      expect(page2.map((t) => t.title), ['T04', 'T05', 'T06']);

      final past = await db.allTracks(limit: 3, offset: 100);
      expect(past, isEmpty);
    });
  });
}
