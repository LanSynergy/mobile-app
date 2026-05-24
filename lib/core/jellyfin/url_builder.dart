import '../../utils/url.dart';

/// Builds Jellyfin URLs, auth headers, and streaming URLs.
///
/// Extracted from [JellyfinClient] so URL-building logic is testable
/// independently of the HTTP layer.
class JellyfinUrlBuilder {

  JellyfinUrlBuilder({
    required this.baseUrl,
    required this.deviceId,
    required this.clientVersion,
    this.accessToken,
    this.userId,
  });
  final String baseUrl;
  final String? accessToken;
  final String? userId;
  final String deviceId;
  final String clientVersion;

  void assertUser() {
    if (userId == null || userId!.isEmpty) {
      throw StateError(
        'JellyfinUrlBuilder.userId is null — endpoint requires authentication.',
      );
    }
  }

  /// Headers callers can use to authenticate ad-hoc requests that bypass
  /// the Dio instance — e.g. the audio source URI given to just_audio, or
  /// a CachedNetworkImage that fetches an artwork-protected endpoint.
  Map<String, String> get authHeaders {
    final headers = <String, String>{
      'User-Agent': userAgentFor(clientVersion),
      'Accept': '*/*',
    };
    if (accessToken != null) {
      headers['Authorization'] = buildAuthHeader(
        deviceId: deviceId,
        token: accessToken,
        userId: userId,
        clientVersion: clientVersion,
      );
    }
    return headers;
  }

  String trackStreamUrl(
    String trackId, {
    int? maxBitrateKbps,
    String? deviceProfileId,
  }) {
    assertUser();
    final qp = <String, String>{
      'Static': 'true',
      'UserId': userId!,
      'DeviceId': deviceId,
      if (accessToken != null && accessToken!.isNotEmpty)
        'api_key': accessToken!,
      if (maxBitrateKbps != null)
        'MaxStreamingBitrate': '${maxBitrateKbps * 1000}',
      // ignore: use_null_aware_elements — map is Map<String,String>, value is String?
      if (deviceProfileId != null) 'DeviceProfileId': deviceProfileId,
    };
    final baseUri = Uri.parse(stripTrailingSlash(baseUrl));
    return baseUri
        .replace(
          path: '${baseUri.path}/Audio/$trackId/stream',
          queryParameters: qp,
        )
        .toString();
  }

  /// Build a Primary image URL for an item, using its image tag if available
  /// so the URL is cacheable. Returns null when the item has no image.
  String? imageUrlFor(Map<String, dynamic> m, String imageType,
      {int maxWidth = 480, int quality = 90}) {
    final tags = m['ImageTags'] as Map?;
    final tag = (tags?[imageType] as String?) ?? '';
    if (tag.isEmpty) return null;
    final id = m['Id'];
    if (id is! String) return null;
    return buildImageUrl(id, imageType,
        tag: tag, maxWidth: maxWidth, quality: quality);
  }

  /// For tracks without their own primary image, fall back to the parent
  /// album's image tag.
  String? albumImageUrl(Map<String, dynamic> m, {int maxWidth = 480}) {
    final id = m['AlbumId'] as String?;
    final tag = m['AlbumPrimaryImageTag'] as String?;
    if (id == null || tag == null || tag.isEmpty) return null;
    return buildImageUrl(id, 'Primary', tag: tag, maxWidth: maxWidth);
  }

  String buildImageUrl(String itemId, String imageType,
      {required String tag, int maxWidth = 480, int quality = 90}) {
    final qp = <String, String>{
      'maxWidth': '$maxWidth',
      'quality': '$quality',
      'tag': tag,
    };
    final baseUri = Uri.parse(stripTrailingSlash(baseUrl));
    return baseUri
        .replace(
          path: '${baseUri.path}/Items/$itemId/Images/$imageType',
          queryParameters: qp,
        )
        .toString();
  }

  /// Strip credentials (api_key, X-Emby-Token) from a URL before it's
  /// emitted to logcat.
  static Uri redactUrl(Uri uri) {
    if (uri.queryParameters.isEmpty) return uri;
    final scrubbed = <String, dynamic>{
      for (final e in uri.queryParametersAll.entries)
        e.key: isSensitiveParam(e.key) ? const ['<redacted>'] : e.value,
    };
    return uri.replace(queryParameters: scrubbed);
  }

  static bool isSensitiveParam(String key) {
    final k = key.toLowerCase();
    return k == 'api_key' ||
        k == 'apikey' ||
        k == 'x-emby-token' ||
        k == 'token';
  }

  /// Build a Jellyfin Authorization header.
  static String buildAuthHeader({
    required String deviceId,
    required String clientVersion,
    String? token,
    String? userId,
  }) {
    final parts = <String>[];
    if (userId != null && userId.isNotEmpty) {
      parts.add('UserId="${escapeHeaderValue(userId)}"');
    }
    if (token != null && token.isNotEmpty) {
      parts.add('Token="${escapeHeaderValue(token)}"');
    }
    parts.add('Client="Aetherfin"');
    parts.add('Device="Android"');
    parts.add('DeviceId="${asciiClean(escapeHeaderValue(deviceId))}"');
    parts.add('Version="${escapeHeaderValue(clientVersion)}"');
    return 'MediaBrowser ${parts.join(", ")}';
  }

  static String userAgentFor(String version) =>
      'Aetherfin/$version (Android)';

  static String escapeHeaderValue(String v) {
    return v
        .replaceAll('\\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll('\r', '')
        .replaceAll('\n', '');
  }

  /// Replace non-ASCII runs with `_`.
  static String asciiClean(String v) =>
      v.replaceAll(RegExp(r'[^\x00-\x7F]+'), '_');
}
