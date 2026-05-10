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
  final Dio _dio;

  JellyfinClient({
    required this.server,
    this.accessToken,
    this.userId,
  }) : _dio = Dio(BaseOptions(
          baseUrl: server.baseUrl,
          connectTimeout: const Duration(seconds: 5),
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
          headers: {
            if (accessToken != null)
              'Authorization': _buildAuthHeader(accessToken),
            if (accessToken == null)
              'X-Emby-Authorization': _buildAuthHeader(null),
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
  }

  static String _buildAuthHeader(String? token) {
    return 'MediaBrowser '
        'Client="Aetherfin", '
        'Device="Android", '
        'DeviceId="aetherfin-android", '
        'Version="0.1.0"'
        '${token != null ? ', Token="$token"' : ''}';
  }

  /// `GET /System/Info/Public` — used by mDNS resolution to confirm a
  /// reachable server and pick up its name + version.
  Future<JellyfinServer> publicInfo() async {
    final res = await _dio.getUri<Map<String, dynamic>>(
      Uri.parse('/System/Info/Public'),
    );
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
      '/Users/AuthenticateByName',
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

  /// `GET /Users/{userId}/Views` — the list of libraries the user can see.
  Future<List<LibraryView>> userViews() async {
    final res = await _dio.get<Map<String, dynamic>>('/Users/$userId/Views');
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
      '/Sessions/Playing/Progress',
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
