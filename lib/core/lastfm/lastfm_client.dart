import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../../utils/log.dart';

/// Lightweight Last.fm API client for fetching similar tracks and scrobbling.
///
/// Uses `track.getSimilar`, `auth.getMobileSession`, `track.updateNowPlaying`,
/// and `track.scrobble` endpoints.
class LastFmClient {
  LastFmClient({required String apiKey, String? apiSecret, String? sessionKey})
    : _apiKey = apiKey,
      _apiSecret = apiSecret,
      _sessionKey = sessionKey;

  final String _apiKey;
  final String? _apiSecret;
  final String? _sessionKey;

  final Dio _dio = Dio(
    BaseOptions(baseUrl: 'https://ws.audioscrobbler.com/2.0/'),
  );

  /// Helper to calculate MD5 request signature for authenticated endpoints.
  /// Concatenates parameters alphabetically by name, appends secret, and hashes.
  String _generateSignature(Map<String, String> params) {
    final secret = _apiSecret;
    if (secret == null) {
      throw StateError('API secret is required for signing requests');
    }
    final sortedKeys = params.keys.toList()..sort();
    final buffer = StringBuffer();
    for (final key in sortedKeys) {
      buffer.write(key);
      buffer.write(params[key]);
    }
    buffer.write(secret);
    final bytes = utf8.encode(buffer.toString());
    return md5.convert(bytes).toString();
  }

  /// Exchange username and password for a persistent Session Key.
  /// Throws an exception if authentication fails.
  Future<String> authenticate(String username, String password) async {
    final params = {
      'method': 'auth.getMobileSession',
      'username': username,
      'password': password,
      'api_key': _apiKey,
    };
    try {
      final sig = _generateSignature(params);
      params['api_sig'] = sig;
      params['format'] = 'json';

      final res = await _dio.post(
        '/',
        data: params,
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );

      final data = res.data;
      if (data is Map) {
        final session = data['session'] as Map?;
        if (session != null) {
          final key = session['key'] as String?;
          if (key != null) return key;
        }
      }
      throw Exception('Authentication failed: missing session key in response');
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map && data.containsKey('message')) {
        throw Exception(data['message']);
      }
      throw Exception(e.message ?? 'Network error during authentication');
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  /// Update the "Now Playing" track on the user's Last.fm profile.
  Future<void> updateNowPlaying({
    required String artist,
    required String track,
    String? album,
    Duration? duration,
  }) async {
    final sk = _sessionKey;
    if (sk == null) return;

    final params = {
      'method': 'track.updateNowPlaying',
      'artist': artist,
      'track': track,
      'api_key': _apiKey,
      'sk': sk,
      if (album != null && album.isNotEmpty) 'album': album,
      if (duration != null && duration.inSeconds > 0)
        'duration': duration.inSeconds.toString(),
    };

    try {
      final sig = _generateSignature(params);
      params['api_sig'] = sig;
      params['format'] = 'json';

      await _dio.post(
        '/',
        data: params,
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      afLog('data', 'Last.fm now playing updated: $artist - $track');
    } catch (e, stack) {
      afLog('error', 'Last.fm now playing failed', error: e, stackTrace: stack);
    }
  }

  /// Scrobble a track to Last.fm (marks as listened).
  Future<void> scrobble({
    required String artist,
    required String track,
    required int timestamp, // Unix timestamp in seconds
    String? album,
    Duration? duration,
  }) async {
    final sk = _sessionKey;
    if (sk == null) return;

    final params = {
      'method': 'track.scrobble',
      'artist[0]': artist,
      'track[0]': track,
      'timestamp[0]': timestamp.toString(),
      'api_key': _apiKey,
      'sk': sk,
      if (album != null && album.isNotEmpty) 'album[0]': album,
      if (duration != null && duration.inSeconds > 0)
        'duration[0]': duration.inSeconds.toString(),
    };

    try {
      final sig = _generateSignature(params);
      params['api_sig'] = sig;
      params['format'] = 'json';

      await _dio.post(
        '/',
        data: params,
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
      afLog('data', 'Last.fm scrobble submitted: $artist - $track');
    } catch (e, stack) {
      afLog('error', 'Last.fm scrobble failed', error: e, stackTrace: stack);
    }
  }

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
