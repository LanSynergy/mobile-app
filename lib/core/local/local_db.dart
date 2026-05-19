import 'package:drift/drift.dart';

import '../../utils/sql.dart';
import '../jellyfin/models/items.dart';
import '../jellyfin/models/quality.dart';
import 'app_database.dart';

/// Local database for caching scanned music metadata.
/// Refactored to wrap Drift's [AppDatabase].
class LocalDb {
  final AppDatabase db;

  LocalDb({AppDatabase? database}) : db = database ?? AppDatabase();

  // ── Folders ─────────────────────────────────────────────────────────────

  Future<void> addFolder(String uri, String displayPath) async {
    await db.into(db.folders).insert(
        FoldersCompanion.insert(
          uri: uri,
          displayPath: displayPath,
          addedAt: DateTime.now().millisecondsSinceEpoch,
        ),
        mode: InsertMode.replace);
  }

  Future<void> removeFolder(String uri) async {
    await (db.delete(db.folders)..where((f) => f.uri.equals(uri))).go();
    // Substring match via raw SQL so we can attach an ESCAPE clause —
    // drift's expression-level `like()` has no escape parameter.
    // SAF tree URIs are unlikely to contain `%` or `_`, but a folder
    // whose name does would otherwise delete unrelated tracks whose IDs
    // happen to share a prefix.
    await db.customStatement(
      r"DELETE FROM tracks WHERE id LIKE ? ESCAPE '\'",
      ['${escapeSqlLike(uri)}%'],
    );
  }

  Future<List<Map<String, dynamic>>> getFolders() async {
    final folders = await (db.select(db.folders)..orderBy([(t) => OrderingTerm.asc(t.addedAt)])).get();
    return folders.map((f) => {
      'uri': f.uri,
      'display_path': f.displayPath,
      'added_at': f.addedAt,
    }).toList();
  }

  // ── Tracks CRUD ─────────────────────────────────────────────────────────

  Future<void> upsertTrack(Map<String, dynamic> track) async {
    await db.into(db.tracks).insert(
        _trackMapToCompanion(track),
        mode: InsertMode.replace);
  }

  Future<void> upsertTracks(List<Map<String, dynamic>> tracks) async {
    await db.batch((batch) {
      batch.insertAll(
          db.tracks,
          tracks.map(_trackMapToCompanion),
          mode: InsertMode.replace);
    });
  }

  TracksCompanion _trackMapToCompanion(Map<String, dynamic> track) {
    return TracksCompanion.insert(
      id: track['id'] as String,
      title: track['title'] as String,
      artist: Value((track['artist'] as String?) ?? ''),
      album: Value((track['album'] as String?) ?? ''),
      albumArtist: Value((track['album_artist'] as String?) ?? ''),
      trackNumber: Value(track['track_number'] as int?),
      durationMs: Value((track['duration_ms'] as int?) ?? 0),
      year: Value(track['year'] as int?),
      genre: Value((track['genre'] as String?) ?? ''),
      filePath: track['file_path'] as String,
      fileSize: Value(track['file_size'] as int?),
      lastModified: Value(track['last_modified'] as int?),
      coverPath: Value(track['cover_path'] as String?),
      codec: Value((track['codec'] as String?) ?? ''),
      bitrate: Value(track['bitrate'] as int?),
      sampleRate: Value(track['sample_rate'] as int?),
    );
  }

  Future<void> deleteTrack(String id) async {
    await (db.delete(db.tracks)..where((t) => t.id.equals(id))).go();
  }

  Future<void> deleteAllTracks() async {
    await db.delete(db.tracks).go();
  }

  Future<int?> getTrackLastModified(String id) async {
    final query = db.select(db.tracks)..where((t) => t.id.equals(id));
    final result = await query.getSingleOrNull();
    return result?.lastModified;
  }

  // ── Query ───────────────────────────────────────────────────────────────

  Future<List<AfTrack>> allTracks({int limit = 5000}) async {
    final rows = await (db.select(db.tracks)
          ..orderBy([(t) => OrderingTerm(expression: t.title.collate(Collate.noCase), mode: OrderingMode.asc)])
          ..limit(limit))
        .get();
    return rows.map(rowToTrack).toList();
  }

  Future<List<AfAlbum>> allAlbums() async {
    final rows = await db.customSelect('''
      SELECT album, artist, album_artist, MIN(cover_path) as cover_path,
             COUNT(*) as track_count, SUM(duration_ms) as total_duration_ms,
             MIN(year) as year
      FROM tracks
      WHERE album != ''
      GROUP BY album, COALESCE(NULLIF(album_artist, ''), artist)
      ORDER BY album COLLATE NOCASE ASC
    ''').get();
    return rows.map((r) {
      final albumName = r.read<String?>('album') ?? 'Unknown';
      final artistName = (r.read<String?>('album_artist'))?.isNotEmpty == true
          ? r.read<String>('album_artist')
          : (r.read<String?>('artist') ?? '');
      return AfAlbum(
        id: 'local:album:$albumName:$artistName',
        name: albumName,
        artistName: artistName,
        trackCount: r.read<int?>('track_count') ?? 0,
        year: r.read<int?>('year'),
        totalDuration: Duration(milliseconds: r.read<int?>('total_duration_ms') ?? 0),
        imageUrl: r.read<String?>('cover_path') != null ? 'file://${r.read<String>('cover_path')}' : null,
      );
    }).toList();
  }

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
        imageUrl: r.read<String?>('cover_path') != null ? 'file://${r.read<String>('cover_path')}' : null,
      );
    }).toList();
  }

  Future<List<AfGenre>> allGenres() async {
    final rows = await db.customSelect('''
      SELECT genre, COUNT(*) as count, MIN(cover_path) as cover_path
      FROM tracks
      WHERE genre != ''
      GROUP BY genre
      ORDER BY genre COLLATE NOCASE ASC
    ''').get();
    const palette = <String>[
      '#5644C9', '#A89DEC', '#3FD18C', '#FF7A59',
      '#F8C42D', '#FF6FB5', '#3DB6FF', '#FF4D6D',
    ];
    int index = 0;
    final results = <AfGenre>[];
    for (final r in rows) {
      final name = r.read<String?>('genre') ?? '';
      if (name.isEmpty) continue;
      results.add(AfGenre(
        name,
        palette[index % palette.length],
        imageUrl: r.read<String?>('cover_path') != null ? 'file://${r.read<String>('cover_path')}' : null,
      ));
      index++;
    }
    return results;
  }

  Future<List<AfTrack>> tracksByAlbum(String albumName, String artistName) async {
    final rows = await (db.select(db.tracks)
          ..where((t) => t.album.equals(albumName) & (t.artist.equals(artistName) | t.albumArtist.equals(artistName)))
          ..orderBy([
            (t) => OrderingTerm.asc(t.trackNumber),
            (t) => OrderingTerm.asc(t.title),
          ]))
        .get();
    return rows.map(rowToTrack).toList();
  }

  Future<List<AfTrack>> tracksByArtist(String artistName) async {
    final rows = await (db.select(db.tracks)
          ..where((t) => t.artist.equals(artistName) | t.albumArtist.equals(artistName))
          ..orderBy([
            (t) => OrderingTerm.asc(t.album),
            (t) => OrderingTerm.asc(t.trackNumber),
          ]))
        .get();
    return rows.map(rowToTrack).toList();
  }

  Future<List<AfTrack>> tracksByGenre(String genre) async {
    final rows = await (db.select(db.tracks)
          ..where((t) => t.genre.equals(genre))
          ..orderBy([
            (t) => OrderingTerm(expression: t.title.collate(Collate.noCase), mode: OrderingMode.asc)
          ]))
        .get();
    return rows.map(rowToTrack).toList();
  }

  /// Albums ordered by most-recently-modified track, descending.
  ///
  /// Mirrors [allAlbums]'s aggregation key (album + COALESCE(album_artist,
  /// artist)) so AfAlbum.id matches across queries. We use
  /// `MAX(last_modified) DESC` per group as the best proxy for "recently
  /// added" without a schema migration — newly-downloaded files have
  /// recent mtimes; restored backups keep their original mtime, which is
  /// also a reasonable signal for "when did this enter my library".
  Future<List<AfAlbum>> recentlyAddedAlbums({int limit = 20}) async {
    final rows = await db.customSelect(
      '''
      SELECT album, artist, album_artist, MIN(cover_path) as cover_path,
             COUNT(*) as track_count, SUM(duration_ms) as total_duration_ms,
             MIN(year) as year,
             MAX(COALESCE(last_modified, 0)) as max_last_modified
      FROM tracks
      WHERE album != ''
      GROUP BY album, COALESCE(NULLIF(album_artist, ''), artist)
      ORDER BY max_last_modified DESC, album COLLATE NOCASE ASC
      LIMIT ?
      ''',
      variables: [Variable<int>(limit)],
    ).get();
    return rows.map((r) {
      final albumName = r.read<String?>('album') ?? 'Unknown';
      final artistName = (r.read<String?>('album_artist'))?.isNotEmpty == true
          ? r.read<String>('album_artist')
          : (r.read<String?>('artist') ?? '');
      return AfAlbum(
        id: 'local:album:$albumName:$artistName',
        name: albumName,
        artistName: artistName,
        trackCount: r.read<int?>('track_count') ?? 0,
        year: r.read<int?>('year'),
        totalDuration:
            Duration(milliseconds: r.read<int?>('total_duration_ms') ?? 0),
        imageUrl: r.read<String?>('cover_path') != null
            ? 'file://${r.read<String>('cover_path')}'
            : null,
      );
    }).toList();
  }

  /// Albums whose tracks tag the given genre. Mirrors [allAlbums]'s
  /// aggregation (album-artist falls back to track artist; `MIN(cover_path)`
  /// picks a representative cover; `SUM(duration_ms)` totals runtime) but
  /// filters by `genre` in SQL so we never load tracks we don't need.
  Future<List<AfAlbum>> albumsByGenre(String genre, {int limit = 200}) async {
    final rows = await db.customSelect(
      '''
      SELECT album, artist, album_artist, MIN(cover_path) as cover_path,
             COUNT(*) as track_count, SUM(duration_ms) as total_duration_ms,
             MIN(year) as year
      FROM tracks
      WHERE album != '' AND genre = ?
      GROUP BY album, COALESCE(NULLIF(album_artist, ''), artist)
      ORDER BY album COLLATE NOCASE ASC
      LIMIT ?
      ''',
      variables: [Variable<String>(genre), Variable<int>(limit)],
    ).get();
    return rows.map((r) {
      final albumName = r.read<String?>('album') ?? 'Unknown';
      final artistName = (r.read<String?>('album_artist'))?.isNotEmpty == true
          ? r.read<String>('album_artist')
          : (r.read<String?>('artist') ?? '');
      return AfAlbum(
        id: 'local:album:$albumName:$artistName',
        name: albumName,
        artistName: artistName,
        trackCount: r.read<int?>('track_count') ?? 0,
        year: r.read<int?>('year'),
        totalDuration:
            Duration(milliseconds: r.read<int?>('total_duration_ms') ?? 0),
        imageUrl: r.read<String?>('cover_path') != null
            ? 'file://${r.read<String>('cover_path')}'
            : null,
      );
    }).toList();
  }

  Future<List<AfTrack>> searchTracks(String query) async {
    // Escape `%`, `_`, and `\` so a query like `100%` is matched
    // literally instead of acting as a wildcard. Use customSelect so
    // we can attach the ESCAPE clause — drift's column-level `.like()`
    // has no escape parameter.
    final like = '%${escapeSqlLike(query)}%';
    final rows = await db.customSelect(
      r'''
        SELECT * FROM tracks
        WHERE title  LIKE ?1 ESCAPE '\'
           OR artist LIKE ?1 ESCAPE '\'
           OR album  LIKE ?1 ESCAPE '\'
        ORDER BY title COLLATE NOCASE ASC
        LIMIT 50
      ''',
      variables: [Variable<String>(like)],
      readsFrom: {db.tracks},
    ).get();
    return rows.map((r) {
      final entity = db.tracks.map(r.data);
      return rowToTrack(entity);
    }).toList();
  }



  Future<int> trackCount() async {
    final countExp = db.tracks.id.count();
    final query = db.selectOnly(db.tracks)..addColumns([countExp]);
    final result = await query.getSingle();
    return result.read(countExp) ?? 0;
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  AfTrack rowToTrack(TrackEntity r, {bool isFavorite = false}) {
    final codec = r.codec;
    final bitrate = r.bitrate;
    final sampleRate = r.sampleRate;
    final isLossless = codec == 'flac' || codec == 'alac' || codec == 'wav';
    return AfTrack(
      id: r.id,
      title: r.title,
      artistName: r.artist,
      albumName: r.album,
      albumId: null,
      artistId: null,
      trackNumber: r.trackNumber,
      duration: Duration(milliseconds: r.durationMs),
      quality: TrackQuality(
        sourceCodec: codec,
        bitrateKbps: !isLossless ? bitrate : null,
        bitDepth: null,
        sampleRateKhz: sampleRate != null ? sampleRate ~/ 1000 : null,
      ),
      imageUrl: r.coverPath != null ? 'file://${r.coverPath}' : null,
      isFavorite: isFavorite,
    );
  }

  // ── Favorites ─────────────────────────────────────────────────────────
  //
  // The local-mode equivalent of the server `setFavorite` endpoint. We
  // store one row per favorited item id (track / album / playlist) and
  // look the set up in bulk so query paths that return many tracks
  // hydrate `isFavorite` in a single round trip.

  Future<bool> isFavorite(String itemId) async {
    final row = await (db.select(db.favorites)
          ..where((f) => f.itemId.equals(itemId)))
        .getSingleOrNull();
    return row != null;
  }

  Future<Set<String>> favoriteIds() async {
    final rows = await db.select(db.favorites).get();
    return rows.map((r) => r.itemId).toSet();
  }

  Future<void> setFavorite(String itemId, bool isFavorite) async {
    if (isFavorite) {
      await db.into(db.favorites).insert(
            FavoritesCompanion.insert(
              itemId: itemId,
              addedAt: DateTime.now().millisecondsSinceEpoch,
            ),
            mode: InsertMode.replace,
          );
    } else {
      await (db.delete(db.favorites)
            ..where((f) => f.itemId.equals(itemId)))
          .go();
    }
  }

  /// Track rows for every favorited *track* id, in alphabetical order.
  /// Items in `favorites` that no longer match a track (e.g. the file
  /// was deleted) are silently filtered out by the inner join.
  Future<List<AfTrack>> favoriteTracks({int limit = 500}) async {
    final favIds = await favoriteIds();
    if (favIds.isEmpty) return const [];
    final rows = await (db.select(db.tracks)
          ..where((t) => t.id.isIn(favIds))
          ..orderBy([
            (t) => OrderingTerm(
                expression: t.title.collate(Collate.noCase),
                mode: OrderingMode.asc),
          ])
          ..limit(limit))
        .get();
    return rows.map((r) => rowToTrack(r, isFavorite: true)).toList();
  }

  // ── Playlists ─────────────────────────────────────────────────────────
  //
  // Server playlists are owned by the server; local-mode playlists are
  // owned by this database. The `id` is shaped `local:playlist:<uuid>`
  // so the rest of the app (album/track-id parsers, share sheets, etc.)
  // can tell a local playlist apart from a server one.

  Future<List<PlaylistEntity>> allPlaylists() {
    return (db.select(db.playlists)
          ..orderBy([
            (p) => OrderingTerm(
                expression: p.name.collate(Collate.noCase),
                mode: OrderingMode.asc),
          ]))
        .get();
  }

  Future<PlaylistEntity?> getPlaylist(String id) {
    return (db.select(db.playlists)..where((p) => p.id.equals(id)))
        .getSingleOrNull();
  }

  Future<void> createPlaylist(String id, String name) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.into(db.playlists).insert(
          PlaylistsCompanion.insert(
            id: id,
            name: name,
            createdAt: now,
            updatedAt: now,
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  Future<void> renamePlaylist(String id, String newName) async {
    await (db.update(db.playlists)..where((p) => p.id.equals(id))).write(
      PlaylistsCompanion(
        name: Value(newName),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  Future<void> deletePlaylist(String id) async {
    await db.transaction(() async {
      await (db.delete(db.playlistEntries)
            ..where((e) => e.playlistId.equals(id)))
          .go();
      await (db.delete(db.playlists)..where((p) => p.id.equals(id))).go();
    });
  }

  /// Counts only — cheap enough to call once per row when rendering the
  /// playlists list. The album/duration mosaic is computed elsewhere
  /// from `playlistTracks` when the user opens the playlist.
  Future<({int count, int durationMs})> playlistStats(String playlistId) async {
    final rows = await db.customSelect(
      '''
        SELECT COUNT(*) AS c, COALESCE(SUM(t.duration_ms), 0) AS d
        FROM playlist_entries pe
        LEFT JOIN tracks t ON t.id = pe.track_id
        WHERE pe.playlist_id = ?
      ''',
      variables: [Variable<String>(playlistId)],
      readsFrom: {db.playlistEntries, db.tracks},
    ).getSingle();
    return (
      count: rows.read<int?>('c') ?? 0,
      durationMs: rows.read<int?>('d') ?? 0,
    );
  }

  Future<List<({String entryId, AfTrack track})>> playlistTracks(
      String playlistId) async {
    final rows = await db.customSelect(
      '''
        SELECT t.*, pe.entry_id AS entry_id, pe.position AS position
        FROM playlist_entries pe
        INNER JOIN tracks t ON t.id = pe.track_id
        WHERE pe.playlist_id = ?
        ORDER BY pe.position ASC
      ''',
      variables: [Variable<String>(playlistId)],
      readsFrom: {db.playlistEntries, db.tracks},
    ).get();
    final favIds = await favoriteIds();
    return rows.map((r) {
      final entity = db.tracks.map(r.data);
      return (
        entryId: r.read<String>('entry_id'),
        track: rowToTrack(entity, isFavorite: favIds.contains(entity.id)),
      );
    }).toList();
  }

  /// Append [trackIds] to the end of the playlist. Each insert gets a
  /// fresh UUID-style entry id so duplicates of the same track can
  /// coexist (same semantics as Jellyfin/Subsonic playlist entries).
  Future<void> addToPlaylist(
    String playlistId,
    List<String> trackIds, {
    required String Function() makeEntryId,
  }) async {
    if (trackIds.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction(() async {
      final maxPos = await db.customSelect(
        'SELECT COALESCE(MAX(position), -1) AS m '
        'FROM playlist_entries WHERE playlist_id = ?',
        variables: [Variable<String>(playlistId)],
        readsFrom: {db.playlistEntries},
      ).getSingle();
      var next = (maxPos.read<int?>('m') ?? -1) + 1;
      await db.batch((batch) {
        for (final id in trackIds) {
          batch.insert(
            db.playlistEntries,
            PlaylistEntriesCompanion.insert(
              entryId: makeEntryId(),
              playlistId: playlistId,
              trackId: id,
              position: next++,
              addedAt: now,
            ),
          );
        }
      });
      await (db.update(db.playlists)
            ..where((p) => p.id.equals(playlistId)))
          .write(PlaylistsCompanion(updatedAt: Value(now)));
    });
  }

  Future<void> removePlaylistEntries(
      String playlistId, List<String> entryIds) async {
    if (entryIds.isEmpty) return;
    await db.transaction(() async {
      await (db.delete(db.playlistEntries)
            ..where((e) =>
                e.playlistId.equals(playlistId) & e.entryId.isIn(entryIds)))
          .go();
      await _repackPositions(playlistId);
      await (db.update(db.playlists)
            ..where((p) => p.id.equals(playlistId)))
          .write(PlaylistsCompanion(
              updatedAt: Value(DateTime.now().millisecondsSinceEpoch)));
    });
  }

  /// Move [entryId] to position [newIndex] (0-based) within its playlist.
  /// Positions are re-packed to a dense 0..N sequence so subsequent
  /// queries can keep relying on monotonic positions.
  Future<void> movePlaylistEntry(
      String playlistId, String entryId, int newIndex) async {
    await db.transaction(() async {
      final entries = await (db.select(db.playlistEntries)
            ..where((e) => e.playlistId.equals(playlistId))
            ..orderBy([(e) => OrderingTerm.asc(e.position)]))
          .get();
      final ordered = entries.toList();
      final fromIdx = ordered.indexWhere((e) => e.entryId == entryId);
      if (fromIdx < 0) return;
      final clamped = newIndex.clamp(0, ordered.length - 1);
      final moved = ordered.removeAt(fromIdx);
      ordered.insert(clamped, moved);
      await db.batch((batch) {
        for (var i = 0; i < ordered.length; i++) {
          batch.update(
            db.playlistEntries,
            PlaylistEntriesCompanion(position: Value(i)),
            where: (e) => e.entryId.equals(ordered[i].entryId),
          );
        }
      });
      await (db.update(db.playlists)
            ..where((p) => p.id.equals(playlistId)))
          .write(PlaylistsCompanion(
              updatedAt: Value(DateTime.now().millisecondsSinceEpoch)));
    });
  }

  /// Re-densify position values to 0..N-1 after a removal. Caller must
  /// already be inside a transaction.
  Future<void> _repackPositions(String playlistId) async {
    final remaining = await (db.select(db.playlistEntries)
          ..where((e) => e.playlistId.equals(playlistId))
          ..orderBy([(e) => OrderingTerm.asc(e.position)]))
        .get();
    await db.batch((batch) {
      for (var i = 0; i < remaining.length; i++) {
        batch.update(
          db.playlistEntries,
          PlaylistEntriesCompanion(position: Value(i)),
          where: (e) => e.entryId.equals(remaining[i].entryId),
        );
      }
    });
  }

  Future<void> close() async {
    await db.close();
  }
}
