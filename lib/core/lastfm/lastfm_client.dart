import 'package:dio/dio.dart';

import '../../utils/log.dart';

/// Lightweight Last.fm API client for fetching similar tracks.
///
/// Uses `track.getSimilar` endpoint. Caching is handled externally
/// by [LastFmCacheRepository] / [SmartQueueManager].
class LastFmClient {
  LastFmClient({required String apiKey}) : _apiKey = apiKey;

  final String _apiKey;
  final Dio _dio = Dio(
    BaseOptions(baseUrl: 'https://ws.audioscrobbler.com/2.0'),
  );

  /// Fetch similar tracks from Last.fm for [artistName] / [trackTitle].
  /// Returns list of `{artist, title}` pairs. Empty on failure.
  Future<List<({String artist, String title})>> getSimilar({
    required String artistName,
    required String trackTitle,
    int limit = 30,
  }) async {
    try {
      final res = await _dio.get(
        '/',
        queryParameters: {
          'method': 'track.getSimilar',
          'artist': artistName,
          'track': trackTitle,
          'api_key': _apiKey,
          'format': 'json',
          'limit': limit,
        },
      );
      final data = res.data;
      if (data is! Map) return [];
      final similartracks = data['similartracks'] as Map?;
      if (similartracks == null) return [];
      final tracks = similartracks['track'] as List?;
      if (tracks == null) return [];
      return tracks.map((t) {
        final name = (t as Map)['name'] as String? ?? '';
        final artist = (t['artist'] as Map?)?['name'] as String? ?? '';
        return (artist: artist, title: name);
      }).toList();
    } catch (e, stack) {
      afLog('error', 'Last.fm getSimilar failed', error: e, stackTrace: stack);
      return [];
    }
  }
}
