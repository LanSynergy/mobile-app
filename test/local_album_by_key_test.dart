// Regression test for LocalDb.albumByKey.
//
// Replaces the `library.albums().firstWhere(...)` pattern used by
// LocalBackend.album(id): a full GROUP BY of every album in the
// library to find one row.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aetherfin/core/local/app_database.dart';
import 'package:aetherfin/core/local/local_db.dart';

void main() {
  group('LocalDb.albumByKey', () {
    late LocalDb db;

    setUp(() async {
      db = LocalDb(database: AppDatabase.forTesting(NativeDatabase.memory()));
      await db.upsertTracks([
        // "Coastlines" by "Una" — 2 tracks, year 2020, has cover.
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
        // Compilation album: album_artist empty → falls back to track artist.
        {
          'id': 'content://uri/v1',
          'title': 'Track A',
          'artist': 'Artist1',
          'album': 'Various Hits',
          'album_artist': '',
          'duration_ms': 150000,
          'genre': 'Pop',
          'file_path': '/a/3.mp3',
          'codec': 'mp3',
        },
        {
          'id': 'content://uri/v2',
          'title': 'Track B',
          'artist': 'Artist1',
          'album': 'Various Hits',
          'album_artist': '',
          'duration_ms': 160000,
          'genre': 'Pop',
          'file_path': '/a/4.mp3',
          'codec': 'mp3',
        },
      ]);
    });

    tearDown(() => db.close());

    test('returns one album with full aggregation', () async {
      final a = await db.albumByKey('Coastlines', 'Una');
      expect(a, isNotNull);
      expect(a!.name, 'Coastlines');
      expect(a.artistName, 'Una');
      expect(a.trackCount, 2);
      expect(a.totalDuration, const Duration(milliseconds: 380000));
      expect(a.year, 2020);
      expect(a.imageUrl, 'file:///c/coast.jpg');
    });

    test('returns null for unknown album/artist combo', () async {
      final a = await db.albumByKey('Nope', 'Una');
      expect(a, isNull);
      final b = await db.albumByKey('Coastlines', 'WrongArtist');
      expect(b, isNull);
    });

    test('id stable with allAlbums (named album_artist)', () async {
      final all = await db.allAlbums();
      final hit = await db.albumByKey('Coastlines', 'Una');
      final allCoast = all.firstWhere((a) => a.name == 'Coastlines');
      expect(hit!.id, allCoast.id);
    });

    test('id stable with allAlbums (empty album_artist fallback)', () async {
      // The album_artist column is empty, so the key falls back to
      // the track artist. allAlbums encodes this as
      // local:album:Various Hits:Artist1 — albumByKey must agree.
      final all = await db.allAlbums();
      final hit = await db.albumByKey('Various Hits', 'Artist1');
      final allVarious = all.firstWhere((a) => a.name == 'Various Hits');
      expect(hit, isNotNull);
      expect(hit!.id, allVarious.id);
      expect(hit.id, 'local:album:Various Hits:Artist1');
      expect(hit.trackCount, 2);
    });

    test(
      'album name containing colon parses correctly via lastIndexOf',
      () async {
        // Regression: album IDs use `local:album:NAME:ARTIST` with `:` as
        // delimiter. If the album name itself contains a colon (e.g.
        // "Greatest Hits: The Best"), splitting on the FIRST colon would
        // corrupt both name and artist. Parsing must use lastIndexOf(':').
        await db.upsertTracks([
          {
            'id': 'content://uri/colon1',
            'title': 'Song One',
            'artist': 'The Band',
            'album': 'Greatest Hits: The Best',
            'album_artist': 'The Band',
            'duration_ms': 200000,
            'genre': 'Rock',
            'file_path': '/a/colon1.mp3',
            'codec': 'mp3',
          },
        ]);

        final hit = await db.albumByKey('Greatest Hits: The Best', 'The Band');
        expect(hit, isNotNull);
        expect(hit!.name, 'Greatest Hits: The Best');
        expect(hit.artistName, 'The Band');
        expect(hit.id, 'local:album:Greatest Hits: The Best:The Band');
      },
    );
  });
}
