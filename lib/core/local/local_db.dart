import 'package:drift/drift.dart';

import '../../utils/sql.dart';
import '../jellyfin/models/items.dart';
import 'app_database.dart';
import 'local_db_albums.dart';
import 'local_db_playlists.dart';
import 'local_db_tracks.dart';

/// Local database for caching scanned music metadata.
/// Refactored to wrap Drift's [AppDatabase].
class LocalDb {
  LocalDb({AppDatabase? database}) : db = database ?? AppDatabase() {
    tracks = TrackRepository(db);
    albums = AlbumRepository(db);
    playlists = PlaylistRepository(db, tracks);
  }
  final AppDatabase db;

  late final TrackRepository tracks;
  late final AlbumRepository albums;
  late final PlaylistRepository playlists;

  // ── Folders ─────────────────────────────────────────────────────────────

  Future<void> addFolder(String uri, String displayPath) async {
    await db
        .into(db.folders)
        .insert(
          FoldersCompanion.insert(
            uri: uri,
            displayPath: displayPath,
            addedAt: DateTime.now().millisecondsSinceEpoch,
          ),
          mode: InsertMode.replace,
        );
  }

  Future<void> removeFolder(String uri) async {
    await db.transaction(() async {
      await (db.delete(db.folders)..where((f) => f.uri.equals(uri))).go();
      await db.customStatement(
        r"DELETE FROM tracks WHERE id LIKE ? ESCAPE '\'",
        ['${escapeSqlLike(uri)}%'],
      );
    });
  }

  Future<List<Map<String, dynamic>>> getFolders() async {
    final folders = await (db.select(
      db.folders,
    )..orderBy([(t) => OrderingTerm.asc(t.addedAt)])).get();
    return folders
        .map(
          (f) => {
            'uri': f.uri,
            'display_path': f.displayPath,
            'added_at': f.addedAt,
          },
        )
        .toList();
  }

  // ── Tracks CRUD ─────────────────────────────────────────────────────────

  Future<void> upsertTrack(Map<String, dynamic> track) =>
      tracks.upsertTrack(track);

  Future<void> upsertTracks(List<Map<String, dynamic>> trackList) =>
      tracks.upsertTracks(trackList);

  Future<void> deleteTrack(String id) => tracks.deleteTrack(id);

  Future<List<String>> trackIdsByPrefix(String prefix) =>
      tracks.trackIdsByPrefix(prefix);

  Future<void> deleteAllTracks() => tracks.deleteAllTracks();

  Future<int?> getTrackLastModified(String id) =>
      tracks.getTrackLastModified(id);

  // ── Tracks Query ────────────────────────────────────────────────────────

  Future<List<AfTrack>> allTracks({int limit = 5000, int offset = 0}) =>
      tracks.allTracks(limit: limit, offset: offset);

  Future<AfTrack?> trackById(String id) => tracks.trackById(id);

  Future<AfTrackDetails?> trackDetailsById(String id) =>
      tracks.trackDetailsById(id);

  Future<List<AfTrack>> tracksByAlbum(String albumName, String artistName) =>
      tracks.tracksByAlbum(albumName, artistName);

  Future<List<AfTrack>> tracksByArtist(String artistName) =>
      tracks.tracksByArtist(artistName);

  Future<List<AfTrack>> tracksByGenre(String genre) =>
      tracks.tracksByGenre(genre);

  Future<List<AfTrack>> getSimilarTracks(String seedId, {int limit = 50}) =>
      tracks.getSimilarTracks(seedId, limit: limit);

  Future<List<AfTrack>> searchTracks(String query) =>
      tracks.searchTracks(query);

  Future<int> trackCount() => tracks.trackCount();

  // ── Albums Query ────────────────────────────────────────────────────────

  Future<List<AfAlbum>> allAlbums({int? limit, int offset = 0}) =>
      albums.allAlbums(limit: limit, offset: offset);

  Future<List<AfAlbum>> recentlyAddedAlbums({int limit = 20}) =>
      albums.recentlyAddedAlbums(limit: limit);

  Future<List<AfAlbum>> albumsByGenre(String genre, {int limit = 200}) =>
      albums.albumsByGenre(genre, limit: limit);

  Future<List<AfAlbum>> albumsByArtist(String artistName, {int limit = 200}) =>
      albums.albumsByArtist(artistName, limit: limit);

  Future<AfAlbum?> albumByKey(String name, String artistName) =>
      albums.albumByKey(name, artistName);

  Future<List<AfAlbum>> searchAlbums(String query, {int limit = 50}) =>
      albums.searchAlbums(query, limit: limit);

  Future<List<AfAlbum>> favoriteAlbums({int limit = 30}) =>
      albums.favoriteAlbums(limit: limit);

  // ── Artists ─────────────────────────────────────────────────────────────

  Future<List<AfArtist>> allArtists() async {
    final rows = await db.customSelect('''
      SELECT artist, COUNT(DISTINCT album) as album_count,
             MIN(cover_path) as cover_path
      FROM tracks
      WHERE artist != ''
      GROUP BY artist
      ORDER BY artist COLLATE NOCASE ASC
    ''').get();
    return rows.map((r) {
      final name = r.read<String?>('artist') ?? 'Unknown';
      return AfArtist(
        id: 'local:artist:$name',
        name: name,
        albumCount: r.read<int?>('album_count') ?? 0,
        imageUrl: r.read<String?>('cover_path') != null
            ? 'file://${r.read<String>('cover_path')}'
            : null,
      );
    }).toList();
  }

  Future<AfArtist?> artistByName(String name) async {
    final rows = await db
        .customSelect(
          r'''
      SELECT artist, COUNT(DISTINCT album) as album_count,
             MIN(cover_path) as cover_path
      FROM tracks
      WHERE artist != ''
        AND artist = ?1
      GROUP BY artist
      LIMIT 1
      ''',
          variables: [Variable<String>(name)],
          readsFrom: {db.tracks},
        )
        .get();
    if (rows.isEmpty) return null;
    final r = rows.first;
    final resolved = r.read<String?>('artist') ?? 'Unknown';
    return AfArtist(
      id: 'local:artist:$resolved',
      name: resolved,
      albumCount: r.read<int?>('album_count') ?? 0,
      imageUrl: r.read<String?>('cover_path') != null
          ? 'file://${r.read<String>('cover_path')}'
          : null,
    );
  }

  Future<List<AfArtist>> searchArtists(String query, {int limit = 50}) async {
    final like = '%${escapeSqlLike(query)}%';
    final rows = await db
        .customSelect(
          r'''
      SELECT artist, COUNT(DISTINCT album) as album_count,
             MIN(cover_path) as cover_path
      FROM tracks
      WHERE artist != ''
        AND artist LIKE ?1 ESCAPE '\'
      GROUP BY artist
      ORDER BY artist COLLATE NOCASE ASC
      LIMIT ?2
      ''',
          variables: [Variable<String>(like), Variable<int>(limit)],
          readsFrom: {db.tracks},
        )
        .get();
    return rows.map((r) {
      final name = r.read<String?>('artist') ?? 'Unknown';
      return AfArtist(
        id: 'local:artist:$name',
        name: name,
        albumCount: r.read<int?>('album_count') ?? 0,
        imageUrl: r.read<String?>('cover_path') != null
            ? 'file://${r.read<String>('cover_path')}'
            : null,
      );
    }).toList();
  }

  // ── Genres ──────────────────────────────────────────────────────────────

  Future<List<AfGenre>> allGenres() async {
    final rows = await db.customSelect('''
      SELECT genre, COUNT(*) as count, MIN(cover_path) as cover_path
      FROM tracks
      WHERE genre != ''
      GROUP BY genre
      ORDER BY genre COLLATE NOCASE ASC
    ''').get();
    const palette = <String>[
      '#5644C9',
      '#A89DEC',
      '#3FD18C',
      '#FF7A59',
      '#F8C42D',
      '#FF6FB5',
      '#3DB6FF',
      '#FF4D6D',
    ];
    int index = 0;
    final results = <AfGenre>[];
    for (final r in rows) {
      final name = r.read<String?>('genre') ?? '';
      if (name.isEmpty) continue;
      results.add(
        AfGenre(
          name,
          palette[index % palette.length],
          imageUrl: r.read<String?>('cover_path') != null
              ? 'file://${r.read<String>('cover_path')}'
              : null,
        ),
      );
      index++;
    }
    return results;
  }

  // ── Favorites ─────────────────────────────────────────────────────────

  Future<bool> isFavorite(String itemId) async {
    final row = await (db.select(
      db.favorites,
    )..where((f) => f.itemId.equals(itemId))).getSingleOrNull();
    return row != null;
  }

  Future<Set<String>> favoriteIds() async {
    final rows = await db.select(db.favorites).get();
    return rows.map((r) => r.itemId).toSet();
  }

  Future<void> setFavorite(String itemId, bool isFavorite) async {
    if (isFavorite) {
      await db
          .into(db.favorites)
          .insert(
            FavoritesCompanion.insert(
              itemId: itemId,
              addedAt: DateTime.now().millisecondsSinceEpoch,
            ),
            mode: InsertMode.replace,
          );
    } else {
      await (db.delete(
        db.favorites,
      )..where((f) => f.itemId.equals(itemId))).go();
    }
  }

  Future<List<AfTrack>> favoriteTracks({int limit = 500}) async {
    final favIds = await favoriteIds();
    if (favIds.isEmpty) return const [];
    final rows =
        await (db.select(db.tracks)
              ..where((t) => t.id.isIn(favIds))
              ..orderBy([
                (t) => OrderingTerm(
                  expression: t.title.collate(Collate.noCase),
                  mode: OrderingMode.asc,
                ),
              ])
              ..limit(limit))
            .get();
    return rows.map((r) => tracks.rowToTrack(r, isFavorite: true)).toList();
  }

  // ── Playback History & Lost Memories ───────────────────────────────────

  /// Fetches tracks played exactly N years ago on the same calendar day.
  Future<List<AfTrack>> getLostMemories({int limit = 50}) async {
    final now = DateTime.now();
    final targetDates = <String>[];
    for (var i = 1; i <= 5; i++) {
      final pastDate = DateTime(now.year - i, now.month, now.day);
      final dateStr = pastDate.toIso8601String().substring(0, 10);
      targetDates.add(dateStr);
    }

    final placeHolders = targetDates.map((_) => '?').join(',');
    final query = '''
      SELECT track_id, title, artist, album, duration_ms, image_url, MAX(played_at) as last_played
      FROM playback_history
      WHERE date(played_at / 1000, 'unixepoch', 'localtime') IN ($placeHolders)
      GROUP BY track_id
      ORDER BY last_played DESC
      LIMIT ?
    ''';

    final variables = [
      ...targetDates.map(Variable<String>.new),
      Variable<int>(limit),
    ];

    final rows = await db.customSelect(
      query,
      variables: variables,
      readsFrom: {db.playbackHistory},
    ).get();

    final result = <AfTrack>[];
    final favIds = await favoriteIds();

    for (final r in rows) {
      final trackId = r.read<String>('track_id');
      final title = r.read<String?>('title') ?? 'Unknown';
      final artistName = r.read<String?>('artist') ?? 'Unknown';
      final albumName = r.read<String?>('album') ?? 'Unknown';
      final durationMs = r.read<int?>('duration_ms') ?? 0;
      final imageUrl = r.read<String?>('image_url');

      result.add(
        AfTrack(
          id: trackId,
          title: title,
          artistName: artistName,
          albumName: albumName,
          duration: Duration(milliseconds: durationMs),
          imageUrl: imageUrl,
          isFavorite: favIds.contains(trackId),
        ),
      );
    }
    return result;
  }

  // ── Playlist queries (delegated) ────────────────────────────────────────

  Future<List<PlaylistEntity>> allPlaylists() => playlists.allPlaylists();

  Future<PlaylistEntity?> getPlaylist(String id) => playlists.getPlaylist(id);

  Future<void> createPlaylist(String id, String name) =>
      playlists.createPlaylist(id, name);

  Future<void> renamePlaylist(String id, String newName) =>
      playlists.renamePlaylist(id, newName);

  Future<void> deletePlaylist(String id) => playlists.deletePlaylist(id);

  Future<({int count, int durationMs})> playlistStats(String playlistId) =>
      playlists.playlistStats(playlistId);

  Future<List<({String entryId, AfTrack track})>> playlistTracks(
    String playlistId,
  ) => playlists.playlistTracks(playlistId);

  Future<void> addToPlaylist(
    String playlistId,
    List<String> trackIds, {
    required String Function() makeEntryId,
  }) => playlists.addToPlaylist(playlistId, trackIds, makeEntryId: makeEntryId);

  Future<void> removePlaylistEntries(
    String playlistId,
    List<String> entryIds,
  ) => playlists.removePlaylistEntries(playlistId, entryIds);

  Future<void> movePlaylistEntry(
    String playlistId,
    String entryId,
    int newIndex,
  ) => playlists.movePlaylistEntry(playlistId, entryId, newIndex);

  Future<List<AfPlaylist>> allPlaylistsWithStats({int limit = 200}) =>
      playlists.allPlaylistsWithStats(limit: limit);

  Future<List<AfPlaylist>> searchPlaylists(String query, {int limit = 50}) =>
      playlists.searchPlaylists(query, limit: limit);

  // ── Lifecycle ───────────────────────────────────────────────────────────

  Future<void> close() async {
    await db.close();
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  AfTrack rowToTrack(TrackEntity r, {bool isFavorite = false}) =>
      tracks.rowToTrack(r, isFavorite: isFavorite);
}
