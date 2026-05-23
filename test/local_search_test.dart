// Regression tests for LocalDb.search{Albums,Artists,Playlists}.
//
// Replaces LocalBackend.search()'s old `library.albums()` + `library.artists()`
// + `playlists(limit:1000)` + N+1 stats fan-out: each result type is now one
// SQL query that filters at the database with `LIKE ? ESCAPE '\\'`.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aetherfin/core/local/app_database.dart';
import 'package:aetherfin/core/local/local_db.dart';

void main() {
  group('LocalDb search', () {
    late LocalDb db;

    setUp(() async {
      db = LocalDb(
        database: AppDatabase.forTesting(NativeDatabase.memory()),
      );
      await db.upsertTracks([
        // Album "Coastlines" by "Una" — 2 tracks.
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
        // Album "Mountains" by "Dos" — 1 track.
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
          'cover_path': '/c/mtn.jpg',
        },
        // Album "Plains" — 100% literal album name (no SQL wildcard leak).
        {
          'id': 'content://uri/p1',
          'title': 'Wheat',
          'artist': 'Tres',
          'album': '100% Plains',
          'album_artist': 'Tres',
          'duration_ms': 150000,
          'genre': 'Folk',
          'file_path': '/a/4.mp3',
          'codec': 'mp3',
        },
      ]);
    });

    tearDown(() => db.close());

    group('searchAlbums', () {
      test('matches by album name', () async {
        final r = await db.searchAlbums('coast');
        expect(r.map((a) => a.name), ['Coastlines']);
        expect(r.first.trackCount, 2);
        expect(r.first.totalDuration, const Duration(milliseconds: 380000));
      });

      test('matches by artist name', () async {
        final r = await db.searchAlbums('dos');
        expect(r.map((a) => a.name), ['Mountains']);
      });

      test('escapes SQL wildcard characters', () async {
        // The literal album title is "100% Plains". A query of "%" must
        // NOT match every album — escapeSqlLike turns it into a literal.
        final pctOnly = await db.searchAlbums('%');
        // The only album whose name contains a literal '%' is "100% Plains".
        expect(pctOnly.map((a) => a.name), ['100% Plains']);
      });

      test('id stable with allAlbums', () async {
        final all = await db.allAlbums();
        final hit = await db.searchAlbums('coast');
        final allCoast = all.firstWhere((a) => a.name == 'Coastlines');
        expect(hit.first.id, allCoast.id);
      });

      test('returns empty for an unknown query', () async {
        final r = await db.searchAlbums('zzzz');
        expect(r, isEmpty);
      });
    });

    group('searchArtists', () {
      test('matches by name substring', () async {
        final r = await db.searchArtists('un');
        expect(r.map((a) => a.name), ['Una']);
      });

      test('id stable with allArtists', () async {
        final all = await db.allArtists();
        final hit = await db.searchArtists('una');
        final allUna = all.firstWhere((a) => a.name == 'Una');
        expect(hit.first.id, allUna.id);
      });
    });

    group('searchPlaylists', () {
      setUp(() async {
        await db.createPlaylist('local:playlist:1', 'Roadtrip 2024');
        await db.createPlaylist('local:playlist:2', 'Workout');
        var entryIdCounter = 0;
        await db.addToPlaylist(
          'local:playlist:1',
          ['content://uri/c1', 'content://uri/c2', 'content://uri/m1'],
          makeEntryId: () => 'test_entry_${entryIdCounter++}',
        );
      });

      test('matches by name + computes count/duration in one query', () async {
        final r = await db.searchPlaylists('road');
        expect(r, hasLength(1));
        expect(r.first.name, 'Roadtrip 2024');
        expect(r.first.trackCount, 3);
        // 180 + 200 + 240 = 620 seconds.
        expect(r.first.duration, const Duration(milliseconds: 620000));
      });

      test('matches empty playlists too', () async {
        final r = await db.searchPlaylists('work');
        expect(r, hasLength(1));
        expect(r.first.name, 'Workout');
        expect(r.first.trackCount, 0);
        expect(r.first.duration, Duration.zero);
      });

      test('returns empty for an unknown query', () async {
        final r = await db.searchPlaylists('zzzz');
        expect(r, isEmpty);
      });
    });
  });
}
