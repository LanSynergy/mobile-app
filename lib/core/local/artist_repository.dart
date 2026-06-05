import 'package:drift/drift.dart';

import '../../utils/sql.dart';
import '../jellyfin/models/items.dart';
import 'app_database.dart';

class ArtistRepository {
  ArtistRepository(this.db);
  final AppDatabase db;

  // ── Queries ──────────────────────────────────────────────────────────────

  Future<List<AfArtist>> allArtists({int limit = 5000}) async {
    final rows = await db
        .customSelect(
          '''
      SELECT artist, COUNT(DISTINCT album) as album_count,
             COUNT(*) as track_count, MIN(cover_path) as cover_path
      FROM tracks
      WHERE artist != ''
      GROUP BY artist
      ORDER BY artist COLLATE NOCASE ASC
      LIMIT ?1
      ''',
          variables: [Variable<int>(limit)],
        )
        .get();
    return rows.map((r) {
      final name = r.read<String?>('artist') ?? 'Unknown';
      return AfArtist(
        id: 'local:artist:$name',
        name: name,
        albumCount: r.read<int?>('album_count') ?? 0,
        trackCount: r.read<int?>('track_count') ?? 0,
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
             COUNT(*) as track_count, MIN(cover_path) as cover_path
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
      trackCount: r.read<int?>('track_count') ?? 0,
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
             COUNT(*) as track_count, MIN(cover_path) as cover_path
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
        trackCount: r.read<int?>('track_count') ?? 0,
        imageUrl: r.read<String?>('cover_path') != null
            ? 'file://${r.read<String>('cover_path')}'
            : null,
      );
    }).toList();
  }
}
