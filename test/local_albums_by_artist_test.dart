// Regression test for LocalDb.albumsByArtist.
//
// Replaces the `library.albums().where(...artistName==...)` pattern in
// LocalBackend.artistAlbums(id): a full GROUP BY scan of every album
// in the library to find one artist's albums.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aetherfin/core/local/app_database.dart';
import 'package:aetherfin/core/local/local_db.dart';

void main() {
  group('LocalDb.albumsByArtist', () {
    late LocalDb db;

    setUp(() async {
      db = LocalDb(
        database: AppDatabase.forTesting(NativeDatabase.memory()),
      );
      await db.upsertTracks([
        // "Una" → albums "Coastlines" (2020) and "Sands" (2018).
        {
          'id': 'content://uri/c1',
          'title': 'Tide',
          'artist': 'Una',
          'album': 'Coastlines',
          'album_artist': 'Una',
          'duration_ms': 180000,
          'genre': 'Pop',
          'file_path': '/a/1.mp3',
          'codec': 'mp3',
          'cover_path': '/c/coast.jpg',
          'year': 2020,
        },
        {
          'id': 'content://uri/c2',
          'title': 'Cliff',
          'artist': 'Una',
          'album': 'Coastlines',
          'album_artist': 'Una',
          'duration_ms': 200000,
          'genre': 'Pop',
          'file_path': '/a/2.mp3',
          'codec': 'mp3',
          'cover_path': '/c/coast.jpg',
          'year': 2020,
        },
        {
          'id': 'content://uri/s1',
          'title': 'Dune',
          'artist': 'Una',
          'album': 'Sands',
          'album_artist': 'Una',
          'duration_ms': 240000,
          'genre': 'Folk',
          'file_path': '/a/3.mp3',
          'codec': 'mp3',
          'year': 2018,
        },
        // Different artist — should NOT appear.
        {
          'id': 'content://uri/m1',
          'title': 'Peak',
          'artist': 'Dos',
          'album': 'Mountains',
          'album_artist': 'Dos',
          'duration_ms': 240000,
          'genre': 'Rock',
          'file_path': '/a/4.mp3',
          'codec': 'mp3',
          'year': 2022,
        },
        // album_artist empty → falls back to track artist for the key.
        {
          'id': 'content://uri/v1',
          'title': 'A',
          'artist': 'Tres',
          'album': 'Compilation',
          'album_artist': '',
          'duration_ms': 100000,
          'genre': 'Mix',
          'file_path': '/a/5.mp3',
          'codec': 'mp3',
          'year': 2019,
        },
      ]);
    });

    tearDown(() => db.close());

    test('returns only albums by the requested artist', () async {
      final r = await db.albumsByArtist('Una');
      expect(r.map((a) => a.name), ['Sands', 'Coastlines']);
      // Years carried through.
      expect(r.first.year, 2018);
      expect(r.last.year, 2020);
    });

    test('honors the album_artist → artist fallback', () async {
      // The compilation row has album_artist='', so the album-artist
      // key falls back to the track artist 'Tres'.
      final r = await db.albumsByArtist('Tres');
      expect(r.map((a) => a.name), ['Compilation']);
    });

    test('returns empty for an unknown artist', () async {
      final r = await db.albumsByArtist('Nope');
      expect(r, isEmpty);
    });

    test('ids stable with allAlbums', () async {
      final all = await db.allAlbums();
      final hit = await db.albumsByArtist('Una');
      final allCoast = all.firstWhere((a) => a.name == 'Coastlines');
      final hitCoast = hit.firstWhere((a) => a.name == 'Coastlines');
      expect(hitCoast.id, allCoast.id);
    });

    test('limit caps the result', () async {
      final r = await db.albumsByArtist('Una', limit: 1);
      expect(r, hasLength(1));
    });
  });
}
