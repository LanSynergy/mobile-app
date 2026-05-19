// Regression test for the local-mode Home hero card.
//
// Bug: `LocalBackend.recentlyAddedAlbums` returned `library.albums()
// .take(limit)`, which is alphabetical (allAlbums orders by
// `album COLLATE NOCASE ASC`). The Home screen's hero "Listen" card
// shows `albums.first`, so users always saw the alphabetically-first
// album, never their newly-imported music.
//
// The fix orders albums by `MAX(last_modified) DESC` per album group
// — file mtime is the best signal without a schema bump.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aetherfin/core/local/app_database.dart';
import 'package:aetherfin/core/local/local_db.dart';

void main() {
  group('LocalDb.recentlyAddedAlbums', () {
    late LocalDb db;

    setUp(() async {
      db = LocalDb(
        database: AppDatabase.forTesting(NativeDatabase.memory()),
      );
      await db.upsertTracks(_fixture);
    });

    tearDown(() => db.close());

    test('orders by MAX(last_modified) descending', () async {
      final albums = await db.recentlyAddedAlbums();
      // Newest first: Zenith (mtime 3000), Coastlines (2000), Anvil (1000).
      expect(
        albums.map((a) => a.name).toList(),
        equals(['Zenith', 'Coastlines', 'Anvil']),
      );
    });

    test('limit caps the result count', () async {
      final albums = await db.recentlyAddedAlbums(limit: 2);
      expect(albums, hasLength(2));
      expect(albums.first.name, 'Zenith');
    });

    test(
        'tracks with NULL last_modified land at the bottom but stay '
        'name-stable so identical mtimes have deterministic order',
        () async {
      await db.upsertTracks([
        {
          'id': 'content://uri/9',
          'title': 'Aaa',
          'artist': 'Mystery',
          'album': 'Mystery',
          'album_artist': '',
          'duration_ms': 100000,
          'genre': '',
          'file_path': '/storage/mystery/1.mp3',
          'codec': 'mp3',
          // last_modified omitted → null
        },
      ]);
      final albums = await db.recentlyAddedAlbums();
      // Mystery has max(last_modified) = NULL → COALESCE → 0 → last.
      expect(albums.last.name, 'Mystery');
    });

    test('aggregation key matches LocalDb.allAlbums (id stability)', () async {
      final byRecent = await db.recentlyAddedAlbums();
      final byAll = await db.allAlbums();
      // Every recently-added album id should also appear in allAlbums.
      // Otherwise navigating from Home → album detail would 404.
      final allIds = byAll.map((a) => a.id).toSet();
      for (final a in byRecent) {
        expect(allIds, contains(a.id),
            reason: 'id mismatch between aggregations: ${a.id}');
      }
    });
  });
}

final _fixture = <Map<String, dynamic>>[
  {
    'id': 'content://uri/1',
    'title': 'Anvil',
    'artist': 'Heavyset',
    'album': 'Anvil',
    'album_artist': '',
    'duration_ms': 200000,
    'genre': 'Rock',
    'file_path': '/storage/anvil/1.flac',
    'codec': 'flac',
    'last_modified': 1000,
  },
  {
    'id': 'content://uri/2',
    'title': 'Sunset Drive',
    'artist': 'Una',
    'album': 'Coastlines',
    'album_artist': 'Various',
    'duration_ms': 180000,
    'genre': 'Pop',
    'file_path': '/storage/coastlines/1.mp3',
    'codec': 'mp3',
    'last_modified': 2000,
  },
  {
    'id': 'content://uri/3',
    'title': 'Apex',
    'artist': 'Tres',
    'album': 'Zenith',
    'album_artist': '',
    'duration_ms': 220000,
    'genre': 'Pop',
    'file_path': '/storage/zenith/1.mp3',
    'codec': 'mp3',
    'last_modified': 3000,
  },
];
