import 'dart:io';

import 'package:mpv_audio_kit/mpv_audio_kit.dart' show CoverArt;

import '../../utils/log.dart';
import '../jellyfin/models/items.dart';

/// Manages cover art persistence and notification artwork download.
///
/// Handles two sources of cover art:
/// 1. mpv's `coverArt` stream (embedded audio file art) → persisted to temp file
/// 2. Remote artwork URLs → downloaded to temp file for notification display
///
/// Tracks the latest cover path so [artUri] always returns the current best
/// available artwork URI for [mediaItem] updates.
class AfArtworkManager {
  /// Called when artwork is persisted or downloaded so the owner can
  /// update the [MediaItem] / notification artwork.
  void Function()? onArtworkChanged;

  int _coverCounter = 0;
  String? _coverPath;
  String? _networkCoverPath;
  static final HttpClient _httpClient = HttpClient();
  Map<String, String> _authHeaders = const <String, String>{};
  String? _networkCoverTrackId;
  bool _disposed = false;

  /// Update the auth headers used for authenticated artwork downloads.
  void setAuthHeaders(Map<String, String> headers) {
    _authHeaders = headers;
  }

  /// Returns the best available artwork URI for the given track, or `null`
  /// when neither local nor remote cover is ready.
  Uri? artUri(AfTrack track) {
    if (_coverPath != null) {
      return Uri.file(_coverPath!);
    }
    if (_networkCoverPath != null && _networkCoverTrackId == track.id) {
      return Uri.file(_networkCoverPath!);
    }
    if (track.imageUrl != null && track.imageUrl!.startsWith('file://')) {
      return Uri.parse(track.imageUrl!);
    }
    return null;
  }

  /// Returns `true` when a remote artwork download is needed for this track.
  bool needsRemoteArtwork(AfTrack track) =>
      track.imageUrl != null &&
      !track.imageUrl!.startsWith('file://') &&
      !(_networkCoverTrackId == track.id && _networkCoverPath != null);

  /// Persist embedded cover art from mpv's `coverArt` stream to a temp file.
  Future<void> persistCover(CoverArt? raw) async {
    if (_disposed) return;
    if (raw == null) {
      _coverPath = null;
      return;
    }

    final ext = raw.extension.isNotEmpty ? raw.extension : 'jpg';
    final id = ++_coverCounter;
    final tmpDir = Directory.systemTemp.path;
    final path = '$tmpDir${Platform.pathSeparator}aetherfin_cover_$id.$ext';

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
    } catch (e) {
      afLog('audio', 'cover art persist failed', error: e);
    }
  }

  /// Download artwork from a remote URL for use in the notification/ lockscreen.
  Future<void> downloadArtworkForNotification(AfTrack track) async {
    if (_disposed) return;
    final imageUrl = track.imageUrl;
    if (imageUrl == null || imageUrl.isEmpty) return;
    if (_networkCoverTrackId == track.id && _networkCoverPath != null) return;

    if (imageUrl.startsWith('file://')) {
      _networkCoverTrackId = track.id;
      _networkCoverPath = imageUrl.substring('file://'.length);
      return;
    }

    try {
      final uri = Uri.parse(imageUrl);
      final request = await _httpClient.getUrl(uri);
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

      final id = ++_coverCounter;
      final tmpDir = Directory.systemTemp.path;
      final path = '$tmpDir${Platform.pathSeparator}aetherfin_notif_$id.$ext';

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

      if (_coverPath != null) {
        try {
          final prev = File(_coverPath!);
          if (await prev.exists()) await prev.delete();
        } catch (_) {}
      }

      await tmpFile.rename(path);

      _networkCoverPath = path;
      _networkCoverTrackId = track.id;
      onArtworkChanged?.call();
    } catch (e) {
      afLog('audio', 'artwork download for notification failed', error: e);
    }
  }

  void dispose() {
    _disposed = true;
  }
}
