import 'package:dio/dio.dart';
import '../../utils/log.dart';

class LrcLibClient {
  LrcLibClient({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 5),
              sendTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 10),
              headers: {
                'User-Agent':
                    'Aetherfin Music Player (https://github.com/Aetherfin/mobile-app)',
              },
            ),
          );

  final Dio _dio;

  /// Fetches synced or plain lyrics for a track from LRCLib.
  /// Returns a Map with keys 'synced' and 'plain' or null if not found.
  Future<({String? synced, String? plain})?> fetchLyrics({
    required String trackName,
    required String artistName,
    required String albumName,
    required Duration duration,
  }) async {
    if (trackName.isEmpty || artistName.isEmpty) return null;

    try {
      final queryParams = <String, dynamic>{
        'track_name': trackName,
        'artist_name': artistName,
      };
      if (albumName.isNotEmpty) {
        queryParams['album_name'] = albumName;
      }
      final durationSecs = duration.inSeconds;
      if (durationSecs > 0) {
        queryParams['duration'] = durationSecs.toString();
      }

      afLog('lyrics', 'Querying lrclib.net: $queryParams');

      final response = await _dio.get<List<dynamic>>(
        'https://lrclib.net/api/search',
        queryParameters: queryParams,
      );

      final results = response.data;
      if (results == null || results.isEmpty) {
        afLog('lyrics', 'lrclib.net: no results found.');
        return null;
      }

      // Find the best match. Prefer results that have syncedLyrics and closer duration.
      Map<String, dynamic>? bestMatch;
      int bestScore = -1;

      for (final raw in results) {
        if (raw is! Map<String, dynamic>) continue;

        final synced = raw['syncedLyrics'] as String?;
        final plain = raw['plainLyrics'] as String?;
        if ((synced == null || synced.isEmpty) &&
            (plain == null || plain.isEmpty)) {
          continue;
        }

        int score = 0;
        if (synced != null && synced.isNotEmpty) {
          score += 10; // Prefer synced lyrics
        }

        final itemDur = raw['duration'] as num?;
        if (itemDur != null && durationSecs > 0) {
          final diff = (itemDur - durationSecs).abs();
          if (diff <= 2) {
            score += 5; // Close duration match
          } else if (diff <= 10) {
            score += 2;
          }
        }

        if (score > bestScore) {
          bestScore = score;
          bestMatch = raw;
        }
      }

      if (bestMatch != null) {
        final synced = bestMatch['syncedLyrics'] as String?;
        final plain = bestMatch['plainLyrics'] as String?;
        afLog(
          'lyrics',
          'lrclib.net: match found. ID=${bestMatch['id']} synced=${synced != null && synced.isNotEmpty}',
        );
        return (
          synced: synced != null && synced.trim().isNotEmpty
              ? synced.trim()
              : null,
          plain: plain != null && plain.trim().isNotEmpty ? plain.trim() : null,
        );
      }
    } catch (e, stack) {
      afLog('lyrics', 'lrclib.net: fetch failed', error: e, stackTrace: stack);
    }
    return null;
  }
}
