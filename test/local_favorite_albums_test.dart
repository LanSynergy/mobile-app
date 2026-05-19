// Regression test for LocalDb.favoriteAlbums.
//
// Replaces the `library.albums() + favIds.contains(a.id)` pattern in
// LocalBackend.favoriteAlbums(limit): a full GROUP BY of every album
// in the library to keep the small set the user has favorited.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aetherfin/core/local/app_database.dart';
import 'package:aetherfin/core/local/local_db.dart';

void main() {
  group('LocalDb.favoriteAlbums', () {
    late LocalDb db;

    setUp(() async {
      db = LocalDb(
        database: AppDatabase.forTesting(NativeDatabase.memory()),
      );
      await db.upsertTracks([
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
          'id': 'content://uri/m1',
          'title': 'Peak',
          'artist': 'Dos',
          'album': 'Mountains',
          'album_artist': 'Dos',
          'duration_ms': 240000,
          'genre': 'Rock',
          'file_path': '/a/3.mp3',
          'codec': 'mp3',
          'year': 2022,
        },
        {
          'id': 'content://uri/v1',
          'title': 'A',
          'artist': 'Tres',
          'album': 'Compilation',
          'album_artist': '',
          'duration_ms': 100000,
          'genre': 'Mix',
          'file_path': '/a/4.mp3',
          'codec': 'mp3',
          'year': 2019,
        },
      ]);
    });

    tearDown(() => db.close());

    test('empty when no favorites are set', () async {
      final r = await db.favoriteAlbums();
      expect(r, isEmpty);
    });

    test('returns only the favorited albums', () async {
      await db.setFavorite('local:album:Coastlines:Una', true);
      // Set a non-album favorite too — must not pollute the result.
      await db.setFavorite('content://uri/m1', true);
      final r = await db.favoriteAlbums();
      expect(r.map((a) => a.name), ['Coastlines']);
      expect(r.first.isFavorite, isTrue);
      expect(r.first.trackCount, 2);
      expect(r.first.totalDuration, const Duration(milliseconds: 380000));
    });

    test('honors compilation album-artist fallback (album_artist empty)',
        () async {
      // The Compilation album_artist is empty → its synthetic id is
      // local:album:Compilation:Tres. The SQL must reconstruct that
      // via COALESCE(NULLIF(album_artist,''), artist).
      await db.setFavorite('local:album:Compilation:Tres', true);
      final r = await db.favoriteAlbums();
      expect(r.map((a) => a.name), ['Compilation']);
      expect(r.first.id, 'local:album:Compilation:Tres');
    });

    test('id stable with allAlbums', () async {
      await db.setFavorite('local:album:Coastlines:Una', true);
      final all = await db.allAlbums();
      final fav = await db.favoriteAlbums();
      final allCoast = all.firstWhere((a) => a.name == 'Coastlines');
      expect(fav.first.id, allCoast.id);
    });

    test('limit caps the result', () async {
      await db.setFavorite('local:album:Coastlines:Una', true);
      await db.setFavorite('local:album:Mountains:Dos', true);
      final r = await db.favoriteAlbums(limit: 1);
      expect(r, hasLength(1));
    });
  });
}
