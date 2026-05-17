import 'package:drift/drift.dart';

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
    await (db.delete(db.tracks)..where((t) => t.id.like('$uri%'))).go();
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

  Future<List<AfTrack>> searchTracks(String query) async {
    final like = '%$query%';
    final rows = await (db.select(db.tracks)
          ..where((t) => t.title.like(like) | t.artist.like(like) | t.album.like(like))
          ..orderBy([
            (t) => OrderingTerm(expression: t.title.collate(Collate.noCase), mode: OrderingMode.asc)
          ])
          ..limit(50))
        .get();
    return rows.map(rowToTrack).toList();
  }

  Future<int> trackCount() async {
    final countExp = db.tracks.id.count();
    final query = db.selectOnly(db.tracks)..addColumns([countExp]);
    final result = await query.getSingle();
    return result.read(countExp) ?? 0;
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  AfTrack rowToTrack(TrackEntity r) {
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
    );
  }

  Future<void> close() async {
    await db.close();
  }
}
