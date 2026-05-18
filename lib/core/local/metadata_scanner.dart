import 'dart:convert' show utf8;
import 'dart:io';

import 'package:crypto/crypto.dart' show sha1;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../utils/log.dart';
import 'local_db.dart';
import 'saf_picker.dart';

/// Orchestrates scanning SAF folders: lists files → reads metadata → inserts
/// into the local SQLite database. Reports progress via a callback.
class MetadataScanner {
  final LocalDb db;

  MetadataScanner(this.db);

  /// Scan a folder tree URI. Calls [onProgress] with (completed, total).
  /// Returns the number of tracks inserted/updated.
  Future<int> scanFolder(
    String treeUri, {
    void Function(int completed, int total)? onProgress,
  }) async {
    afLog('local', 'scanFolder start: $treeUri');

    // 1. List all audio files
    final files = await SafPicker.listAudioFiles(treeUri);
    afLog('local', 'found ${files.length} audio files');

    if (files.isEmpty) return 0;

    int completed = 0;
    int inserted = 0;
    final coverCacheDir = await _coverCacheDir();

    // 2. Process in batches of 50 for DB efficiency
    final batch = <Map<String, dynamic>>[];

    for (final file in files) {
      // Check if file is already in DB and unchanged
      final existingModified = await db.getTrackLastModified(file.uri);
      if (existingModified != null && existingModified == file.lastModified) {
        completed++;
        onProgress?.call(completed, files.length);
        continue;
      }

      // 3. Read metadata
      try {
        final meta = await SafPicker.readMetadata(file.uri);
        final title = meta.title?.isNotEmpty == true
            ? meta.title!
            : _titleFromFilename(file.name);

        // 4. Extract cover art (if not already cached)
        String? coverPath;
        final coverFile = File(p.join(coverCacheDir, _coverFilename(file.uri)));
        if (!coverFile.existsSync()) {
          final artBytes = await SafPicker.readCoverArt(file.uri);
          if (artBytes != null && artBytes.isNotEmpty) {
            await coverFile.writeAsBytes(artBytes);
            coverPath = coverFile.path;
          }
        } else {
          coverPath = coverFile.path;
        }

        batch.add({
          'id': file.uri,
          'title': title,
          'artist': meta.artist ?? '',
          'album': meta.album ?? '',
          'album_artist': meta.albumArtist ?? '',
          'track_number': meta.trackNum,
          'duration_ms': meta.durationMs,
          'year': meta.yearInt,
          'genre': meta.genre ?? '',
          'file_path': file.name,
          'file_size': file.size,
          'last_modified': file.lastModified,
          'cover_path': coverPath,
          'codec': meta.codec,
          'bitrate': meta.bitrateKbps,
          'sample_rate': meta.sampleRateHz,
        });

        inserted++;
      } catch (e) {
        afLog('local', 'metadata read failed for ${file.name}', error: e);
      }

      completed++;
      onProgress?.call(completed, files.length);

      // Flush batch every 50 tracks
      if (batch.length >= 50) {
        await db.upsertTracks(batch);
        batch.clear();
      }
    }

    // Flush remaining
    if (batch.isNotEmpty) {
      await db.upsertTracks(batch);
    }

    afLog('local', 'scanFolder done: $inserted tracks inserted/updated');
    return inserted;
  }

  /// Remove tracks from DB that no longer exist on disk for a given folder.
  Future<int> pruneDeletedFiles(String treeUri) async {
    final files = await SafPicker.listAudioFiles(treeUri);
    final existingUris = files.map((f) => f.uri).toSet();

    final dbTracks = await db.allTracks();
    int pruned = 0;
    for (final track in dbTracks) {
      if (track.id.startsWith(treeUri) && !existingUris.contains(track.id)) {
        await db.deleteTrack(track.id);
        pruned++;
      }
    }
    if (pruned > 0) {
      afLog('local', 'pruned $pruned deleted tracks');
    }
    return pruned;
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  Future<String> _coverCacheDir() async {
    final appDir = await getApplicationCacheDirectory();
    final dir = Directory(p.join(appDir.path, 'local_covers'));
    // create(recursive: true) is idempotent — no need for an existsSync
    // pre-check, which is also racy against a concurrent scan.
    await dir.create(recursive: true);
    return dir.path;
  }

  /// Generate a stable filename for cover art cache from the file URI.
  ///
  /// Dart's `String.hashCode` is a 32-bit value, so by the birthday
  /// paradox two distinct URIs collide with ~50% probability around
  /// 65k tracks — well within "a serious music library" territory.
  /// SHA-1 truncated to 16 hex chars (64 bits) pushes the 50% collision
  /// threshold past 2 ^ 32 entries, which we will never hit.
  String _coverFilename(String uri) {
    final digest = sha1.convert(utf8.encode(uri)).toString();
    return '${digest.substring(0, 16)}.jpg';
  }

  /// Derive a title from the filename (strip extension, replace underscores).
  String _titleFromFilename(String filename) {
    final withoutExt = p.basenameWithoutExtension(filename);
    // Strip leading track numbers like "01 - " or "01. "
    final stripped = withoutExt.replaceFirst(RegExp(r'^\d{1,3}[\s._-]+'), '');
    return stripped.replaceAll('_', ' ').trim();
  }
}
