import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aetherfin/core/local/app_database.dart';
import 'package:aetherfin/core/local/local_db.dart';

void main() {
  group('LocalDb.trackById', () {
    late LocalDb db;

    setUp(() async {
      db = LocalDb(db: AppDatabase.forTesting(NativeDatabase.memory()));
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

  group('LocalDb.albumByKey', () {
    late LocalDb db;

    setUp(() async {
      db = LocalDb(db: AppDatabase.forTesting(NativeDatabase.memory()));
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

  group('LocalDb.albumsByArtist', () {
    late LocalDb db;

    setUp(() async {
      db = LocalDb(db: AppDatabase.forTesting(NativeDatabase.memory()));
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
      expect(r.first.year, 2018);
      expect(r.last.year, 2020);
    });

    test('honors the album_artist → artist fallback', () async {
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

  group('LocalDb.albumsByGenre', () {
    late LocalDb db;

    setUp(() async {
      db = LocalDb(db: AppDatabase.forTesting(NativeDatabase.memory()));
      await db.upsertTracks([
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
      ]);
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

    test(
      'compilation albums keep album_artist as their artistName so the id matches LocalDb.allAlbums',
      () async {
        final pop = await db.albumsByGenre('Pop');
        expect(pop, hasLength(1));
        expect(pop.single.artistName, 'Various');
        expect(pop.single.id, 'local:album:Coastlines:Various');
      },
    );

    test('aggregates track count and total duration per album', () async {
      final rock = (await db.albumsByGenre('Rock')).single;
      expect(rock.trackCount, 2);
      expect(rock.totalDuration, const Duration(milliseconds: 450000));
    });

    test('respects the limit parameter', () async {
      final res = await db.albumsByGenre('Pop', limit: 0);
      expect(res, isEmpty);
    });
  });

  group('LocalDb.allPlaylistsWithStats', () {
    late LocalDb db;

    setUp(() async {
      db = LocalDb(db: AppDatabase.forTesting(NativeDatabase.memory()));
      await db.upsertTracks([
        {
          'id': 'content://uri/1',
          'title': 'A',
          'artist': 'Una',
          'album': 'Coastlines',
          'album_artist': 'Una',
          'duration_ms': 180000,
          'genre': 'Pop',
          'file_path': '/a/1.mp3',
          'codec': 'mp3',
        },
        {
          'id': 'content://uri/2',
          'title': 'B',
          'artist': 'Una',
          'album': 'Coastlines',
          'album_artist': 'Una',
          'duration_ms': 200000,
          'genre': 'Pop',
          'file_path': '/a/2.mp3',
          'codec': 'mp3',
        },
        {
          'id': 'content://uri/3',
          'title': 'C',
          'artist': 'Dos',
          'album': 'Mountains',
          'album_artist': 'Dos',
          'duration_ms': 240000,
          'genre': 'Rock',
          'file_path': '/a/3.mp3',
          'codec': 'mp3',
        },
      ]);
      var n = 0;
      String mkEntry() => 'e${++n}';

      await db.createPlaylist('local:playlist:b', 'B Workout');
      await db.addToPlaylist('local:playlist:b', [
        'content://uri/1',
        'content://uri/3',
      ], makeEntryId: mkEntry);

      await db.createPlaylist('local:playlist:a', 'A Roadtrip');
      await db.addToPlaylist('local:playlist:a', [
        'content://uri/1',
        'content://uri/2',
        'content://uri/3',
      ], makeEntryId: mkEntry);

      await db.createPlaylist('local:playlist:e', 'Empty');
    });

    tearDown(() => db.close());

    test(
      'sorted by name (case-insensitive) and includes empty playlists',
      () async {
        final r = await db.allPlaylistsWithStats();
        expect(r.map((p) => p.name), ['A Roadtrip', 'B Workout', 'Empty']);
      },
    );

    test('computes track count and total duration in one query', () async {
      final r = await db.allPlaylistsWithStats();
      final road = r.firstWhere((p) => p.name == 'A Roadtrip');
      final workout = r.firstWhere((p) => p.name == 'B Workout');
      final empty = r.firstWhere((p) => p.name == 'Empty');

      expect(road.trackCount, 3);
      expect(road.duration, const Duration(milliseconds: 620000));
      expect(workout.trackCount, 2);
      expect(workout.duration, const Duration(milliseconds: 420000));
      expect(empty.trackCount, 0);
      expect(empty.duration, Duration.zero);
    });

    test('limit caps the result', () async {
      final r = await db.allPlaylistsWithStats(limit: 2);
      expect(r, hasLength(2));
      expect(r.map((p) => p.name), ['A Roadtrip', 'B Workout']);
    });
  });

  group('LocalDb.artistByName', () {
    late LocalDb db;

    setUp(() async {
      db = LocalDb(db: AppDatabase.forTesting(NativeDatabase.memory()));
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

  group('LocalDb.favoriteAlbums', () {
    late LocalDb db;

    setUp(() async {
      db = LocalDb(db: AppDatabase.forTesting(NativeDatabase.memory()));
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
      await db.setFavorite('content://uri/m1', true);
      final r = await db.favoriteAlbums();
      expect(r.map((a) => a.name), ['Coastlines']);
      expect(r.first.isFavorite, isTrue);
      expect(r.first.trackCount, 2);
      expect(r.first.totalDuration, const Duration(milliseconds: 380000));
    });

    test(
      'honors compilation album-artist fallback (album_artist empty)',
      () async {
        await db.setFavorite('local:album:Compilation:Tres', true);
        final r = await db.favoriteAlbums();
        expect(r.map((a) => a.name), ['Compilation']);
        expect(r.first.id, 'local:album:Compilation:Tres');
      },
    );

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

  group('LocalDb pagination', () {
    late LocalDb db;

    setUp(() async {
      db = LocalDb(db: AppDatabase.forTesting(NativeDatabase.memory()));
      final tracks = <Map<String, dynamic>>[];
      for (var i = 0; i < 5; i++) {
        final albumIdx = (i + 1).toString().padLeft(2, '0');
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

  group('LocalDb.recentlyAddedAlbums', () {
    late LocalDb db;

    setUp(() async {
      db = LocalDb(db: AppDatabase.forTesting(NativeDatabase.memory()));
      await db.upsertTracks([
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
      ]);
    });

    tearDown(() => db.close());

    test('orders by MAX(last_modified) descending', () async {
      final albums = await db.recentlyAddedAlbums();
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
      'tracks with NULL last_modified land at the bottom but stay name-stable so identical mtimes have deterministic order',
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
          },
        ]);
        final albums = await db.recentlyAddedAlbums();
        expect(albums.last.name, 'Mystery');
      },
    );

    test('aggregation key matches LocalDb.allAlbums (id stability)', () async {
      final byRecent = await db.recentlyAddedAlbums();
      final byAll = await db.allAlbums();
      final allIds = byAll.map((a) => a.id).toSet();
      for (final a in byRecent) {
        expect(
          allIds,
          contains(a.id),
          reason: 'id mismatch between aggregations: ${a.id}',
        );
      }
    });
  });

  group('LocalDb search', () {
    late LocalDb db;

    setUp(() async {
      db = LocalDb(db: AppDatabase.forTesting(NativeDatabase.memory()));
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
        final pctOnly = await db.searchAlbums('%');
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
        await db.addToPlaylist('local:playlist:1', [
          'content://uri/c1',
          'content://uri/c2',
          'content://uri/m1',
        ], makeEntryId: () => 'test_entry_${entryIdCounter++}');
      });

      test('matches by name + computes count/duration in one query', () async {
        final r = await db.searchPlaylists('road');
        expect(r, hasLength(1));
        expect(r.first.name, 'Roadtrip 2024');
        expect(r.first.trackCount, 3);
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
