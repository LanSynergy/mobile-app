import 'dart:convert';
import 'dart:io';

import '../../utils/log.dart';

/// Manages a local cover art cache with LRU eviction.
///
/// Tracks access timestamps via a metadata JSON file inside the cache
/// directory. On eviction, the least-recently-accessed files are deleted
/// until total size is below the configured maximum.
///
/// Thread-safe for reads; writes go through sync I/O which is acceptable
/// because all callers (scanner, display) already use sync patterns for
/// cover files.
class CoverCacheManager {
  final String _cacheDir;
  final int _maxBytes;
  final String _metaPath;

  static const int _kDefaultMaxBytes = 100 * 1024 * 1024; // 100 MB

  Map<String, int> _accessTimestamps = {};
  bool _dirty = false;

  /// Create manager with cache at [cacheDir] and max size [maxBytes].
  CoverCacheManager({
    required String cacheDir,
    int maxBytes = _kDefaultMaxBytes,
  })  : _cacheDir = cacheDir,
        _maxBytes = maxBytes,
        _metaPath = '$cacheDir${Platform.pathSeparator}_access_meta.json' {
    _loadMeta();
  }

  // ── Metadata persistence ──────────────────────────────────────────────

  void _loadMeta() {
    final file = File(_metaPath);
    if (!file.existsSync()) return;
    try {
      final content = file.readAsStringSync();
      final decoded = jsonDecode(content) as Map<String, dynamic>;
      _accessTimestamps = decoded.map(
        (k, v) => MapEntry(k, (v as num).toInt()),
      );
    } catch (e) {
      afLog('local', 'failed to load cover cache meta', error: e);
      _accessTimestamps = {};
    }
  }

  void _saveMeta() {
    if (!_dirty) return;
    try {
      File(_metaPath).writeAsStringSync(jsonEncode(_accessTimestamps));
      _dirty = false;
    } catch (e) {
      afLog('local', 'failed to save cover cache meta', error: e);
    }
  }

  // ── Public API ────────────────────────────────────────────────────────

  /// Record an access to the cover at [path].
  ///
  /// This should be called whenever a cached cover file is created or
  /// read, so that the eviction order reflects actual usage.
  void trackAccess(String path) {
    _accessTimestamps[path] = DateTime.now().millisecondsSinceEpoch;
    _dirty = true;
  }

  /// Evict least-recently-accessed files until total size <= maxBytes.
  ///
  /// Returns the number of files deleted, or 0 if no eviction was needed.
  int evictIfNeeded() {
    final cacheDir = Directory(_cacheDir);
    if (!cacheDir.existsSync()) return 0;

    final files = cacheDir.listSync().whereType<File>().toList();
    int totalSize = 0;
    for (final f in files) {
      // Skip the metadata file itself
      if (f.path == _metaPath) continue;
      totalSize += f.lengthSync();
    }

    if (totalSize <= _maxBytes) return 0;

    // Sort by access timestamp (oldest first). Files with no recorded
    // access (timestamp 0) are treated as oldest.
    files.sort((a, b) {
      if (a.path == _metaPath) return 1;
      if (b.path == _metaPath) return -1;
      final aTime = _accessTimestamps[a.path] ?? 0;
      final bTime = _accessTimestamps[b.path] ?? 0;
      return aTime.compareTo(bTime);
    });

    int deleted = 0;
    for (final f in files) {
      if (totalSize <= _maxBytes) break;
      if (f.path == _metaPath) continue;
      final len = f.lengthSync();
      try {
        f.deleteSync();
        _accessTimestamps.remove(f.path);
        totalSize -= len;
        deleted++;
      } catch (e) {
        afLog('local', 'failed to delete cover cache file', error: e);
      }
    }

    _dirty = true;
    _saveMeta();
    return deleted;
  }

  /// Remove all cached covers and reset the access log.
  void clear() {
    final cacheDir = Directory(_cacheDir);
    if (cacheDir.existsSync()) {
      for (final entity in cacheDir.listSync()) {
        if (entity is File && entity.path != _metaPath) {
          try {
            entity.deleteSync();
          } catch (_) {}
        }
      }
    }
    _accessTimestamps.clear();
    _dirty = true;
    _saveMeta();
  }

  /// Remove entries from the access log whose files no longer exist.
  ///
  /// Call this after external deletion (e.g., user clearing app data) to
  /// keep the metadata file consistent with on-disk state.
  void pruneStaleEntries() {
    final before = _accessTimestamps.length;
    _accessTimestamps.removeWhere((path, _) => !File(path).existsSync());
    if (_accessTimestamps.length != before) {
      _dirty = true;
      _saveMeta();
    }
  }
}
