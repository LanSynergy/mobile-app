import 'dart:convert' show utf8;
import 'dart:io';
import 'dart:math' show min;

import 'package:crypto/crypto.dart' show sha1;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../utils/log.dart';
import 'cover_cache_manager.dart';
import 'local_db.dart';
import 'saf_picker.dart';

/// Orchestrates scanning SAF folders: lists files → reads metadata → inserts
/// into the local SQLite database. Reports progress via a callback.
class MetadataScanner {
  MetadataScanner(this.db);
  final LocalDb db;
  bool _isScanning = false;
  CoverCacheManager? _coverCacheManager;

  /// Check scanning state to allow UI buttons to show progress or disable themselves.
  bool get isScanning => _isScanning;

  /// Scan a folder tree URI. Calls [onProgress] with (completed, total).
  /// Returns the number of tracks inserted/updated.
  Future<int> scanFolder(
    String treeUri, {
    void Function(int completed, int total)? onProgress,
  }) async {
    if (_isScanning) {
      afLog('local', 'scanFolder bypassed: scan already in progress');
      return 0;
    }

    _isScanning = true;
    try {
      afLog('local', 'scanFolder start: $treeUri');

      // 1. List all audio files
      final files = await SafPicker.listAudioFiles(treeUri);
      afLog('local', 'found ${files.length} audio files');

      if (files.isEmpty) return 0;

      int completed = 0;
      int inserted = 0;
      final coverCacheDir = await _coverCacheDir();
      _coverCacheManager ??= await CoverCacheManager.create(
        cacheDir: coverCacheDir,
      );

      // 2. Batch-load scan info for all files in this folder,
      //    replacing N per-file DB queries with a single SELECT.
      final prefix = treeUri.endsWith('/') ? treeUri : '$treeUri/';
      final scanInfo = await db.getTrackScanInfoByPrefix(prefix);

      // 3. Process in chunks: metadata reads fire concurrently per chunk
      //    (MethodChannel calls are independent), cover art + disk writes
      //    remain sequential. DB batch writes stay sequential (SQLite single-writer).
      const chunkSize = 10;
      final batch = <Map<String, dynamic>>[];

      for (var i = 0; i < files.length; i += chunkSize) {
        final end = min(i + chunkSize, files.length);
        final chunk = files.sublist(i, end);

        // Separate files that need processing from those already cached.
        // Retry cover art extraction for files whose lastModified matches
        // but cover_path was null OR the cover file was evicted from disk.
        final toProcess = <SafFile>[];
        final coverOnly = <SafFile>[];
        for (final file in chunk) {
          final info = scanInfo[file.uri];
          if (info != null && info.lastModified == file.lastModified) {
            if (!info.hasCover) {
              // Metadata OK but cover art missing — retry cover extraction only.
              coverOnly.add(file);
            } else if (info.hasCover) {
              // DB says cover exists — verify file is actually on disk.
              final coverFile = File(
                p.join(coverCacheDir, _coverFilename(file.uri)),
              );
              if (!await coverFile.exists()) {
                // Cover evicted from disk but DB is stale — retry extraction.
                coverOnly.add(file);
              }
            }
            completed++;
            onProgress?.call(completed, files.length);
            continue;
          }
          toProcess.add(file);
        }

        if (toProcess.isEmpty && coverOnly.isEmpty) continue;

        // Retry cover art extraction for files that have metadata but
        // are missing cover art (extraction failed on a previous scan).
        for (final file in coverOnly) {
          final coverFile = File(
            p.join(coverCacheDir, _coverFilename(file.uri)),
          );
          if (await coverFile.exists()) {
            // File exists on disk — just make sure DB points to it.
            await db.updateCoverPath(file.uri, coverFile.path);
            _coverCacheManager?.trackAccess(coverFile.path);
            continue;
          }
          try {
            final artBytes = await SafPicker.readCoverArt(file.uri);
            if (artBytes != null && artBytes.isNotEmpty) {
              await coverFile.writeAsBytes(artBytes);
              // Update ONLY cover_path — don't corrupt the rest of the row.
              await db.updateCoverPath(file.uri, coverFile.path);
              _coverCacheManager?.trackAccess(coverFile.path);
              afLog('local', 'cover art recovered for ${file.name}');
            }
          } catch (e, stack) {
            afLog(
              'local',
              'cover art retry failed for ${file.name}',
              error: e,
              stackTrace: stack,
            );
          }
        }

        if (toProcess.isEmpty) continue;

        // Fire all metadata reads concurrently within this chunk.
        final results = await Future.wait(
          toProcess.map(
            (f) => SafPicker.readMetadata(f.uri).then(
              (m) => _ChunkResult(f, m),
              onError: (Object e, StackTrace stack) {
                afLog(
                  'local',
                  'metadata read failed for ${f.name}',
                  error: e,
                  stackTrace: stack,
                );
                return _ChunkResult(f, null);
              },
            ),
          ),
        );

        // Process results sequentially: cover art reads/writes + batch build.
        for (final result in results) {
          final file = result.file;
          final meta = result.meta;

          if (meta != null) {
            final title = meta.title?.isNotEmpty == true
                ? meta.title!
                : _titleFromFilename(file.name);

            // Extract cover art (if not already cached)
            String? coverPath;
            final coverFile = File(
              p.join(coverCacheDir, _coverFilename(file.uri)),
            );
            if (!await coverFile.exists()) {
              final artBytes = await SafPicker.readCoverArt(file.uri);
              if (artBytes != null && artBytes.isNotEmpty) {
                await coverFile.writeAsBytes(artBytes);
                coverPath = coverFile.path;
                _coverCacheManager?.trackAccess(coverFile.path);
              }
            } else {
              coverPath = coverFile.path;
              _coverCacheManager?.trackAccess(coverFile.path);
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
          }

          completed++;
          onProgress?.call(completed, files.length);

          // Flush batch every 50 tracks
          if (batch.length >= 50) {
            await db.upsertTracks(batch);
            batch.clear();
          }
        }
      }

      // Flush remaining
      if (batch.isNotEmpty) {
        await db.upsertTracks(batch);
      }

      // Evict old covers if cache exceeds size limit, then null out
      // DB cover_path for evicted files so re-scan can re-extract.
      final evicted = await _coverCacheManager?.evictIfNeeded() ?? [];
      if (evicted.isNotEmpty) {
        afLog('local', 'evicted ${evicted.length} stale cover art files');
        // Build a set of evicted paths for O(1) lookup.
        final evictedSet = evicted.toSet();
        // Null out cover_path for tracks whose cover was evicted.
        // Query all tracks with cover_path and check each.
        await db.clearEvictedCoverPaths(evictedSet);
      }

      afLog('local', 'scanFolder done: $inserted tracks inserted/updated');
      return inserted;
    } finally {
      _isScanning = false;
    }
  }

  /// Remove tracks from DB that no longer exist on disk for a given folder.
  ///
  /// Membership test: SAF document URIs for files inside [treeUri] always
  /// take the form `<treeUri>/document/<encodedDocId>`, so we test for the
  /// `<treeUri>/` boundary instead of a raw `startsWith(treeUri)`.
  ///
  /// Without the trailing slash, two sibling folders whose tree URIs share
  /// a prefix — e.g. `…/tree/primary%3AMusic` and
  /// `…/tree/primary%3AMusic2` — would alias: pruning Music would treat
  /// all of Music2's documents as candidates, never find them in
  /// Music's directory listing, and silently delete them from the DB.
  Future<int> pruneDeletedFiles(String treeUri) async {
    final files = await SafPicker.listAudioFiles(treeUri);
    final existingUris = files.map((f) => f.uri).toSet();
    final prefix = treeUri.endsWith('/') ? treeUri : '$treeUri/';

    final trackIds = await db.trackIdsByPrefix(prefix);
    final idsToDelete = <String>[];
    for (final id in trackIds) {
      if (!existingUris.contains(id)) {
        idsToDelete.add(id);
      }
    }
    if (idsToDelete.isEmpty) return 0;
    await db.deleteTracksByIds(idsToDelete);
    final pruned = idsToDelete.length;
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

/// Holds a file together with its metadata result from a concurrent read.
class _ChunkResult {
  _ChunkResult(this.file, this.meta);
  final SafFile file;
  final SafMetadata? meta;
}
