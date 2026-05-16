import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'smart_playlist_model.dart';

/// SQLite storage for smart playlist definitions.
/// Separate from LocalDb (music metadata) — smart playlists work in all modes.
class SmartPlaylistDb {
  static const _dbName = 'aetherfin_smart_playlists.db';
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
      CREATE TABLE smart_playlists (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        combinator TEXT NOT NULL DEFAULT 'all',
        rules_json TEXT NOT NULL DEFAULT '[]',
        sort TEXT NOT NULL DEFAULT 'title',
        sort_order TEXT NOT NULL DEFAULT 'asc',
        max_limit INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
  }

  // ── CRUD ────────────────────────────────────────────────────────────────

  Future<List<SmartPlaylist>> getAll() async {
    final d = await db;
    final rows = await d.query('smart_playlists', orderBy: 'updated_at DESC');
    return rows.map(_rowToPlaylist).toList();
  }

  Future<SmartPlaylist?> getById(String id) async {
    final d = await db;
    final rows = await d.query('smart_playlists',
        where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return _rowToPlaylist(rows.first);
  }

  Future<SmartPlaylist> save(SmartPlaylist playlist) async {
    final d = await db;
    final isNew = (await getById(playlist.id)) == null;
    final id = isNew && playlist.id.isEmpty ? const Uuid().v4() : playlist.id;
    final updated = playlist.copyWith(
      id: id,
      createdAt: isNew ? DateTime.now() : playlist.createdAt,
      updatedAt: DateTime.now(),
    );
    await d.insert('smart_playlists', {
      'id': updated.id,
      'name': updated.name,
      'combinator': updated.combinator,
      'rules_json': updated.rulesJson,
      'sort': updated.sort,
      'sort_order': updated.sortOrder,
      'max_limit': updated.limit,
      'created_at': updated.createdAt.millisecondsSinceEpoch,
      'updated_at': updated.updatedAt.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return updated;
  }

  Future<void> delete(String id) async {
    final d = await db;
    await d.delete('smart_playlists', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> count() async {
    final d = await db;
    final result = await d.rawQuery('SELECT COUNT(*) as c FROM smart_playlists');
    return (result.first['c'] as int?) ?? 0;
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  SmartPlaylist _rowToPlaylist(Map<String, dynamic> r) {
    return SmartPlaylist(
      id: (r['id'] as String?) ?? '',
      name: (r['name'] as String?) ?? '',
      combinator: (r['combinator'] as String?) ?? 'all',
      rules: SmartPlaylist.parseRules((r['rules_json'] as String?) ?? '[]'),
      sort: (r['sort'] as String?) ?? 'title',
      sortOrder: (r['sort_order'] as String?) ?? 'asc',
      limit: r['max_limit'] as int?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
          (r['created_at'] as int?) ?? 0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
          (r['updated_at'] as int?) ?? 0),
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
