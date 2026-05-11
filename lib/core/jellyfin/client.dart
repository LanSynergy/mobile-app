import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';

import 'models/items.dart';
import 'models/library.dart';
import 'models/server.dart';

/// Thin Dio-backed Jellyfin REST client.
///
/// Hand-rolled per design spec §11.1 — community Dart SDKs are stale and
/// the surface we need is small.
class JellyfinClient {
  final JellyfinServer server;
  final String? accessToken;
  final String? userId;
  final String deviceId;
  final Dio _dio;

  JellyfinClient({
    required this.server,
    required this.deviceId,
    this.accessToken,
    this.userId,
  }) : _dio = Dio(BaseOptions(
          // Trailing slash is REQUIRED so Dio's Uri.resolve preserves the
          // server's base path (e.g. https://example.com/jellyfin/). All
          // paths below are written WITHOUT a leading slash for the same
          // reason.
          baseUrl: server.baseUrl.endsWith('/')
              ? server.baseUrl
              : '${server.baseUrl}/',
          connectTimeout: const Duration(seconds: 5),
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
          // Modern Jellyfin (10.11+) reads `Authorization` only.
          // `X-Emby-Authorization` is deprecated and only consulted when
          // EnableLegacyAuthorization is true (off by default in 10.11+).
          // We send both for back-compat with older Jellyfin / Emby forks.
          //
          // Always sending User-Agent + Content-Type explicitly avoids the
          // 'Value cannot be null. (Parameter \'appName\')' server crash
          // some Jellyfin builds hit when those headers are missing.
          headers: {
            'Authorization': _buildAuthHeader(deviceId, accessToken),
            'X-Emby-Authorization': _buildAuthHeader(deviceId, accessToken),
            'User-Agent': 'Aetherfin/0.1.0 (Android)',
            'Accept': 'application/json',
          },
        )) {
    _dio.interceptors.add(
      DioCacheInterceptor(
        options: CacheOptions(
          store: MemCacheStore(),
          policy: CachePolicy.request,
          maxStale: const Duration(minutes: 5),
          priority: CachePriority.normal,
        ),
      ),
    );
    // Log every request + response to logcat so we can see exactly what
    // bytes go on the wire when debugging Jellyfin's 500 / 403 / etc.
    // The Authorization header value is redacted to avoid leaking tokens.
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final redactedHeaders = Map<String, dynamic>.from(options.headers)
            ..updateAll((k, v) =>
                k.toLowerCase().contains('auth') ? '<redacted>' : v);
          // ignore: avoid_print
          print('aetherfin:http → ${options.method} ${options.uri}');
          // ignore: avoid_print
          print('aetherfin:http headers: $redactedHeaders');
          // For auth-sensitive endpoints, redact the body too.
          final isAuth = options.uri.path.toLowerCase().contains('authenticate');
          // ignore: avoid_print
          print('aetherfin:http body: '
              '${isAuth ? '<redacted ${options.data is Map ? (options.data as Map).keys.toList() : options.data.runtimeType}>' : options.data}');
          handler.next(options);
        },
        onResponse: (response, handler) {
          // ignore: avoid_print
          print('aetherfin:http ← ${response.statusCode} '
              '${response.requestOptions.method} ${response.requestOptions.uri}');
          handler.next(response);
        },
        onError: (err, handler) {
          // ignore: avoid_print
          print('aetherfin:http ✕ ${err.response?.statusCode ?? '?'} '
              '${err.requestOptions.method} ${err.requestOptions.uri}');
          handler.next(err);
        },
      ),
    );
  }

  /// Build a Jellyfin Authorization header.
  ///
  /// We ALWAYS include `Token="..."` — empty when not yet authenticated.
  /// Jellyfin's parser at
  /// `Jellyfin.Server.Implementations/Security/AuthorizationContext.cs`
  /// is tolerant of an empty token, but the reference React Native client
  /// `leinelissen/jellyfin-audio-player` always includes all five fields
  /// (Client, Device, DeviceId, Version, Token) and that pattern is the
  /// known-good shape. The known 500 "appName is null" error happens when
  /// Jellyfin sees a header it can't parse, so we match the canonical
  /// format exactly.
  static String _buildAuthHeader(String deviceId, String? token) {
    return 'MediaBrowser '
        'Client="Aetherfin", '
        'Device="Android", '
        'DeviceId="$deviceId", '
        'Version="0.1.0", '
        'Token="${token ?? ''}"';
  }

  /// `GET /System/Info/Public` — used by mDNS resolution to confirm a
  /// reachable server and pick up its name + version.
  Future<JellyfinServer> publicInfo() async {
    final res = await _dio.get<Map<String, dynamic>>('System/Info/Public');
    final data = res.data ?? const <String, dynamic>{};
    return server.copyWith(
      name: (data['ServerName'] as String?) ?? server.name,
      version: data['Version'] as String?,
      id: data['Id'] as String?,
      isReachable: true,
    );
  }

  /// Authenticate via username + password. Returns the auth blob ready
  /// to be persisted to secure storage.
  Future<JellyfinAuth> authenticate({
    required String username,
    required String password,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      'Users/AuthenticateByName',
      data: {'Username': username, 'Pw': password},
    );
    final data = res.data!;
    final user = (data['User'] as Map).cast<String, dynamic>();
    return JellyfinAuth(
      server: server,
      userId: user['Id'] as String,
      userName: user['Name'] as String,
      accessToken: data['AccessToken'] as String,
    );
  }

  /// Authenticate via a server-issued API key (created in
  /// `Dashboard → API Keys`). This bypasses `/Users/AuthenticateByName`
  /// — and therefore Jellyfin's session-creation / `LogSessionActivity`
  /// code path entirely — so it works even when plugins or stale device
  /// state cause that endpoint to 500.
  ///
  /// We list users with the API key, find the one whose name matches
  /// [username] (case-insensitive), and return their userId + the key
  /// as the access token. Throws [StateError] if no matching user is
  /// found, with a clear message the UI can surface.
  Future<JellyfinAuth> authenticateWithApiKey({
    required String username,
    required String apiKey,
  }) async {
    // Build a temporary client carrying the API key in the Authorization
    // header. We can't just swap headers on `_dio` because that would
    // mutate state shared with other callers.
    final probe = Dio(BaseOptions(
      baseUrl: _dio.options.baseUrl,
      connectTimeout: const Duration(seconds: 5),
      sendTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'Authorization': _buildAuthHeader(deviceId, apiKey),
        'X-Emby-Authorization': _buildAuthHeader(deviceId, apiKey),
        'User-Agent': 'Aetherfin/0.1.0 (Android)',
        'Accept': 'application/json',
      },
    ));
    final res = await probe.get<List<dynamic>>('Users');
    final users = (res.data ?? const []).cast<Map>();
    final wanted = username.trim().toLowerCase();
    for (final raw in users) {
      final u = raw.cast<String, dynamic>();
      final name = (u['Name'] as String?)?.trim() ?? '';
      if (name.toLowerCase() == wanted) {
        return JellyfinAuth(
          server: server,
          userId: u['Id'] as String,
          userName: name,
          accessToken: apiKey,
        );
      }
    }
    throw StateError(
      'No user named "$username" on this server. '
      'Available: ${users.map((u) => u['Name']).join(", ")}',
    );
  }

  /// `GET /Users/{userId}/Views` — the list of libraries the user can see.
  Future<List<LibraryView>> userViews() async {
    final res = await _dio.get<Map<String, dynamic>>('Users/$userId/Views');
    final items = (res.data?['Items'] as List? ?? const []).cast<Map>();
    return items
        .map((m) => LibraryView(
              id: m['Id'] as String,
              name: m['Name'] as String,
              collectionType: (m['CollectionType'] as String? ?? 'unknown')
                  .toLowerCase(),
            ))
        .toList(growable: false);
  }

  /// Resolve an album/track/artist Primary image URL (delegates to Jellyfin's
  /// `/Items/{id}/Images/Primary` endpoint with `maxWidth` and `quality` query
  /// params for sane bandwidth).
  String imageUrl(String itemId, {int maxWidth = 480, int quality = 90}) {
    final qp = <String, String>{
      'maxWidth': '$maxWidth',
      'quality': '$quality',
      if (accessToken != null) 'api_key': accessToken!,
    };
    final query = qp.entries.map((e) => '${e.key}=${e.value}').join('&');
    return '${server.baseUrl}/Items/$itemId/Images/Primary?$query';
  }

  /// Build a streaming URL for a given track ID.
  ///
  /// We DO NOT add `static=true` — that would force direct play and bypass
  /// Jellyfin's transcoder. Instead we let the server decide based on the
  /// `audioCodec` / `maxStreamingBitrate` hints we send, and the resulting
  /// `MediaSource` carries the [TrackQuality] honesty signal back to us.
  String trackStreamUrl(
    String trackId, {
    int? maxBitrateKbps,
    String? deviceProfileId,
  }) {
    final qp = <String, String>{
      if (accessToken != null) 'api_key': accessToken!,
      if (maxBitrateKbps != null)
        'maxStreamingBitrate': '${maxBitrateKbps * 1000}',
      if (deviceProfileId != null) 'profileId': deviceProfileId,
    };
    final query = qp.entries.map((e) => '${e.key}=${e.value}').join('&');
    return '${server.baseUrl}/Audio/$trackId/universal?$query';
  }

  /// `POST /Sessions/Playing/Progress` — playback progress reporting.
  Future<void> reportProgress(
    String trackId,
    Duration position, {
    bool isPaused = false,
  }) async {
    await _dio.post(
      'Sessions/Playing/Progress',
      data: {
        'ItemId': trackId,
        'PositionTicks': position.inMicroseconds * 10,
        'IsPaused': isPaused,
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Below: stub endpoints we'll fill in as Phase 4–7 lands.
  // ---------------------------------------------------------------------------

  /// `/Users/{userId}/Items/Resume` — the "Resume what I was listening to" data.
  Future<List<AfTrack>> resumeItems() async => const [];

  /// `/Items?IncludeItemTypes=MusicAlbum&Recursive=true&SortBy=DateCreated&SortOrder=Descending`.
  Future<List<AfAlbum>> recentlyAddedAlbums({int limit = 20}) async => const [];

  /// `/Items?IncludeItemTypes=Audio&SortBy=DatePlayed&SortOrder=Descending`.
  Future<List<AfTrack>> recentlyPlayed({int limit = 20}) async => const [];

  /// `/Items/{albumId}` + `/Items?ParentId=…` for the track list.
  Future<({AfAlbum album, List<AfTrack> tracks})?> album(String id) async => null;

  /// `/Items/{artistId}` + albums + top tracks + similar.
  Future<AfArtist?> artist(String id) async => null;

  /// Full-text search.
  Future<({List<AfTrack> tracks, List<AfAlbum> albums, List<AfArtist> artists, List<AfPlaylist> playlists})>
      search(String query) async => (
            tracks: const <AfTrack>[],
            albums: const <AfAlbum>[],
            artists: const <AfArtist>[],
            playlists: const <AfPlaylist>[],
          );

  /// `/Audio/{id}/Lyrics` — returns LRC blob if available.
  Future<String?> lyrics(String trackId) async => null;
}
