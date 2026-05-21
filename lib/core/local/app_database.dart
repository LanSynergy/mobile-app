import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

@DataClassName('TrackEntity')
class Tracks extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get artist => text().withDefault(const Constant(''))();
  TextColumn get album => text().withDefault(const Constant(''))();
  TextColumn get albumArtist => text().withDefault(const Constant(''))();
  IntColumn get trackNumber => integer().nullable()();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  IntColumn get year => integer().nullable()();
  TextColumn get genre => text().withDefault(const Constant(''))();
  TextColumn get filePath => text()();
  IntColumn get fileSize => integer().nullable()();
  IntColumn get lastModified => integer().nullable()();
  TextColumn get coverPath => text().nullable()();
  TextColumn get codec => text().withDefault(const Constant(''))();
  IntColumn get bitrate => integer().nullable()();
  IntColumn get sampleRate => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('FolderEntity')
class Folders extends Table {
  TextColumn get uri => text()();
  TextColumn get displayPath => text()();
  IntColumn get addedAt => integer()();

  @override
  Set<Column> get primaryKey => {uri};
}

@DataClassName('SmartPlaylistEntity')
class SmartPlaylists extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get combinator => text().withDefault(const Constant('all'))();
  TextColumn get rulesJson => text().withDefault(const Constant('[]'))();
  TextColumn get sort => text().withDefault(const Constant('title'))();
  TextColumn get sortOrder => text().withDefault(const Constant('asc'))();
  IntColumn get maxLimit => integer().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Local-mode favorites — covers tracks, albums and playlists. The
/// `itemId` is whatever the rest of the app uses to address the item
/// (track → `content://` URI, album → `local:album:NAME:ARTIST`,
/// playlist → `local:playlist:UUID`). Persists across launches so
/// hearts stay filled in without a server round-trip.
@DataClassName('FavoriteEntity')
class Favorites extends Table {
  TextColumn get itemId => text()();
  IntColumn get addedAt => integer()();

  @override
  Set<Column> get primaryKey => {itemId};
}

/// Local-mode user playlists. The `id` is generated on creation and
/// follows the `local:playlist:<uuid>` convention so the rest of the
/// app can tell it apart from server-issued playlist IDs.
@DataClassName('PlaylistEntity')
class Playlists extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Ordered tracks inside a local playlist. The `entryId` is a stable
/// per-row UUID so the same track can appear multiple times in one
/// playlist (server backends use a similar entry-id pattern for the
/// same reason). `position` is the user-visible order; we re-pack it
/// on every move/remove so it always stays a dense 0..N sequence.
@DataClassName('PlaylistEntryEntity')
class PlaylistEntries extends Table {
  TextColumn get entryId => text()();
  TextColumn get playlistId => text()();
  TextColumn get trackId => text()();
  IntColumn get position => integer()();
  IntColumn get addedAt => integer()();

  @override
  Set<Column> get primaryKey => {entryId};
}

@DataClassName('CacheEntryEntity')
class CacheEntries extends Table {
  TextColumn get trackId => text()();
  IntColumn get fileSize => integer()();
  IntColumn get lastPlayedAt => integer()();

  @override
  Set<Column> get primaryKey => {trackId};
}

@DriftDatabase(
    tables: [
      Tracks,
      Folders,
      SmartPlaylists,
      Favorites,
      Playlists,
      PlaylistEntries,
      CacheEntries,
    ])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Test-only constructor that lets us inject an in-memory executor
  /// (`NativeDatabase.memory()`) without going through path_provider.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          // v1 → v2 introduces local-mode favorites and user playlists
          // so the hearts and "Save to playlist" actions can persist
          // without a music server.
          if (from < 2) {
            await m.createTable(favorites);
            await m.createTable(playlists);
            await m.createTable(playlistEntries);
          }
          if (from < 3) {
            await m.createTable(cacheEntries);
          }
        },
      );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'aetherfin_drift.db'));
    return NativeDatabase.createInBackground(file);
  });
}
