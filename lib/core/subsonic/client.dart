import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

import '../../utils/log.dart';
import '../../utils/url.dart';
import '../backend/music_backend.dart';
import '../jellyfin/models/items.dart';
import '../jellyfin/models/library.dart';
import '../jellyfin/models/quality.dart';
import '../jellyfin/models/server.dart';

const _kSubsonicApiVersion = '1.16.1';
const _kClientName = 'Aetherfin';

/// Subsonic/OpenSubsonic REST client for Navidrome (and compatible servers).
///
/// This is the Subsonic counterpart of [JellyfinClient]. It implements
/// [MusicBackend] so the provider layer can treat both backends
/// identically. Auth uses the Subsonic token scheme:
/// `t = md5(password + salt)`, `s = salt`, sent as query params on
/// every request alongside `u`, `v`, `c`, `f=json`.
class SubsonicClient implements MusicBackend {
  final JellyfinServer server;
  final String username;

  /// The plaintext password — stored in encrypted secure storage. Needed
  /// to compute the per-request `md5(password + salt)` token.
  final String password;
  final Dio _dio;
  final MemCacheStore _cacheStore;
  final Random _rng = Random.secure();

  SubsonicClient({
    required this.server,
    required this.username,
    required this.password,
  })  : _cacheStore = MemCacheStore(
            maxSize: 20 * 1024 * 1024, maxEntrySize: 1 * 1024 * 1024),
        _dio = Dio(BaseOptions(
          baseUrl: _buildBaseUrl(server.baseUrl),
          connectTimeout: const Duration(seconds: 5),
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
          headers: {
            'User-Agent': 'Aetherfin/0.1.0 (Android)',
            'Accept': 'application/json',
          },
        )) {
    _dio.interceptors.add(
      DioCacheInterceptor(
        options: CacheOptions(
          store: _cacheStore,
          policy: CachePolicy.request,
          maxStale: const Duration(minutes: 5),
          priority: CachePriority.normal,
        ),
      ),
    );
    if (kDebugMode) {
      _dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            afLog('http', '→ ${options.method} ${options.uri.path}');
            handler.next(options);
          },
          onResponse: (response, handler) {
            afLog('http',
                '← ${response.statusCode} ${response.requestOptions.uri.path}');
            handler.next(response);
          },
          onError: (err, handler) {
            afLog('http',
                '✕ ${err.response?.statusCode ?? '?'} ${err.requestOptions.uri.path}');
            handler.next(err);
          },
        ),
      );
    }
  }

  static String _buildBaseUrl(String baseUrl) {
    final b = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    return '${b}rest/';
  }

  // ── Auth helpers ──────────────────────────────────────────────────────

  /// Generate Subsonic auth query params for every request.
  Map<String, String> _authParams() {
    final salt = _generateSalt();
    final token = md5.convert(utf8.encode('$password$salt')).toString();
    return {
      'u': username,
      't': token,
      's': salt,
      'v': _kSubsonicApiVersion,
      'c': _kClientName,
      'f': 'json',
    };
  }

  String _generateSalt([int length = 16]) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List.generate(length, (_) => chars[_rng.nextInt(chars.length)])
        .join();
  }

  /// Execute a Subsonic API call and return the inner response data.
  Future<Map<String, dynamic>> _get(
    String endpoint, [
    Map<String, dynamic>? extra,
  ]) async {
    final qp = <String, dynamic>{..._authParams(), ...?extra};
    final res = await _dio.get<Map<String, dynamic>>(
      '$endpoint.view',
      queryParameters: qp,
    );
    final root = res.data?['subsonic-response'] as Map<String, dynamic>?;
    if (root == null) {
      throw StateError('Subsonic response missing subsonic-response envelope');
    }
    final status = root['status'] as String?;
    if (status != 'ok') {
      final err = root['error'] as Map<String, dynamic>?;
      final code = err?['code'] as int? ?? 0;
      final msg = err?['message'] as String? ?? 'Unknown Subsonic error';
      throw SubsonicApiError(code, msg);
    }
    return root;
  }

  // ── MusicBackend implementation ───────────────────────────────────────

  @override
  ServerType get serverType => ServerType.subsonic;

  @override
  Map<String, String> get authHeaders => const {};

  @override
  void clearCache() => _cacheStore.clean();

  @override
  void close() {
    _cacheStore.close();
    _dio.close(force: true);
  }

  // ── Server ────────────────────────────────────────────────────────────

  /// `ping.view` — verify the server is reachable and credentials work.
  Future<JellyfinServer> ping() async {
    await _get('ping');
    return server.copyWith(isReachable: true);
  }

  // ── Library browsing ──────────────────────────────────────────────────

  @override
  Future<List<AfAlbum>> recentlyAddedAlbums({int limit = 20}) async {
    final root = await _get('getAlbumList2', {
      'type': 'newest',
      'size': limit,
    });
    return _parseAlbumList(root['albumList2'] as Map<String, dynamic>?);
  }

  @override
  Future<List<AfTrack>> recentlyPlayed({int limit = 20}) async {
    // Subsonic has no direct "recently played tracks" endpoint.
    // Use getAlbumList2 type=recent (recently played albums) and fetch
    // their tracks, or return empty for now.
    final root = await _get('getAlbumList2', {
      'type': 'recent',
      'size': limit,
    });
    final albums = _parseAlbumList(root['albumList2'] as Map<String, dynamic>?);
    if (albums.isEmpty) return const [];
    // Fetch tracks from the first few albums to approximate recently played
    final tracks = <AfTrack>[];
    for (final a in albums.take(5)) {
      try {
        final detail = await album(a.id);
        if (detail != null) tracks.addAll(detail.tracks);
      } catch (e) {
        afLog('subsonic', 'recentlyPlayed album fetch failed id=${a.id}', error: e);
      }
    }
    return tracks.take(limit).toList(growable: false);
  }

  @override
  Future<List<AfTrack>> resumeItems({int limit = 20}) async {
    // Subsonic has no resume concept.
    return const [];
  }

  @override
  Future<List<AfArtist>> artists({int limit = 200}) async {
    final root = await _get('getArtists');
    final artistsData = root['artists'] as Map<String, dynamic>?;
    final indices =
        (artistsData?['index'] as List?)?.cast<Map<String, dynamic>>() ??
            const [];
    final result = <AfArtist>[];
    for (final idx in indices) {
      final artistList =
          (idx['artist'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      for (final a in artistList) {
        result.add(_parseArtist(a));
        if (result.length >= limit) return result;
      }
    }
    return result;
  }

  @override
  Future<List<AfPlaylist>> playlists({int limit = 200}) async {
    final root = await _get('getPlaylists');
    final playlistsData = root['playlists'] as Map<String, dynamic>?;
    final list = (playlistsData?['playlist'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        const [];
    return list
        .take(limit)
        .map(_parsePlaylist)
        .toList(growable: false);
  }

  @override
  Future<List<AfAlbum>> allAlbums({
    int limit = 500,
    int startIndex = 0,
  }) async {
    final root = await _get('getAlbumList2', {
      'type': 'alphabeticalByName',
      'size': limit,
      'offset': startIndex,
    });
    return _parseAlbumList(root['albumList2'] as Map<String, dynamic>?);
  }

  @override
  Future<List<AfTrack>> allTracks({
    int limit = 1000,
    int startIndex = 0,
  }) async {
    // Subsonic has no "get all songs" endpoint. Use search3 with empty
    // query which Navidrome supports.
    final root = await _get('search3', {
      'query': '',
      'songCount': limit,
      'songOffset': startIndex,
      'albumCount': 0,
      'artistCount': 0,
    });
    final results = root['searchResult3'] as Map<String, dynamic>?;
    final songs =
        (results?['song'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    return songs.map(_parseTrack).toList(growable: false);
  }

  @override
  Future<List<AfGenre>> genres({int limit = 200}) async {
    final root = await _get('getGenres');
    final genresData = root['genres'] as Map<String, dynamic>?;
    final list = (genresData?['genre'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        const [];
    const palette = <String>[
      '#5644C9', '#A89DEC', '#3FD18C', '#FF7A59',
      '#F8C42D', '#FF6FB5', '#3DB6FF', '#FF4D6D',
    ];
    // Walk the input once and assign palette colours by output index so
    // the colour sequence matches the Jellyfin backend (which also keys
    // off result.length). Avoids the O(n²) `list.indexOf(g)` lookup and
    // the identity-equality footgun (Map doesn't override ==).
    final result = <AfGenre>[];
    for (final g in list.take(limit)) {
      final name = (g['value'] as String?) ?? '';
      if (name.isEmpty) continue;
      result.add(AfGenre(name, palette[result.length % palette.length]));
    }
    return result;
  }

  @override
  Future<List<AfAlbum>> favoriteAlbums({int limit = 30}) async {
    final root = await _get('getAlbumList2', {
      'type': 'starred',
      'size': limit,
    });
    return _parseAlbumList(root['albumList2'] as Map<String, dynamic>?);
  }

  @override
  Future<List<AfTrack>> favoriteTracks({int limit = 500}) async {
    final root = await _get('getStarred2', {});
    final starred = root['starred2'] as Map<String, dynamic>?;
    if (starred == null) return const [];
    final songs =
        (starred['song'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    return songs.take(limit).map(_parseTrack).toList(growable: false);
  }

  // ── Detail views ──────────────────────────────────────────────────────

  @override
  Future<({AfAlbum album, List<AfTrack> tracks})?> album(String id) async {
    final root = await _get('getAlbum', {'id': id});
    final albumData = root['album'] as Map<String, dynamic>?;
    if (albumData == null) return null;
    final albumObj = _parseAlbumDetail(albumData);
    final songs = (albumData['song'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        const [];
    final tracks = songs.map(_parseTrack).toList(growable: false);
    return (album: albumObj, tracks: tracks);
  }

  @override
  Future<AfArtist?> artist(String id) async {
    final root = await _get('getArtist', {'id': id});
    final data = root['artist'] as Map<String, dynamic>?;
    if (data == null) return null;
    return _parseArtistDetail(data);
  }

  @override
  Future<List<AfAlbum>> artistAlbums(String artistId,
      {int limit = 100}) async {
    final root = await _get('getArtist', {'id': artistId});
    final data = root['artist'] as Map<String, dynamic>?;
    if (data == null) return const [];
    final albums =
        (data['album'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    return albums
        .take(limit)
        .map(_parseAlbumDetail)
        .toList(growable: false);
  }

  @override
  Future<List<AfTrack>> artistTopTracks(String artistId,
      {int limit = 5}) async {
    // Get artist name first, then use getTopSongs
    final artistObj = await artist(artistId);
    if (artistObj == null) return const [];
    try {
      final root = await _get('getTopSongs', {
        'artist': artistObj.name,
        'count': limit,
      });
      final topSongs = root['topSongs'] as Map<String, dynamic>?;
      final songs = (topSongs?['song'] as List?)
              ?.cast<Map<String, dynamic>>() ??
          const [];
      return songs.map(_parseTrack).toList(growable: false);
    } catch (e) {
      afLog('subsonic', 'getTopSongs failed, falling back to search', error: e);
      // getTopSongs may not be supported; fall back to search
      final root = await _get('search3', {
        'query': artistObj.name,
        'songCount': limit,
        'albumCount': 0,
        'artistCount': 0,
      });
      final results = root['searchResult3'] as Map<String, dynamic>?;
      final songs = (results?['song'] as List?)
              ?.cast<Map<String, dynamic>>() ??
          const [];
      return songs.map(_parseTrack).toList(growable: false);
    }
  }

  @override
  Future<List<AfAlbum>> albumsByGenre(String genre, {int limit = 200}) async {
    final root = await _get('getAlbumList2', {
      'type': 'byGenre',
      'genre': genre,
      'size': limit,
    });
    return _parseAlbumList(root['albumList2'] as Map<String, dynamic>?);
  }

  @override
  Future<({AfPlaylist playlist, List<AfTrack> tracks})?> playlist(
      String id) async {
    final root = await _get('getPlaylist', {'id': id});
    final data = root['playlist'] as Map<String, dynamic>?;
    if (data == null) return null;
    final pl = _parsePlaylist(data);
    final songs =
        (data['entry'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final tracks = songs.map(_parseTrack).toList(growable: false);
    return (playlist: pl, tracks: tracks);
  }

  // ── Search ────────────────────────────────────────────────────────────

  @override
  Future<
      ({
        List<AfTrack> tracks,
        List<AfAlbum> albums,
        List<AfArtist> artists,
        List<AfPlaylist> playlists,
      })> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      return (
        tracks: const <AfTrack>[],
        albums: const <AfAlbum>[],
        artists: const <AfArtist>[],
        playlists: const <AfPlaylist>[],
      );
    }
    final root = await _get('search3', {
      'query': q,
      'songCount': 20,
      'albumCount': 20,
      'artistCount': 20,
    });
    final results = root['searchResult3'] as Map<String, dynamic>?;
    final songs =
        (results?['song'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final albumsList =
        (results?['album'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final artistsList =
        (results?['artist'] as List?)?.cast<Map<String, dynamic>>() ??
            const [];
    return (
      tracks: songs.map(_parseTrack).toList(growable: false),
      albums: albumsList.map(_parseAlbumDetail).toList(growable: false),
      artists: artistsList.map(_parseArtist).toList(growable: false),
      playlists: const <AfPlaylist>[],
    );
  }

  // ── Favorites ─────────────────────────────────────────────────────────

  @override
  Future<void> setFavorite(String itemId, bool isFavorite) async {
    if (isFavorite) {
      await _get('star', {'id': itemId});
    } else {
      await _get('unstar', {'id': itemId});
    }
  }

  // ── Playlists ─────────────────────────────────────────────────────────

  @override
  Future<void> addToPlaylist(
      String playlistId, List<String> trackIds) async {
    final params = <String, dynamic>{'playlistId': playlistId};
    // Subsonic takes multiple songIdToAdd params; Dio handles list values
    params['songIdToAdd'] = trackIds;
    await _get('updatePlaylist', params);
  }

  @override
  Future<String?> createPlaylist(
      String name, List<String> trackIds) async {
    final params = <String, dynamic>{
      'name': name,
      if (trackIds.isNotEmpty) 'songId': trackIds,
    };
    final root = await _get('createPlaylist', params);
    final pl = root['playlist'] as Map<String, dynamic>?;
    return pl?['id']?.toString();
  }

  @override
  Future<void> removeFromPlaylist(
      String playlistId, List<String> entryIds) async {
    // Subsonic uses 0-based songIndexToRemove. The entryIds here are
    // track indices as strings.
    final params = <String, dynamic>{
      'playlistId': playlistId,
      'songIndexToRemove': entryIds.map(int.parse).toList(),
    };
    await _get('updatePlaylist', params);
  }

  @override
  Future<void> movePlaylistItem(
      String playlistId, String itemId, int newIndex) async {
    // Subsonic API has no playlist-reorder endpoint. Throwing lets the UI
    // catch this and show a toast instead of silently discarding the move.
    throw UnsupportedError(
        'Subsonic API does not support playlist item reordering');
  }

  @override
  Future<void> deletePlaylist(String playlistId) async {
    await _get('deletePlaylist', {'id': playlistId});
  }

  @override
  Future<void> renamePlaylist(String playlistId, String newName) async {
    await _get('updatePlaylist', {
      'playlistId': playlistId,
      'name': newName,
    });
  }

  // ── Similar songs ─────────────────────────────────────────────────────

  @override
  Future<List<AfTrack>> instantMix(String seedId, {int limit = 50}) async {
    try {
      final root = await _get('getSimilarSongs2', {
        'id': seedId,
        'count': limit,
      });
      final data = root['similarSongs2'] as Map<String, dynamic>?;
      final songs = (data?['song'] as List?)
              ?.cast<Map<String, dynamic>>() ??
          const [];
      return songs.map(_parseTrack).toList(growable: false);
    } catch (e) {
      afLog('subsonic', 'getSimilarSongs2 failed', error: e);
      // getSimilarSongs2 may not be supported; return empty
      return const [];
    }
  }

  // ── Lyrics ────────────────────────────────────────────────────────────

  @override
  Future<String?> lyrics(String trackId) async {
    try {
      // Try OpenSubsonic getLyricsBySongId first
      final root = await _get('getLyricsBySongId', {'id': trackId});
      final lyricsData = root['lyricsList'] as Map<String, dynamic>?;
      final structured = (lyricsData?['structuredLyrics'] as List?)
              ?.cast<Map<String, dynamic>>() ??
          const [];
      if (structured.isEmpty) return null;
      // Prefer synced lyrics
      final synced = structured.firstWhere(
        (l) => l['synced'] == true,
        orElse: () => structured.first,
      );
      final lines =
          (synced['line'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      if (lines.isEmpty) return null;
      final buf = StringBuffer();
      for (final line in lines) {
        final text = (line['value'] as String?) ?? '';
        final startMs = line['start'] as int?;
        if (startMs != null) {
          final mm = (startMs ~/ 60000).toString().padLeft(2, '0');
          final ss = ((startMs ~/ 1000) % 60).toString().padLeft(2, '0');
          final cs = ((startMs % 1000) ~/ 10).toString().padLeft(2, '0');
          buf.writeln('[$mm:$ss.$cs]$text');
        } else {
          buf.writeln(text);
        }
      }
      return buf.toString();
    } catch (e) {
      afLog('subsonic', 'getLyricsBySongId failed', error: e);
      // Fall back to legacy getLyrics (requires artist + title)
      return null;
    }
  }

  // ── Streaming ─────────────────────────────────────────────────────────

  @override
  String trackStreamUrl(String trackId, {int? maxBitrateKbps}) {
    final params = <String, String>{
      ..._authParams(),
      'id': trackId,
      // 'raw' tells Navidrome to serve the original file without
      // transcoding. Without this, Navidrome may transcode on-the-fly
      // which adds latency and CPU load on the server.
      'format': 'raw',
    };
    final baseUri = Uri.parse(stripTrailingSlash(server.baseUrl));
    return baseUri
        .replace(
          path: '${baseUri.path}/rest/stream.view',
          queryParameters: params,
        )
        .toString();
  }

  /// Build a cover art URL with embedded auth.
  String? coverArtUrl(String? coverArtId, {int size = 480}) {
    if (coverArtId == null || coverArtId.isEmpty) return null;
    final params = <String, String>{
      ..._authParams(),
      'id': coverArtId,
      'size': '$size',
    };
    final baseUri = Uri.parse(stripTrailingSlash(server.baseUrl));
    return baseUri
        .replace(
          path: '${baseUri.path}/rest/getCoverArt.view',
          queryParameters: params,
        )
        .toString();
  }

  // ── Playback reporting ────────────────────────────────────────────────

  @override
  Future<void> reportPlaybackStart(String trackId) async {
    try {
      await _get('scrobble', {
        'id': trackId,
        'submission': false,
      });
    } catch (e) {
      afLog('subsonic', 'reportPlaybackStart scrobble failed', error: e);
    }
  }

  @override
  Future<void> reportProgress(
    String trackId,
    Duration position, {
    bool isPaused = false,
  }) async {
    // Subsonic has no progress endpoint; scrobble handles start/stop only
  }

  @override
  Future<void> reportPlaybackStop(String trackId, Duration position) async {
    try {
      await _get('scrobble', {
        'id': trackId,
        'submission': true,
      });
    } catch (e) {
      afLog('subsonic', 'reportPlaybackStop scrobble failed', error: e);
    }
  }

  // ── User views ────────────────────────────────────────────────────────

  @override
  Future<List<LibraryView>> userViews() async {
    // Subsonic doesn't have the concept of user views like Jellyfin.
    // Return a single "Music" view as a reasonable default.
    return const [
      LibraryView(
        id: 'music',
        name: 'Music',
        collectionType: 'music',
      ),
    ];
  }

  // ── Parsing helpers ───────────────────────────────────────────────────

  List<AfAlbum> _parseAlbumList(Map<String, dynamic>? data) {
    final albums =
        (data?['album'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    return albums.map(_parseAlbumDetail).toList(growable: false);
  }

  AfAlbum _parseAlbumDetail(Map<String, dynamic> m) {
    final id = (m['id'] ?? '').toString();
    final duration = _asInt(m['duration']) ?? 0;
    final created = m['created'] as String?;
    final starred = m['starred'] as String?;
    return AfAlbum(
      id: id,
      name: (m['name'] as String?) ??
          (m['album'] as String?) ??
          (m['title'] as String?) ??
          'Unknown',
      artistName: (m['artist'] as String?) ?? '',
      artistId: m['artistId']?.toString(),
      trackCount: _asInt(m['songCount']) ?? 0,
      year: _asInt(m['year']),
      totalDuration: Duration(seconds: duration),
      imageUrl: coverArtUrl(m['coverArt']?.toString()),
      dateAdded: created != null ? DateTime.tryParse(created) : null,
      isFavorite: starred != null,
    );
  }

  AfArtist _parseArtist(Map<String, dynamic> m) {
    return AfArtist(
      id: (m['id'] ?? '').toString(),
      name: (m['name'] as String?) ?? 'Unknown',
      albumCount: _asInt(m['albumCount']) ?? 0,
      imageUrl: coverArtUrl(m['coverArt']?.toString() ?? m['artistImageUrl']?.toString()),
    );
  }

  AfArtist _parseArtistDetail(Map<String, dynamic> m) {
    final albums =
        (m['album'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    return AfArtist(
      id: (m['id'] ?? '').toString(),
      name: (m['name'] as String?) ?? 'Unknown',
      albumCount: albums.length,
      imageUrl: coverArtUrl(m['coverArt']?.toString() ?? m['artistImageUrl']?.toString()),
    );
  }

  AfTrack _parseTrack(Map<String, dynamic> m) {
    final duration = _asInt(m['duration']) ?? 0;
    final starred = m['starred'] as String?;
    final created = m['created'] as String?;
    final bitRate = _asInt(m['bitRate']);
    final suffix = (m['suffix'] as String?)?.toLowerCase() ?? '';
    final isLossless = suffix == 'flac' || suffix == 'alac' || suffix == 'wav';
    final samplingRate = _asInt(m['samplingRate']);
    return AfTrack(
      id: (m['id'] ?? '').toString(),
      title: (m['title'] as String?) ?? 'Unknown',
      artistName: (m['artist'] as String?) ?? '',
      albumName: (m['album'] as String?) ?? '',
      albumId: m['albumId']?.toString(),
      artistId: m['artistId']?.toString(),
      trackNumber: _asInt(m['track']),
      duration: Duration(seconds: duration),
      quality: TrackQuality(
        sourceCodec: suffix,
        bitrateKbps: !isLossless ? bitRate : null,
        bitDepth: isLossless ? _asInt(m['bitDepth']) : null,
        sampleRateKhz: isLossless && samplingRate != null
            ? samplingRate ~/ 1000
            : null,
      ),
      imageUrl: coverArtUrl(m['coverArt']?.toString()),
      isFavorite: starred != null,
      dateAdded: created != null ? DateTime.tryParse(created) : null,
    );
  }

  AfPlaylist _parsePlaylist(Map<String, dynamic> m) {
    final duration = _asInt(m['duration']) ?? 0;
    return AfPlaylist(
      id: (m['id'] ?? '').toString(),
      name: (m['name'] as String?) ?? 'Unknown',
      trackCount: _asInt(m['songCount']) ?? 0,
      duration: Duration(seconds: duration),
      imageUrl: coverArtUrl(m['coverArt']?.toString()),
      isPublic: (m['public'] as bool?) ?? false,
    );
  }

  /// Coerce a JSON numeric to int regardless of whether the upstream
  /// emitted it as int or double. Subsonic-compatible servers vary in
  /// their JSON encoders — Navidrome consistently emits ints, but some
  /// OpenSubsonic implementations encode integer-valued doubles like
  /// `123.0` for durations / bitrates. A blunt \`as int?\` cast then
  /// throws TypeError and tears the parse down. Also accepts numeric
  /// strings like \`"123"\` defensively.
  static int? _asInt(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }
}

/// Error returned by the Subsonic API (status != "ok").
class SubsonicApiError implements Exception {
  final int code;
  final String message;
  const SubsonicApiError(this.code, this.message);

  @override
  String toString() => 'SubsonicApiError($code): $message';
}
