import 'package:drift/drift.dart';

import '../../utils/sql.dart';
import '../jellyfin/models/items.dart';
import '../jellyfin/models/quality.dart';
import 'app_database.dart';

class TrackRepository {

  TrackRepository(this.db);
  final AppDatabase db;

  // ── CRUD ────────────────────────────────────────────────────────────────

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

  Future<List<String>> trackIdsByPrefix(String prefix) async {
    final rows = await db.customSelect(
      'SELECT id FROM tracks WHERE id LIKE ?1 ESCAPE \'\\\'',
      variables: [Variable<String>('${escapeSqlLike(prefix)}%')],
      readsFrom: {db.tracks},
    ).get();
    return rows.map((r) => r.read<String>('id')).toList();
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

  Future<List<AfTrack>> allTracks({int limit = 100, int offset = 0}) async {
    final rows = await (db.select(db.tracks)
          ..orderBy([(t) => OrderingTerm(expression: t.title.collate(Collate.noCase), mode: OrderingMode.asc)])
          ..limit(limit, offset: offset > 0 ? offset : null))
        .get();
    return rows.map(rowToTrack).toList();
  }

  Future<AfTrack?> trackById(String id) async {
    final row = await (db.select(db.tracks)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return null;
    return rowToTrack(row);
  }

  Future<AfTrackDetails?> trackDetailsById(String id) async {
    final row = await (db.select(db.tracks)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return null;
    final track = rowToTrack(row);
    final codec = row.codec;
    return AfTrackDetails(
      track: track,
      container: codec.isNotEmpty ? codec : null,
      sizeBytes: row.fileSize,
      channels: null,
      sampleRateHz: row.sampleRate,
      bitDepth: null,
      bitrateBps: row.bitrate != null ? row.bitrate! * 1000 : null,
      path: row.filePath,
      genres: row.genre.isNotEmpty ? [row.genre] : const [],
      playCount: null,
      lastPlayedAt: null,
    );
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

  // ── Helpers ──────────────────────────────────────────────────────────────

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
}
