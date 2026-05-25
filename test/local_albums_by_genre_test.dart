// Regression test for the local-mode "Genres" detail screen.
//
// Bug: `LocalBackend.albumsByGenre(genre)` ignored its `genre`
// argument and returned every album in the library (capped at
// `limit`). The new SQL-backed `LocalDb.albumsByGenre` actually
// filters by `tracks.genre` and groups by the same key as
// `LocalDb.allAlbums`, so:
//   - Picking a genre returns only its albums.
//   - Tag-mismatched albums (compilation albums with `album_artist`
//     set) keep their proper artistName / id.
//   - An unknown genre returns an empty list.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aetherfin/core/local/app_database.dart';
import 'package:aetherfin/core/local/local_db.dart';

void main() {
  group('LocalDb.albumsByGenre', () {
    late LocalDb db;

    setUp(() async {
      db = LocalDb(database: AppDatabase.forTesting(NativeDatabase.memory()));
      await db.upsertTracks(_fixture);
    });

    tearDown(() => db.close());

    test('returns only albums whose tracks tag the requested genre', () async {
      final pop = await db.albumsByGenre('Pop');
      expect(pop.map((a) => a.name), unorderedEquals(['Coastlines']));

      final rock = await db.albumsByGenre('Rock');
      expect(rock.map((a) => a.name), unorderedEquals(['Heavyset']));
    });

    test('an unknown genre returns an empty list', () async {
      final res = await db.albumsByGenre('Jazz');
      expect(res, isEmpty);
    });

    test('compilation albums keep album_artist as their artistName so the '
        'id matches LocalDb.allAlbums', () async {
      final pop = await db.albumsByGenre('Pop');
      expect(pop, hasLength(1));
      // album_artist on the seed is "Various", track artist is "Una".
      // allAlbums groups by album_artist when non-empty, so we must too.
      expect(pop.single.artistName, 'Various');
      expect(pop.single.id, 'local:album:Coastlines:Various');
    });

    test('aggregates track count and total duration per album', () async {
      final rock = (await db.albumsByGenre('Rock')).single;
      // Heavyset has two tracks of 200_000 + 250_000 ms in the fixture.
      expect(rock.trackCount, 2);
      expect(rock.totalDuration, const Duration(milliseconds: 450000));
    });

    test('respects the limit parameter', () async {
      final res = await db.albumsByGenre('Pop', limit: 0);
      expect(res, isEmpty);
    });
  });
}

/// Two albums spanning two genres, plus a compilation row so we cover
/// the album-artist fallback that bit the buggy implementation.
final _fixture = <Map<String, dynamic>>[
  {
    'id': 'content://uri/1',
    'title': 'Sunset Drive',
    'artist': 'Una',
    'album': 'Coastlines',
    'album_artist': 'Various',
    'duration_ms': 180000,
    'genre': 'Pop',
    'file_path': '/storage/coastlines/1.mp3',
    'codec': 'mp3',
  },
  {
    'id': 'content://uri/2',
    'title': 'Pier Lights',
    'artist': 'Dos',
    'album': 'Coastlines',
    'album_artist': 'Various',
    'duration_ms': 200000,
    'genre': 'Pop',
    'file_path': '/storage/coastlines/2.mp3',
    'codec': 'mp3',
  },
  {
    'id': 'content://uri/3',
    'title': 'Anvil',
    'artist': 'Heavyset',
    'album': 'Heavyset',
    'album_artist': '',
    'duration_ms': 200000,
    'genre': 'Rock',
    'file_path': '/storage/heavyset/1.mp3',
    'codec': 'flac',
  },
  {
    'id': 'content://uri/4',
    'title': 'Forge',
    'artist': 'Heavyset',
    'album': 'Heavyset',
    'album_artist': '',
    'duration_ms': 250000,
    'genre': 'Rock',
    'file_path': '/storage/heavyset/2.mp3',
    'codec': 'flac',
  },
];
