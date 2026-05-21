import 'package:drift/drift.dart';

import '../../utils/sql.dart';
import '../jellyfin/models/items.dart';
import 'app_database.dart';

class AlbumRepository {
  final AppDatabase db;

  AlbumRepository(this.db);

  Future<List<AfAlbum>> allAlbums({int? limit, int offset = 0}) async {
    final paginated = limit != null;
    final sql = StringBuffer('''
      SELECT album, artist, album_artist, MIN(cover_path) as cover_path,
             COUNT(*) as track_count, SUM(duration_ms) as total_duration_ms,
             MIN(year) as year
      FROM tracks
      WHERE album != ''
      GROUP BY album, COALESCE(NULLIF(album_artist, ''), artist)
      ORDER BY album COLLATE NOCASE ASC
    ''');
    final vars = <Variable>[];
    if (paginated) {
      sql.write(' LIMIT ?1 OFFSET ?2');
      vars.add(Variable<int>(limit));
      vars.add(Variable<int>(offset));
    }
    final rows = await db
        .customSelect(sql.toString(), variables: vars, readsFrom: {db.tracks})
        .get();
    return rows.map(_rowToAlbum).toList();
  }

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
    return rows.map(_rowToAlbum).toList();
  }

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
    return rows.map(_rowToAlbum).toList();
  }

  Future<List<AfAlbum>> albumsByArtist(String artistName,
      {int limit = 200}) async {
    final rows = await db.customSelect(
      '''
      SELECT album, artist, album_artist, MIN(cover_path) as cover_path,
             COUNT(*) as track_count, SUM(duration_ms) as total_duration_ms,
             MIN(year) as year
      FROM tracks
      WHERE album != ''
        AND COALESCE(NULLIF(album_artist, ''), artist) = ?1
      GROUP BY album, COALESCE(NULLIF(album_artist, ''), artist)
      ORDER BY year ASC, album COLLATE NOCASE ASC
      LIMIT ?2
      ''',
      variables: [Variable<String>(artistName), Variable<int>(limit)],
      readsFrom: {db.tracks},
    ).get();
    return rows.map(_rowToAlbum).toList();
  }

  Future<AfAlbum?> albumByKey(String name, String artistName) async {
    final rows = await db.customSelect(
      '''
      SELECT album, artist, album_artist, MIN(cover_path) as cover_path,
             COUNT(*) as track_count, SUM(duration_ms) as total_duration_ms,
             MIN(year) as year
      FROM tracks
      WHERE album = ?1
        AND COALESCE(NULLIF(album_artist, ''), artist) = ?2
      GROUP BY album, COALESCE(NULLIF(album_artist, ''), artist)
      LIMIT 1
      ''',
      variables: [
        Variable<String>(name),
        Variable<String>(artistName),
      ],
      readsFrom: {db.tracks},
    ).get();
    if (rows.isEmpty) return null;
    return _rowToAlbum(rows.first);
  }

  Future<List<AfAlbum>> searchAlbums(String query, {int limit = 50}) async {
    final like = '%${escapeSqlLike(query)}%';
    final rows = await db.customSelect(
      r'''
      SELECT album, artist, album_artist, MIN(cover_path) as cover_path,
             COUNT(*) as track_count, SUM(duration_ms) as total_duration_ms,
             MIN(year) as year
      FROM tracks
      WHERE album != ''
        AND (album        LIKE ?1 ESCAPE '\'
          OR artist       LIKE ?1 ESCAPE '\'
          OR album_artist LIKE ?1 ESCAPE '\')
      GROUP BY album, COALESCE(NULLIF(album_artist, ''), artist)
      ORDER BY album COLLATE NOCASE ASC
      LIMIT ?2
      ''',
      variables: [Variable<String>(like), Variable<int>(limit)],
      readsFrom: {db.tracks},
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

  Future<List<AfAlbum>> favoriteAlbums({int limit = 30}) async {
    final rows = await db.customSelect(
      '''
      SELECT album, artist, album_artist, MIN(cover_path) as cover_path,
             COUNT(*) as track_count, SUM(duration_ms) as total_duration_ms,
             MIN(year) as year
      FROM tracks
      WHERE album != ''
        AND ('local:album:' || album || ':'
             || COALESCE(NULLIF(album_artist, ''), artist))
            IN (SELECT item_id FROM favorites)
      GROUP BY album, COALESCE(NULLIF(album_artist, ''), artist)
      ORDER BY album COLLATE NOCASE ASC
      LIMIT ?1
      ''',
      variables: [Variable<int>(limit)],
      readsFrom: {db.tracks, db.favorites},
    ).get();
    return rows.map((r) {
      final albumName = r.read<String?>('album') ?? 'Unknown';
      final albumArtist = (r.read<String?>('album_artist'))?.isNotEmpty == true
          ? r.read<String>('album_artist')
          : (r.read<String?>('artist') ?? '');
      return AfAlbum(
        id: 'local:album:$albumName:$albumArtist',
        name: albumName,
        artistName: albumArtist,
        trackCount: r.read<int?>('track_count') ?? 0,
        year: r.read<int?>('year'),
        totalDuration:
            Duration(milliseconds: r.read<int?>('total_duration_ms') ?? 0),
        imageUrl: r.read<String?>('cover_path') != null
            ? 'file://${r.read<String>('cover_path')}'
            : null,
        isFavorite: true,
      );
    }).toList();
  }

  AfAlbum _rowToAlbum(QueryRow r) {
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
  }
}
