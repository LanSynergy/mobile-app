import 'dart:io';

import 'package:mpv_audio_kit/mpv_audio_kit.dart' show CoverArt;
import 'package:path_provider/path_provider.dart';

import '../../utils/log.dart';
import '../jellyfin/models/items.dart';

/// Manages cover art persistence and notification artwork download.
///
/// Handles two sources of cover art:
/// 1. mpv's `coverArt` stream (embedded audio file art) → persisted to temp file
/// 2. Remote artwork URLs → downloaded to temp file for notification display
///
/// Optimizations implemented:
/// - Shared HttpClient across all instances
/// - Two-level caching (memory + disk)
/// - LRU eviction for memory cache
/// - Disk cache with TTL and size limits
///
/// Tracks the latest cover path so [artUri] always returns the current best
/// available artwork URI for native notification updates.
class AfArtworkManager {
  /// Shared HttpClient instance for all AfArtworkManager instances
  /// This reduces memory overhead and enables connection reuse
  static final HttpClient _sharedHttpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..idleTimeout = const Duration(seconds: 15);

  /// Maximum memory cache entries
  static const int _memoryCacheSize = 50;

  /// Maximum disk cache size in bytes (100MB)
  static const int _diskCacheSizeBytes = 100 * 1024 * 1024;

  /// Cache TTL
  static const Duration _cacheTTL = Duration(days: 7);

  /// Maximum number of disk cache files
  static const int _maxDiskCacheFiles = 200;

  /// Cleans up orphan `.tmp` files left behind by aborted or crashed
  /// [persistCover] / [downloadArtworkForNotification] calls.
  ///
  /// Should be called once at app startup to reclaim disk space from
  /// interrupted writes. Scans [Directory.systemTemp] for files matching
  /// the `aetherfin_*.tmp` pattern and removes them.
  static Future<void> cleanupOrphanTempFiles() async {
    try {
      final tmpDir = Directory.systemTemp;
      final orphans = <File>[];
      await for (final entity in tmpDir.list()) {
        if (entity is File) {
          final name = entity.uri.pathSegments.last;
          if (name.startsWith('aetherfin_') && name.endsWith('.tmp')) {
            orphans.add(entity);
          }
        }
      }
      if (orphans.isEmpty) return;
      for (final f in orphans) {
        try {
          await f.delete();
        } catch (_) {
          // Best-effort; another process may have already deleted it.
        }
      }
    } catch (_) {
      // Best-effort; directory may not be accessible.
    }
  }

  /// Called when artwork is persisted or downloaded so the owner can
  /// update the native notification artwork.
  void Function()? onArtworkChanged;

  int _coverCounter = 0;
  String? _coverPath;
  String? _networkCoverPath;
  Map<String, String> _authHeaders = const <String, String>{};
  String? _networkCoverTrackId;
  bool _disposed = false;

  /// Memory cache: trackId -> file path
  final Map<String, String> _memoryCache = {};

  /// Set of trackIds whose disk cache file has been confirmed to exist.
  /// Avoids repeated `existsSync()` + `statSync()` calls in the hot path.
  final Set<String> _diskCacheChecked = {};

  /// Disk cache directory
  String? _diskCacheDir;

  /// Track disk cache size
  int _diskCacheSize = 0;

  /// Update the auth headers used for authenticated artwork downloads.
  void setAuthHeaders(Map<String, String> headers) {
    _authHeaders = headers;
  }

  /// Returns the best available artwork URI for the given track, or `null`
  /// when neither local nor remote cover is ready.
  Uri? artUri(AfTrack track) {
    // Check memory cache first
    if (_memoryCache.containsKey(track.id)) {
      return Uri.file(_memoryCache[track.id]!);
    }

    // Check embedded cover art from mpv
    if (_coverPath != null) {
      return Uri.file(_coverPath!);
    }

    // Check network cover for this specific track
    if (_networkCoverPath != null && _networkCoverTrackId == track.id) {
      return Uri.file(_networkCoverPath!);
    }

    // Check disk cache
    final diskCached = _getDiskCachedPath(track.id);
    if (diskCached != null) {
      return Uri.file(diskCached);
    }

    // Fallback to track's image URL if it's a local file
    if (track.imageUrl != null && track.imageUrl!.startsWith('file://')) {
      return Uri.parse(track.imageUrl!);
    }

    return null;
  }

  /// Returns `true` when a remote artwork download is needed for this track.
  bool needsRemoteArtwork(AfTrack track) =>
      track.imageUrl != null &&
      !track.imageUrl!.startsWith('file://') &&
      !(_networkCoverTrackId == track.id && _networkCoverPath != null) &&
      !_memoryCache.containsKey(track.id) &&
      _getDiskCachedPath(track.id) == null;

  /// Persist embedded cover art from mpv's `coverArt` stream to a temp file.
  Future<void> persistCover(CoverArt? raw) async {
    if (_disposed) return;
    if (raw == null) {
      _coverPath = null;
      return;
    }

    final ext = raw.extension.isNotEmpty ? raw.extension : 'jpg';
    final tmpDir = Directory.systemTemp.path;
    final path =
        '$tmpDir${Platform.pathSeparator}aetherfin_cover_${++_coverCounter}.$ext';

    try {
      final tmpPath = '$path.tmp';
      await File(tmpPath).writeAsBytes(raw.bytes);

      if (_coverPath != null) {
        final prev = File(_coverPath!);
        if (await prev.exists()) {
          await prev.delete();
        }
      }

      await File(tmpPath).rename(path);
      _coverPath = path;

      _networkCoverPath = null;
      _networkCoverTrackId = null;

      // Don't clear memory cache — _coverPath is checked first in artUri()
      // (step 2) before the memory cache (step 1), so entries for other
      // tracks are preserved for fast back-navigation.

      onArtworkChanged?.call();
    } catch (e) {
      afLog('audio', 'cover art persist failed', error: e);
    }
  }

  /// Initialize disk cache directory
  Future<void> _initDiskCache() async {
    if (_diskCacheDir != null) return;

    try {
      final cacheDir = await getApplicationCacheDirectory();
      _diskCacheDir = '${cacheDir.path}${Platform.pathSeparator}artwork_cache';
      final dir = Directory(_diskCacheDir!);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      // Clean up expired files on startup
      _cleanupExpiredCache();
    } catch (e) {
      afLog('audio', 'Failed to initialize disk cache', error: e);
    }
  }

  /// Get path for disk cached artwork
  ///
  /// Uses [_diskCacheChecked] to avoid redundant `existsSync()` + `statSync()`
  /// calls on confirmed-cached files. If the file was evicted between checks,
  /// the stale entry is removed from the set and the method falls back to a
  /// full stat cycle.
  String? _getDiskCachedPath(String trackId) {
    if (_diskCacheDir == null) return null;
    final cachePath = '$_diskCacheDir/$trackId';

    // Fast path: file was confirmed to exist in a prior call.
    // Still verify with existsSync in case LRU eviction removed it.
    if (_diskCacheChecked.contains(trackId)) {
      if (File(cachePath).existsSync()) {
        return cachePath;
      }
      // Stale entry — remove from set, fall through to full check.
      _diskCacheChecked.remove(trackId);
    }

    final cacheFile = File(cachePath);
    if (cacheFile.existsSync()) {
      try {
        final stat = cacheFile.statSync();
        final ageDays = DateTime.now().difference(stat.modified).inDays;
        if (ageDays <= _cacheTTL.inDays) {
          _diskCacheChecked.add(trackId);
          return cacheFile.path;
        } else {
          // Expired, delete
          cacheFile.deleteSync();
          _diskCacheChecked.remove(trackId);
        }
      } catch (e) {
        afLog('audio', 'Failed to check disk cache for $trackId', error: e);
      }
    }
    return null;
  }

  /// Clean up expired disk cache files
  void _cleanupExpiredCache() {
    if (_diskCacheDir == null) return;
    try {
      final dir = Directory(_diskCacheDir!);
      final now = DateTime.now();
      final threshold = now.subtract(_cacheTTL);

      for (final entity in dir.listSync()) {
        if (entity is File) {
          try {
            final stat = entity.statSync();
            if (stat.modified.isBefore(threshold)) {
              final size = stat.size;
              entity.deleteSync();
              _diskCacheSize -= size;
              afLog('audio', 'Cleaned up expired cache file: ${entity.path}');
            }
          } catch (e) {
            afLog(
              'audio',
              'Failed to clean up cache file: ${entity.path}',
              error: e,
            );
          }
        }
      }

      // Enforce size limit
      _enforceCacheSizeLimit();
    } catch (e) {
      afLog('audio', 'Cache cleanup failed', error: e);
    }
  }

  /// Enforce disk cache size limit by removing oldest files
  void _enforceCacheSizeLimit() {
    if (_diskCacheDir == null) return;

    try {
      final dir = Directory(_diskCacheDir!);
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => !f.path.endsWith('.tmp'))
          .toList();

      // Sort by modification time (oldest first)
      files.sort(
        (a, b) => a.statSync().modified.compareTo(b.statSync().modified),
      );

      while (_diskCacheSize > _diskCacheSizeBytes ||
          files.length > _maxDiskCacheFiles) {
        if (files.isEmpty) break;
        final oldest = files.removeAt(0);
        try {
          final size = oldest.lengthSync();
          oldest.deleteSync();
          _diskCacheSize -= size;
          afLog('audio', 'Evicted oldest cache file to enforce size limit');
        } catch (e) {
          afLog(
            'audio',
            'Failed to evict cache file: ${oldest.path}',
            error: e,
          );
        }
      }
    } catch (e) {
      afLog('audio', 'Failed to enforce cache size limit', error: e);
    }
  }

  /// Download artwork from a remote URL for use in the notification/ lockscreen.
  Future<void> downloadArtworkForNotification(AfTrack track) async {
    if (_disposed) return;

    await _initDiskCache();

    final imageUrl = track.imageUrl;
    if (imageUrl == null || imageUrl.isEmpty) return;

    // Check memory cache first
    if (_memoryCache.containsKey(track.id)) {
      _networkCoverTrackId = track.id;
      _networkCoverPath = _memoryCache[track.id];
      onArtworkChanged?.call();
      return;
    }

    // Check disk cache
    final diskCached = _getDiskCachedPath(track.id);
    if (diskCached != null) {
      _networkCoverTrackId = track.id;
      _networkCoverPath = diskCached;
      _memoryCache[track.id] = diskCached;
      // Enforce memory cache size
      if (_memoryCache.length > _memoryCacheSize) {
        _memoryCache.remove(_memoryCache.keys.first);
      }
      onArtworkChanged?.call();
      return;
    }

    // Check if it's a local file
    if (imageUrl.startsWith('file://')) {
      _networkCoverTrackId = track.id;
      _networkCoverPath = imageUrl.substring('file://'.length);
      _memoryCache[track.id] = _networkCoverPath!;
      onArtworkChanged?.call();
      return;
    }

    try {
      final uri = Uri.parse(imageUrl);
      final request = await _sharedHttpClient.getUrl(uri);
      _authHeaders.forEach((key, value) {
        request.headers.set(key, value);
      });

      final response = await request.close();
      if (response.statusCode != 200) {
        await response.drain<int>(0);
        return;
      }

      final contentType = response.headers.contentType;
      var ext = 'jpg';
      if (contentType != null && contentType.subType.isNotEmpty) {
        ext = contentType.subType == 'jpeg' ? 'jpg' : contentType.subType;
      }

      final path = '$_diskCacheDir/${track.id}.$ext';

      final tmpPath = '$path.tmp';
      final tmpFile = File(tmpPath);
      final sink = tmpFile.openWrite();
      try {
        await response.pipe(sink);
      } finally {
        await sink.close();
      }

      if (_disposed) return;

      if (_networkCoverPath != null) {
        try {
          final prev = File(_networkCoverPath!);
          if (await prev.exists()) await prev.delete();
        } catch (_) {}
      }

      // Do NOT delete _coverPath here. Embedded cover art from mpv's
      // `coverArt` stream is higher quality than network thumbnails and
      // must be preserved. The network download is a fallback for tracks
      // that lack embedded art — deleting _coverPath would cause the
      // notification artwork to flicker between sources.

      await tmpFile.rename(path);

      // Update cache tracking
      final fileSize = (await File(path).stat()).size;
      _diskCacheSize += fileSize;

      // Enforce cache limits
      _enforceCacheSizeLimit();

      _networkCoverPath = path;
      _networkCoverTrackId = track.id;

      // Add to memory cache
      _memoryCache[track.id] = path;
      if (_memoryCache.length > _memoryCacheSize) {
        _memoryCache.remove(_memoryCache.keys.first);
      }

      onArtworkChanged?.call();
    } catch (e) {
      afLog('audio', 'artwork download for notification failed', error: e);
    }
  }

  /// Clears all artwork caches
  Future<void> clearCache() async {
    _memoryCache.clear();
    if (_diskCacheDir != null) {
      try {
        final dir = Directory(_diskCacheDir!);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
          await dir.create(recursive: true);
          _diskCacheSize = 0;
        }
      } catch (e) {
        afLog('audio', 'Failed to clear disk cache', error: e);
      }
    }
    _coverPath = null;
    _networkCoverPath = null;
    _networkCoverTrackId = null;
  }

  void dispose() {
    _disposed = true;
    // Note: We don't close the shared HttpClient as it's static
    // and shared across all instances
  }
}
