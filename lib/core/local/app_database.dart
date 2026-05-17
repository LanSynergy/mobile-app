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

@DriftDatabase(tables: [Tracks, Folders, SmartPlaylists])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'aetherfin_drift.db'));
    return NativeDatabase.createInBackground(file);
  });
}
