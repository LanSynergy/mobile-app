import 'package:dio/dio.dart';
import '../../utils/log.dart';
import '../network/shared_dio_client.dart';

/// Client for fetching lyrics from NetEase Cloud Music (music.163.com).
///
/// Flow: search for song by name/artist → fetch LRC lyrics by song ID.
/// Returns standard LRC format compatible with the existing parser.
class NetEaseClient {
  NetEaseClient({Dio? dio})
    : _dio =
          dio ??
          SharedDioClient().createWithOptions(
            BaseOptions(
              connectTimeout: const Duration(seconds: 5),
              sendTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
              headers: {
                'User-Agent':
                    'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36',
                'Referer': 'https://music.163.com',
              },
            ),
          );

  final Dio _dio;

  /// Fetches synced or plain lyrics for a track from NetEase Cloud Music.
  /// Returns a Map with keys 'synced', 'plain', and 'romaji' or null if not
  /// found.
  Future<({String? synced, String? plain, String? romaji})?> fetchLyrics({
    required String trackName,
    required String artistName,
    required String albumName,
    required Duration duration,
  }) async {
    if (trackName.isEmpty || artistName.isEmpty) return null;

    try {
      // Step 1: Search for the song to get the NetEase song ID
      final query = '$trackName $artistName';
      afLog('lyrics', 'Querying NetEase search: $query');

      final searchResponse = await _dio.get<Map<String, dynamic>>(
        'https://music.163.com/api/search/get',
        queryParameters: {
          's': query,
          'type': 1, // songs
          'limit': 5,
        },
      );

      final searchData = searchResponse.data;
      if (searchData == null || searchData['code'] != 200) {
        afLog('lyrics', 'NetEase: search failed or no results.');
        return null;
      }

      final result = searchData['result'] as Map<String, dynamic>?;
      final songs = result?['songs'] as List<dynamic>?;
      if (songs == null || songs.isEmpty) {
        afLog('lyrics', 'NetEase: no songs found for "$query".');
        return null;
      }

      // Pick the first matching song
      final songId = songs.first['id'] as int?;
      if (songId == null) {
        afLog('lyrics', 'NetEase: song ID is null.');
        return null;
      }

      afLog('lyrics', 'NetEase: found song ID=$songId');

      // Step 2: Fetch lyrics using the song ID
      final lyricsResponse = await _dio.get<Map<String, dynamic>>(
        'https://music.163.com/api/song/lyric',
        queryParameters: {
          'os': 'pc',
          'id': songId,
          'lv': -1, // original lyrics
          'tv': -1, // translated lyrics
        },
      );

      final lyricsData = lyricsResponse.data;
      if (lyricsData == null || lyricsData['code'] != 200) {
        afLog('lyrics', 'NetEase: lyrics fetch failed.');
        return null;
      }

      final lrc = lyricsData['lrc'] as Map<String, dynamic>?;
      final synced = lrc?['lyric'] as String?;

      // Log available lyrics fields for debugging
      final availableFields = lyricsData.keys.toList();
      afLog(
        'lyrics',
        'NetEase: response fields=$availableFields for song ID=$songId',
      );

      // Fetch romaji lyrics — try multiple possible fields
      final romaji = _extractRomaji(lyricsData);

      if (synced != null && synced.trim().isNotEmpty) {
        afLog(
          'lyrics',
          'NetEase: lyrics found. ID=$songId synced=${synced.isNotEmpty} romaji=${romaji != null}',
        );
        return (
          synced: synced.trim(),
          plain: null, // NetEase only returns LRC (synced) format
          romaji: romaji?.trim(),
        );
      }

      afLog('lyrics', 'NetEase: no lyrics content for song ID=$songId.');
    } on Exception catch (e, stack) {
      afLog('lyrics', 'NetEase: fetch failed', error: e, stackTrace: stack);
    }
    return null;
  }

  /// Extracts romaji lyrics from NetEase response, trying multiple fields.
  static String? _extractRomaji(Map<String, dynamic> data) {
    // Try romalrc first
    final romalrc = data['romalrc'] as Map<String, dynamic>?;
    final romaji = romalrc?['lyric'] as String?;
    if (romaji != null && romaji.trim().isNotEmpty) return romaji;

    // Try yrc (romanized lyrics)
    final yrc = data['yrc'] as Map<String, dynamic>?;
    final yrcText = yrc?['lyric'] as String?;
    if (yrcText != null && yrcText.trim().isNotEmpty) return yrcText;

    // Try klyric (korean lyrics, sometimes romanized)
    final klyric = data['klyric'] as Map<String, dynamic>?;
    final klyricText = klyric?['lyric'] as String?;
    if (klyricText != null && klyricText.trim().isNotEmpty) return klyricText;

    return null;
  }
}
