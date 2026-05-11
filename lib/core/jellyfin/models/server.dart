/// A Jellyfin server discovered via mDNS or entered manually.
class JellyfinServer {
  /// Resolved base URL, e.g. `https://media.example.com:8920` (no trailing slash).
  final String baseUrl;

  /// Friendly server name from `/System/Info/Public` → `ServerName`.
  final String name;

  /// Server version, e.g. `10.9.7`.
  final String? version;

  /// Server's announced ID (from public info, used for de-duping).
  final String? id;

  /// True if discovered via local mDNS scan.
  final bool isLocal;

  /// Last-known reachability — refreshed by the [JellyfinClient.ping].
  final bool isReachable;

  const JellyfinServer({
    required this.baseUrl,
    required this.name,
    this.version,
    this.id,
    this.isLocal = false,
    this.isReachable = true,
  });

  JellyfinServer copyWith({
    String? baseUrl,
    String? name,
    String? version,
    String? id,
    bool? isLocal,
    bool? isReachable,
  }) =>
      JellyfinServer(
        baseUrl: baseUrl ?? this.baseUrl,
        name: name ?? this.name,
        version: version ?? this.version,
        id: id ?? this.id,
        isLocal: isLocal ?? this.isLocal,
        isReachable: isReachable ?? this.isReachable,
      );

  @override
  bool operator ==(Object other) =>
      other is JellyfinServer && other.baseUrl == baseUrl;

  @override
  int get hashCode => baseUrl.hashCode;
}

/// Jellyfin user credentials returned from `/Users/AuthenticateByName`.
///
/// Note: the Authorization header is built freshly per-client in
/// `JellyfinClient._buildAuthHeader()` so it can pick up the
/// per-install random `DeviceId` from secure storage. There is
/// intentionally no `authHeader` getter here — hard-coding
/// `DeviceId="aetherfin-android"` was the source of CLAUDE.md §10
/// footgun #2 and we never want it brought back.
class JellyfinAuth {
  final JellyfinServer server;
  final String userId;
  final String userName;
  final String accessToken;

  const JellyfinAuth({
    required this.server,
    required this.userId,
    required this.userName,
    required this.accessToken,
  });
}
