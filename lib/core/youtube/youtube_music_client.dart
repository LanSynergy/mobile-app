import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../utils/log.dart';
import '../backend/music_backend.dart';
import '../jellyfin/models/items.dart';
import '../jellyfin/models/library.dart';
import 'innertube_client.dart';
import 'youtube_auth.dart';
import 'youtube_home_content.dart';

/// YouTube Music backend using youtube_explode_dart.
///
/// Streams from YouTube/YouTube Music catalog. Does NOT sync with a
/// YouTube Music account library — that's Phase 2. This MVP focuses
/// on search + streaming.
class YouTubeMusicClient implements MusicBackend {
  YouTubeMusicClient({this.auth}) : _yt = YoutubeExplode();

  final YouTubeAuth? auth;
  final YoutubeExplode _yt;
  final InnerTubeClient _innertube = InnerTubeClient();

  @override
  ServerType get serverType => ServerType.youtubeMusic;

  // ── Helpers ──────────────────────────────────────────────────────────

  AfTrack _videoToTrack(Video video) => AfTrack(
    id: video.id.value,
    title: video.title,
    artistName: video.author,
    albumName: 'YouTube Music',
    duration: video.duration ?? Duration.zero,
    imageUrl: video.thumbnails.highResUrl,
  );

  AfArtist _channelToArtist(Channel channel) => AfArtist(
    id: channel.id.value,
    name: channel.title,
    imageUrl: channel.logoUrl,
  );

  // ── Library browsing ─────────────────────────────────────────────────

  /// Returns the device's ISO country code (e.g. "ID", "MY", "US").
  String get _countryCode {
    final parts = Platform.localeName.split('_');
    if (parts.length >= 2) {
      final code = parts.last.toUpperCase();
      if (code.length == 2) return code;
    }
    return 'US';
  }

  /// Fetches home page content via InnerTube browse API.
  Future<YouTubeHomeContent> browseHome({
    String? params,
    String? continuation,
  }) async {
    final region = _countryCode;
    afLog(
      'aetherfin:youtube',
      'browseHome: region=$region, params=$params, continuation=$continuation',
    );

    final response = await _innertube.browseHome(
      params: params,
      continuation: continuation,
    );
    if (response == null || response.sections.isEmpty) {
      return YouTubeHomeContent.empty();
    }

    final sections = response.sections
        .map((s) => YouTubeHomeSection(title: s.title, items: s.items))
        .toList();

    afLog(
      'aetherfin:youtube',
      'browseHome: ${sections.length} sections, ${response.chips.length} chips',
    );

    return YouTubeHomeContent(
      sections: sections,
      chips: response.chips,
      region: region,
      continuation: response.continuation,
    );
  }

  @override
  Future<List<AfAlbum>> recentlyAddedAlbums({int limit = 20}) async => [];

  @override
  Future<List<AfTrack>> recentlyPlayed({int limit = 20}) async => [];

  @override
  Future<List<AfTrack>> resumeItems({int limit = 20}) async => [];

  @override
  Future<List<AfArtist>> artists({int limit = 200}) async => [];

  @override
  Future<List<AfPlaylist>> playlists({int limit = 200}) async => [];

  @override
  Future<List<AfAlbum>> allAlbums({
    int limit = 500,
    int startIndex = 0,
  }) async => [];

  @override
  Future<List<AfTrack>> allTracks({
    int limit = 1000,
    int startIndex = 0,
  }) async => [];

  @override
  Future<List<AfGenre>> genres({int limit = 200}) async => [];

  @override
  Future<List<AfAlbum>> favoriteAlbums({int limit = 30}) async => [];

  @override
  Future<List<AfTrack>> favoriteTracks({int limit = 500}) async => [];

  // ── Detail views ─────────────────────────────────────────────────────

  @override
  Future<({AfAlbum album, List<AfTrack> tracks})?> album(String id) async {
    try {
      final playlist = await _yt.playlists.get(id);
      final videos = await _yt.playlists.getVideos(id).take(100).toList();
      final album = AfAlbum(
        id: playlist.id.value,
        name: playlist.title,
        artistName: playlist.author,
        trackCount: playlist.videoCount ?? videos.length,
        imageUrl: playlist.thumbnails.highResUrl,
      );
      return (album: album, tracks: videos.map(_videoToTrack).toList());
    } on Exception catch (e) {
      afLog('youtube', 'Failed to get album', error: e);
      return null;
    }
  }

  @override
  Future<AfArtist?> artist(String id) async {
    try {
      final channel = await _yt.channels.get(ChannelId(id));
      return _channelToArtist(channel);
    } on Exception catch (e) {
      afLog('youtube', 'Failed to get artist', error: e);
      return null;
    }
  }

  @override
  Future<AfTrackDetails?> trackDetails(String id) async {
    try {
      final video = await _yt.videos.get(id);
      return AfTrackDetails(track: _videoToTrack(video));
    } on Exception catch (e) {
      afLog('youtube', 'Failed to get track details', error: e);
      return null;
    }
  }

  @override
  Future<List<AfAlbum>> artistAlbums(
    String artistId, {
    int limit = 100,
  }) async => [];

  @override
  Future<List<AfTrack>> artistTopTracks(
    String artistId, {
    int limit = 5,
  }) async {
    try {
      final channel = await _yt.channels.get(ChannelId(artistId));
      final uploads = _yt.channels.getUploads(channel.id);
      final tracks = <AfTrack>[];
      await for (final video in uploads) {
        tracks.add(_videoToTrack(video));
        if (tracks.length >= limit) break;
      }
      return tracks;
    } on Exception catch (e) {
      afLog('youtube', 'Failed to get artist top tracks', error: e);
      return [];
    }
  }

  @override
  Future<List<AfAlbum>> albumsByGenre(String genre, {int limit = 200}) async =>
      [];

  @override
  Future<({AfPlaylist playlist, List<AfTrack> tracks})?> playlist(
    String id,
  ) async {
    try {
      final pl = await _yt.playlists.get(id);
      final videos = await _yt.playlists.getVideos(id).take(100).toList();
      final playlist = AfPlaylist(
        id: pl.id.value,
        name: pl.title,
        trackCount: pl.videoCount ?? videos.length,
      );
      return (playlist: playlist, tracks: videos.map(_videoToTrack).toList());
    } on Exception catch (e) {
      afLog('youtube', 'Failed to get playlist', error: e);
      return null;
    }
  }

  // ── Search ───────────────────────────────────────────────────────────

  @override
  Future<
    ({
      List<AfTrack> tracks,
      List<AfAlbum> albums,
      List<AfArtist> artists,
      List<AfPlaylist> playlists,
    })
  >
  search(String query) async {
    try {
      final results = await _yt.search.search(query);
      final tracks = <AfTrack>[];
      for (final result in results) {
        tracks.add(_videoToTrack(result));
      }
      return (
        tracks: tracks,
        albums: <AfAlbum>[],
        artists: <AfArtist>[],
        playlists: <AfPlaylist>[],
      );
    } on Exception catch (e) {
      afLog('youtube', 'Search failed', error: e);
      return (
        tracks: <AfTrack>[],
        albums: <AfAlbum>[],
        artists: <AfArtist>[],
        playlists: <AfPlaylist>[],
      );
    }
  }

  // ── Favorites ────────────────────────────────────────────────────────

  @override
  Future<void> setFavorite(String itemId, bool isFavorite) async {
    afLog(
      'aetherfin:youtube',
      'setFavorite not yet implemented: $itemId -> $isFavorite',
    );
  }

  // ── Playlists ────────────────────────────────────────────────────────

  @override
  Future<void> addToPlaylist(String playlistId, List<String> trackIds) async {
    afLog('aetherfin:youtube', 'addToPlaylist not yet implemented');
  }

  @override
  Future<String?> createPlaylist(String name, List<String> trackIds) async {
    afLog('aetherfin:youtube', 'createPlaylist not yet implemented');
    return null;
  }

  @override
  Future<void> removeFromPlaylist(
    String playlistId,
    List<String> entryIds,
  ) async {
    afLog('aetherfin:youtube', 'removeFromPlaylist not yet implemented');
  }

  @override
  Future<void> movePlaylistItem(
    String playlistId,
    String itemId,
    int newIndex,
  ) async {
    afLog('aetherfin:youtube', 'movePlaylistItem not yet implemented');
  }

  @override
  Future<void> deletePlaylist(String playlistId) async {
    afLog('aetherfin:youtube', 'deletePlaylist not yet implemented');
  }

  @override
  Future<void> renamePlaylist(String playlistId, String newName) async {
    afLog('aetherfin:youtube', 'renamePlaylist not yet implemented');
  }

  // ── Similar songs ────────────────────────────────────────────────────

  @override
  Future<List<AfTrack>> instantMix(String seedId, {int limit = 50}) async {
    try {
      final video = await _yt.videos.get(seedId);
      final related = await _yt.videos.getRelatedVideos(video);
      if (related == null) return [];
      return related.take(limit).map(_videoToTrack).toList();
    } on Exception catch (e) {
      afLog('youtube', 'instantMix failed', error: e);
      return [];
    }
  }

  // ── Lyrics ───────────────────────────────────────────────────────────

  @override
  Future<String?> lyrics(String trackId) async => null;

  // ── Streaming ────────────────────────────────────────────────────────

  @override
  String trackStreamUrl(String trackId, {int? maxBitrateKbps}) {
    return 'https://youtube.com/watch?v=$trackId';
  }

  /// Resolves the actual audio stream URL for a YouTube video.
  Future<String> resolveStreamUrl(String videoId) async {
    try {
      afLog('aetherfin:youtube', 'getManifest for: $videoId');
      final manifest = await _yt.videos.streams.getManifest(
        VideoId(videoId),
        ytClients: [YoutubeApiClient.safari, YoutubeApiClient.androidVr],
      );
      afLog(
        'aetherfin:youtube',
        'manifest OK: audioOnly=${manifest.audioOnly.length} muxed=${manifest.muxed.length}',
      );

      // Prefer muxed (audio+video in one file) — most compatible with mpv.
      if (manifest.muxed.isNotEmpty) {
        final best = manifest.muxed.withHighestBitrate();
        final url = best.url.toString();
        afLog(
          'aetherfin:youtube',
          'Using muxed: ${best.container} bitrate=${best.bitrate} url=${url.substring(0, 80)}',
        );
        return url;
      }

      // Fallback: audio-only adaptive stream.
      if (manifest.audioOnly.isNotEmpty) {
        final best = manifest.audioOnly.withHighestBitrate();
        final url = best.url.toString();
        afLog(
          'aetherfin:youtube',
          'Using audioOnly: ${best.container} bitrate=${best.bitrate} url=${url.substring(0, 80)}',
        );
        return url;
      }

      throw StateError('No streams available for $videoId');
    } on Exception catch (e) {
      afLog('youtube', 'resolveStreamUrl failed for $videoId', error: e);
      rethrow;
    }
  }

  // ── Playback reporting ───────────────────────────────────────────────

  @override
  Future<void> reportPlaybackStart(String trackId) async {}

  @override
  Future<void> reportProgress(
    String trackId,
    Duration position, {
    bool isPaused = false,
  }) async {}

  @override
  Future<void> reportPlaybackStop(
    String trackId,
    Duration position, {
    bool submission = true,
  }) async {}

  // ── Play queue sync ──────────────────────────────────────────────────

  @override
  Future<void> savePlayQueue(
    List<String> trackIds, {
    int? currentIndex,
    Duration? position,
  }) async {}

  @override
  Future<({List<AfTrack> tracks, int currentIndex, Duration position})?>
  getPlayQueue() async => null;

  // ── User views ───────────────────────────────────────────────────────

  @override
  Future<List<LibraryView>> userViews() async => [];

  // ── User avatar ──────────────────────────────────────────────────────

  @override
  Future<void> uploadUserAvatar(List<int> bytes, String mimeType) async {}

  @override
  Future<void> deleteUserAvatar() async {}

  // ── Auth headers ─────────────────────────────────────────────────────

  @override
  Map<String, String> get authHeaders => {
    'User-Agent': 'Aetherfin/0.3.5 (Android)',
  };

  // ── Lifecycle ────────────────────────────────────────────────────────

  @override
  void clearCache() {}

  @override
  void close() {
    _yt.close();
  }
}
