import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../jellyfin/models/items.dart';
import '../jellyfin/models/quality.dart';

/// Local SQLite database for caching scanned music metadata.
///
/// Schema stores tracks with their tags, plus a folders table tracking
/// which SAF tree URIs the user has granted access to.
class LocalDb {
  static const _dbName = 'aetherfin_local.db';
  static const _dbVersion = 1;

  Database? _db;

  Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, _dbName);
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE tracks (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        artist TEXT NOT NULL DEFAULT '',
        album TEXT NOT NULL DEFAULT '',
        album_artist TEXT DEFAULT '',
        track_number INTEGER,
        duration_ms INTEGER NOT NULL DEFAULT 0,
        year INTEGER,
        genre TEXT DEFAULT '',
        file_path TEXT NOT NULL,
        file_size INTEGER,
        last_modified INTEGER,
        cover_path TEXT,
        codec TEXT DEFAULT '',
        bitrate INTEGER,
        sample_rate INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE folders (
        uri TEXT PRIMARY KEY,
        display_path TEXT NOT NULL,
        added_at INTEGER NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_tracks_album ON tracks(album)');
    await db.execute('CREATE INDEX idx_tracks_artist ON tracks(artist)');
    await db.execute('CREATE INDEX idx_tracks_genre ON tracks(genre)');
  }

  // ── Folders ─────────────────────────────────────────────────────────────

  Future<void> addFolder(String uri, String displayPath) async {
    final d = await db;
    await d.insert('folders', {
      'uri': uri,
      'display_path': displayPath,
      'added_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> removeFolder(String uri) async {
    final d = await db;
    await d.delete('folders', where: 'uri = ?', whereArgs: [uri]);
    // Also remove tracks from that folder
    await d.delete('tracks', where: 'id LIKE ?', whereArgs: ['$uri%']);
  }

  Future<List<Map<String, dynamic>>> getFolders() async {
    final d = await db;
    return d.query('folders', orderBy: 'added_at ASC');
  }

  // ── Tracks CRUD ─────────────────────────────────────────────────────────

  Future<void> upsertTrack(Map<String, dynamic> track) async {
    final d = await db;
    await d.insert('tracks', track, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> upsertTracks(List<Map<String, dynamic>> tracks) async {
    final d = await db;
    final batch = d.batch();
    for (final t in tracks) {
      batch.insert('tracks', t, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> deleteTrack(String id) async {
    final d = await db;
    await d.delete('tracks', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAllTracks() async {
    final d = await db;
    await d.delete('tracks');
  }

  /// Get the lastModified timestamp for a track (for incremental scan).
  Future<int?> getTrackLastModified(String id) async {
    final d = await db;
    final rows = await d.query('tracks',
        columns: ['last_modified'], where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return rows.first['last_modified'] as int?;
  }

  // ── Query ───────────────────────────────────────────────────────────────

  Future<List<AfTrack>> allTracks({int limit = 5000}) async {
    final d = await db;
    final rows = await d.query('tracks',
        orderBy: 'title COLLATE NOCASE ASC', limit: limit);
    return rows.map(_rowToTrack).toList();
  }

  Future<List<AfAlbum>> allAlbums() async {
    final d = await db;
    final rows = await d.rawQuery('''
      SELECT album, artist, album_artist, MIN(cover_path) as cover_path,
             COUNT(*) as track_count, SUM(duration_ms) as total_duration_ms,
             MIN(year) as year
      FROM tracks
      WHERE album != ''
      GROUP BY album, COALESCE(NULLIF(album_artist, ''), artist)
      ORDER BY album COLLATE NOCASE ASC
    ''');
    return rows.map((r) {
      final albumName = (r['album'] as String?) ?? 'Unknown';
      final artistName = (r['album_artist'] as String?)?.isNotEmpty == true
          ? r['album_artist'] as String
          : (r['artist'] as String?) ?? '';
      return AfAlbum(
        id: 'local:album:$albumName:$artistName',
        name: albumName,
        artistName: artistName,
        trackCount: (r['track_count'] as int?) ?? 0,
        year: r['year'] as int?,
        totalDuration: Duration(milliseconds: (r['total_duration_ms'] as int?) ?? 0),
        imageUrl: r['cover_path'] != null ? 'file://${r['cover_path']}' : null,
      );
    }).toList();
  }

  Future<List<AfArtist>> allArtists() async {
    final d = await db;
    final rows = await d.rawQuery('''
      SELECT artist, COUNT(DISTINCT album) as album_count,
             MIN(cover_path) as cover_path
      FROM tracks
      WHERE artist != ''
      GROUP BY artist
      ORDER BY artist COLLATE NOCASE ASC
    ''');
    return rows.map((r) {
      final name = (r['artist'] as String?) ?? 'Unknown';
      return AfArtist(
        id: 'local:artist:$name',
        name: name,
        albumCount: (r['album_count'] as int?) ?? 0,
        imageUrl: r['cover_path'] != null ? 'file://${r['cover_path']}' : null,
      );
    }).toList();
  }

  Future<List<AfGenre>> allGenres() async {
    final d = await db;
    final rows = await d.rawQuery('''
      SELECT genre, COUNT(*) as count
      FROM tracks
      WHERE genre != ''
      GROUP BY genre
      ORDER BY genre COLLATE NOCASE ASC
    ''');
    const palette = <String>[
      '#5644C9', '#A89DEC', '#3FD18C', '#FF7A59',
      '#F8C42D', '#FF6FB5', '#3DB6FF', '#FF4D6D',
    ];
    return rows.asMap().entries.map((e) {
      final r = e.value;
      final name = (r['genre'] as String?) ?? '';
      return AfGenre(name, palette[e.key % palette.length]);
    }).where((g) => g.name.isNotEmpty).toList();
  }

  Future<List<AfTrack>> tracksByAlbum(String albumName, String artistName) async {
    final d = await db;
    final rows = await d.query('tracks',
        where: 'album = ? AND (artist = ? OR album_artist = ?)',
        whereArgs: [albumName, artistName, artistName],
        orderBy: 'track_number ASC, title ASC');
    return rows.map(_rowToTrack).toList();
  }

  Future<List<AfTrack>> tracksByArtist(String artistName) async {
    final d = await db;
    final rows = await d.query('tracks',
        where: 'artist = ? OR album_artist = ?',
        whereArgs: [artistName, artistName],
        orderBy: 'album ASC, track_number ASC');
    return rows.map(_rowToTrack).toList();
  }

  Future<List<AfTrack>> tracksByGenre(String genre) async {
    final d = await db;
    final rows = await d.query('tracks',
        where: 'genre = ?', whereArgs: [genre],
        orderBy: 'title COLLATE NOCASE ASC');
    return rows.map(_rowToTrack).toList();
  }

  Future<List<AfTrack>> searchTracks(String query) async {
    final d = await db;
    final like = '%$query%';
    final rows = await d.query('tracks',
        where: 'title LIKE ? OR artist LIKE ? OR album LIKE ?',
        whereArgs: [like, like, like],
        orderBy: 'title COLLATE NOCASE ASC',
        limit: 50);
    return rows.map(_rowToTrack).toList();
  }

  Future<int> trackCount() async {
    final d = await db;
    final result = await d.rawQuery('SELECT COUNT(*) as c FROM tracks');
    return (result.first['c'] as int?) ?? 0;
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  AfTrack _rowToTrack(Map<String, dynamic> r) {
    final codec = (r['codec'] as String?) ?? '';
    final bitrate = r['bitrate'] as int?;
    final sampleRate = r['sample_rate'] as int?;
    final isLossless = codec == 'flac' || codec == 'alac' || codec == 'wav';
    return AfTrack(
      id: (r['id'] as String?) ?? '',
      title: (r['title'] as String?) ?? 'Unknown',
      artistName: (r['artist'] as String?) ?? '',
      albumName: (r['album'] as String?) ?? '',
      albumId: null,
      artistId: null,
      trackNumber: r['track_number'] as int?,
      duration: Duration(milliseconds: (r['duration_ms'] as int?) ?? 0),
      quality: TrackQuality(
        sourceCodec: codec,
        bitrateKbps: !isLossless ? bitrate : null,
        bitDepth: null,
        sampleRateKhz: sampleRate != null ? sampleRate ~/ 1000 : null,
      ),
      imageUrl: r['cover_path'] != null ? 'file://${r['cover_path']}' : null,
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
