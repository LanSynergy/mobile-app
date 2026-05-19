// Regression test for LocalDb.artistByName.
//
// Replaces the `library.artists() + linear search` pattern in
// LocalBackend.artist(id), which ran a full GROUP BY of every artist
// in the library to find one row.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aetherfin/core/local/app_database.dart';
import 'package:aetherfin/core/local/local_db.dart';

void main() {
  group('LocalDb.artistByName', () {
    late LocalDb db;

    setUp(() async {
      db = LocalDb(
        database: AppDatabase.forTesting(NativeDatabase.memory()),
      );
      await db.upsertTracks([
        // Una has 2 distinct albums.
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
        },
        // Different artist.
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
        },
      ]);
    });

    tearDown(() => db.close());

    test('returns the matching artist with album count', () async {
      final a = await db.artistByName('Una');
      expect(a, isNotNull);
      expect(a!.name, 'Una');
      expect(a.id, 'local:artist:Una');
      expect(a.albumCount, 2);
      expect(a.imageUrl, 'file:///c/coast.jpg');
    });

    test('returns null for an unknown artist', () async {
      final a = await db.artistByName('Nope');
      expect(a, isNull);
    });

    test('id stable with allArtists', () async {
      final all = await db.allArtists();
      final hit = await db.artistByName('Una');
      final allUna = all.firstWhere((a) => a.name == 'Una');
      expect(hit!.id, allUna.id);
    });
  });
}
