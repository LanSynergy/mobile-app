import 'package:drift/drift.dart';

import '../../utils/sql.dart';
import '../jellyfin/models/items.dart';
import 'app_database.dart';
import 'local_db_tracks.dart';

class PlaylistRepository {
  final AppDatabase db;
  final TrackRepository tracks;

  PlaylistRepository(this.db, this.tracks);

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
    final favIds = await _favoriteIds();
    return rows.map((r) {
      final entity = db.tracks.map(r.data);
      return (
        entryId: r.read<String>('entry_id'),
        track: tracks.rowToTrack(entity, isFavorite: favIds.contains(entity.id)),
      );
    }).toList();
  }

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

  /// Single SQL: list every playlist with track count + total duration
  /// joined in one pass.
  Future<List<AfPlaylist>> allPlaylistsWithStats({int limit = 200}) async {
    final rows = await db.customSelect(
      r'''
      SELECT p.id   AS id,
             p.name AS name,
             COUNT(pe.entry_id)              AS track_count,
             COALESCE(SUM(t.duration_ms), 0) AS total_duration_ms
      FROM playlists p
      LEFT JOIN playlist_entries pe ON pe.playlist_id = p.id
      LEFT JOIN tracks t            ON t.id           = pe.track_id
      GROUP BY p.id
      ORDER BY p.name COLLATE NOCASE ASC
      LIMIT ?1
      ''',
      variables: [Variable<int>(limit)],
      readsFrom: {db.playlists, db.playlistEntries, db.tracks},
    ).get();
    return rows.map((r) {
      return AfPlaylist(
        id: r.read<String>('id'),
        name: r.read<String>('name'),
        trackCount: r.read<int?>('track_count') ?? 0,
        duration: Duration(
            milliseconds: r.read<int?>('total_duration_ms') ?? 0),
      );
    }).toList();
  }

  Future<List<AfPlaylist>> searchPlaylists(String query,
      {int limit = 50}) async {
    final like = '%${escapeSqlLike(query)}%';
    final rows = await db.customSelect(
      r'''
      SELECT p.id   AS id,
             p.name AS name,
             COUNT(pe.entry_id)                 AS track_count,
             COALESCE(SUM(t.duration_ms), 0)    AS total_duration_ms
      FROM playlists p
      LEFT JOIN playlist_entries pe ON pe.playlist_id = p.id
      LEFT JOIN tracks t            ON t.id         = pe.track_id
      WHERE p.name LIKE ?1 ESCAPE '\'
      GROUP BY p.id
      ORDER BY p.name COLLATE NOCASE ASC
      LIMIT ?2
      ''',
      variables: [Variable<String>(like), Variable<int>(limit)],
      readsFrom: {db.playlists, db.playlistEntries, db.tracks},
    ).get();
    return rows.map((r) {
      return AfPlaylist(
        id: r.read<String>('id'),
        name: r.read<String>('name'),
        trackCount: r.read<int?>('track_count') ?? 0,
        duration: Duration(
            milliseconds: r.read<int?>('total_duration_ms') ?? 0),
      );
    }).toList();
  }

  Future<void> close() async {
    await db.close();
  }

  Future<Set<String>> _favoriteIds() async {
    final rows = await db.select(db.favorites).get();
    return rows.map((r) => r.itemId).toSet();
  }

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
}
