/// Strategy interface for extracting a track ID from an mpv stream URI.
///
/// Each [MusicBackend] implementation uses a different URL format; this
/// interface allows [AfQueueManager] to remain backend-agnostic.
///
/// All implementations must be stateless — this is called synchronously
/// on the mpv playlist sync hot path.
abstract class TrackIdExtractor {
  const TrackIdExtractor();

  /// Extract a track ID from [uri], or `null` when the format is
  /// unrecognized. Must not perform IO.
  String? extractId(String uri);
}

/// Extracts track IDs from Jellyfin stream URLs.
///
/// Handles formats:
///   - `/Audio/{id}/stream` (path segment after `/Audio/`)
///   - `/Audio/{id}/stream?static=true`
///   - `?id={trackId}` (fallback query-parameter lookup)
///
/// This is the default extractor used by [AfQueueManager] and preserves
/// the exact logic of the original `AfQueueManager._extractTrackId`.
class JellyfinTrackIdExtractor extends TrackIdExtractor {
  const JellyfinTrackIdExtractor();

  @override
  String? extractId(String uri) {
    final parsed = Uri.tryParse(uri);
    if (parsed == null) return null;

    final segments = parsed.pathSegments;
    for (var i = 0; i < segments.length - 1; i++) {
      if (segments[i].toLowerCase() == 'audio') {
        return segments[i + 1];
      }
    }

    final queryId = parsed.queryParameters['id'];
    if (queryId != null && queryId.isNotEmpty) return queryId;
    return null;
  }
}

/// Extracts track IDs from Subsonic/Navidrome stream URLs.
///
/// Subsonic stream URLs use the format:
///   - `/rest/stream.view?id={trackId}&u=user&t=token`
///   - `/rest/getCoverArt.view?id={trackId}`
///
/// Only the `id` query parameter is used — path segments are ignored.
class SubsonicTrackIdExtractor extends TrackIdExtractor {
  const SubsonicTrackIdExtractor();

  @override
  String? extractId(String uri) {
    final parsed = Uri.tryParse(uri);
    if (parsed == null) return null;

    final queryId = parsed.queryParameters['id'];
    if (queryId != null && queryId.isNotEmpty) return queryId;
    return null;
  }
}

/// Extracts track IDs from local file/system URIs.
///
/// Handles:
///   - `content://media/external/audio/media/{id}` — last path segment
///   - `file:///storage/music/track.flac` — the full URI
///   - Plain absolute paths — the full string
///
/// For local mode the URI itself is the identity key, so returning the
/// full URI for file:/// and path URIs is correct — [AfQueueManager]'s
/// `_urlToTrack` map resolves them by equality.
class LocalTrackIdExtractor extends TrackIdExtractor {
  const LocalTrackIdExtractor();

  @override
  String? extractId(String uri) {
    if (uri.isEmpty) return null;

    final parsed = Uri.tryParse(uri);
    if (parsed != null && parsed.scheme == 'content') {
      final segments = parsed.pathSegments;
      if (segments.isNotEmpty) {
        return segments.last;
      }
    }

    // For file:// and plain paths, return the URI as-is — it's the key
    // into _urlToTrack.
    return uri;
  }
}
