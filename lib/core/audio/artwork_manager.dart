import 'dart:io';

import 'package:mpv_audio_kit/mpv_audio_kit.dart' show CoverArt;

import '../../utils/log.dart';
import '../jellyfin/models/items.dart';
import 'artwork_disk_cache.dart';

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
/// - Disk cache with TTL and size limits (delegated to [ArtworkDiskCache])
///
/// Tracks the latest cover path so [artUri] always returns the current best
/// available artwork URI for native notification updates.
class AfArtworkManager {
  /// Shared HttpClient instance for all AfArtworkManager instances
  static final HttpClient _sharedHttpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..idleTimeout = const Duration(seconds: 15);

  /// Maximum memory cache entries
  static const int _memoryCacheSize = 50;

  /// Cleans up orphan `.tmp` files left behind by aborted or crashed
  /// [persistCover] / [downloadArtworkForNotification] calls.
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
        } catch (_) {}
      }
    } catch (_) {}
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

  /// Disk cache (delegates to [ArtworkDiskCache] for persistence).
  final ArtworkDiskCache _diskCache = ArtworkDiskCache();

  /// Update the auth headers used for authenticated artwork downloads.
  void setAuthHeaders(Map<String, String> headers) {
    _authHeaders = headers;
  }

  /// Returns the best available artwork URI for the given track, or `null`
  /// when neither local nor remote cover is ready.
  Uri? artUri(AfTrack track) {
    if (_coverPath != null) return Uri.file(_coverPath!);
    if (_memoryCache.containsKey(track.id)) {
      return Uri.file(_memoryCache[track.id]!);
    }
    if (_networkCoverPath != null && _networkCoverTrackId == track.id) {
      return Uri.file(_networkCoverPath!);
    }
    final diskCached = _diskCache.getPath(track.id);
    if (diskCached != null) return Uri.file(diskCached);
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
      _diskCache.getPath(track.id) == null;

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
      onArtworkChanged?.call();
    } on Exception catch (e, stack) {
      afLog('audio', 'cover art persist failed', error: e, stackTrace: stack);
    }
  }

  /// Download artwork from a remote URL for use in the notification/
  /// lockscreen.
  Future<void> downloadArtworkForNotification(AfTrack track) async {
    if (_disposed) return;
    await _diskCache.init();

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
    final diskCached = _diskCache.getPath(track.id);
    if (diskCached != null) {
      _networkCoverTrackId = track.id;
      _networkCoverPath = diskCached;
      _memoryCache[track.id] = diskCached;
      if (_memoryCache.length > _memoryCacheSize) {
        _memoryCache.remove(_memoryCache.keys.first);
      }
      onArtworkChanged?.call();
      return;
    }

    // Local file:// URL
    if (imageUrl.startsWith('file://')) {
      _networkCoverTrackId = track.id;
      _networkCoverPath = imageUrl.substring('file://'.length);
      _memoryCache[track.id] = _networkCoverPath!;
      onArtworkChanged?.call();
      return;
    }

    // Download from remote URL
    final path = await _diskCache.downloadFromUrl(
      track.id,
      imageUrl,
      _authHeaders,
      _sharedHttpClient,
    );
    if (path == null || _disposed) return;

    if (_networkCoverPath != null) {
      try {
        final prev = File(_networkCoverPath!);
        if (await prev.exists()) await prev.delete();
      } on Exception catch (_) {}
    }

    _networkCoverPath = path;
    _networkCoverTrackId = track.id;
    _memoryCache[track.id] = path;
    if (_memoryCache.length > _memoryCacheSize) {
      _memoryCache.remove(_memoryCache.keys.first);
    }
    onArtworkChanged?.call();
  }

  /// Clears all artwork caches
  Future<void> clearCache() async {
    _memoryCache.clear();
    await _diskCache.clear();
    _coverPath = null;
    _networkCoverPath = null;
    _networkCoverTrackId = null;
  }

  void dispose() {
    _disposed = true;
    _memoryCache.clear();
    _diskCache.resetTracking();
  }
}
