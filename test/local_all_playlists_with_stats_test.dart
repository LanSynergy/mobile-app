// Regression test for LocalDb.allPlaylistsWithStats.
//
// Replaces the N+1 fan-out at LocalBackend.playlists():
//   allPlaylists() + per-row playlistStats() → one SQL with LEFT JOIN.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aetherfin/core/local/app_database.dart';
import 'package:aetherfin/core/local/local_db.dart';

void main() {
  group('LocalDb.allPlaylistsWithStats', () {
    late LocalDb db;

    setUp(() async {
      db = LocalDb(
        database: AppDatabase.forTesting(NativeDatabase.memory()),
      );
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
      await db.addToPlaylist(
        'local:playlist:b',
        ['content://uri/1', 'content://uri/3'],
        makeEntryId: mkEntry,
      );

      await db.createPlaylist('local:playlist:a', 'A Roadtrip');
      await db.addToPlaylist(
        'local:playlist:a',
        ['content://uri/1', 'content://uri/2', 'content://uri/3'],
        makeEntryId: mkEntry,
      );

      // An intentionally empty playlist.
      await db.createPlaylist('local:playlist:e', 'Empty');
    });

    tearDown(() => db.close());

    test('sorted by name (case-insensitive) and includes empty playlists',
        () async {
      final r = await db.allPlaylistsWithStats();
      expect(r.map((p) => p.name), ['A Roadtrip', 'B Workout', 'Empty']);
    });

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
}
