import 'dart:convert';
import 'dart:io';

import '../../utils/log.dart';

/// InnerTube client for YouTube Music home content.
///
/// Uses WEB_REMIX client identity (YouTube Music web app).
/// Visitor data fetched from /sw.js_data (not HTML page).
class InnerTubeClient {
  static const _baseUrl = 'https://music.youtube.com/youtubei/v1';
  static const _clientName = 'WEB_REMIX';
  static const _clientVersion = '1.20260213.01.00';
  static const _clientId = '67';
  static const _origin = 'https://music.youtube.com';
  static const _referer = '$_origin/';

  InnerTubeClient();

  String get _locale {
    final parts = Platform.localeName.split('_');
    final gl = parts.length >= 2 ? parts.last.toUpperCase() : 'US';
    final hl = parts.length >= 2 ? parts.first : 'en';
    return '$gl|$hl';
  }

  Map<String, dynamic> _buildContext({
    required String gl,
    required String hl,
    String? visitorData,
  }) {
    return {
      'client': {
        'clientName': _clientName,
        'clientVersion': _clientVersion,
        'hl': hl,
        'gl': gl,
        if (visitorData != null) 'visitorData': visitorData,
      },
    };
  }

  /// Fetches the YouTube Music home page content.
  Future<InnerTubeBrowseResponse?> browseHome({
    String? continuation,
    String? params,
  }) async {
    final parts = _locale.split('|');
    final gl = parts[0];
    final hl = parts[1];

    try {
      final visitorData = await _getVisitorData();
      print('[YT-INNERTUBE] visitorData=${visitorData != null ? "${visitorData.substring(0, 20)}..." : "null"}');

      final body = <String, dynamic>{
        'context': _buildContext(gl: gl, hl: hl, visitorData: visitorData),
        if (continuation == null) 'browseId': 'FEmusic_home',
        if (continuation == null && params != null) 'params': params,
        if (continuation != null) 'continuation': continuation,
      };

      final uri = Uri.parse('$_baseUrl/browse?prettyPrint=false');
      print('[YT-INNERTUBE] POST $uri');
      final client = HttpClient();

      try {
        final request = await client.postUrl(uri);

        // Headers matching Metrolist's InnerTube.kt ytClient()
        request.headers.set('Content-Type', 'application/json');
        request.headers.set('X-Goog-Api-Format-Version', '1');
        request.headers.set('X-YouTube-Client-Name', _clientId);
        request.headers.set('X-YouTube-Client-Version', _clientVersion);
        request.headers.set('X-Origin', _origin);
        request.headers.set('Referer', _referer);
        request.headers.set(
          'User-Agent',
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) '
          'Gecko/20100101 Firefox/140.0',
        );
        if (visitorData != null) {
          request.headers.set('X-Goog-Visitor-Id', visitorData);
        }

        request.write(jsonEncode(body));

        final response = await request.close();
        final responseBody = await response.transform(utf8.decoder).join();
        print('[YT-INNERTUBE] status=${response.statusCode} bodyLen=${responseBody.length}');

        if (response.statusCode != 200) {
          print('[YT-INNERTUBE] FAILED: ${responseBody.substring(0, responseBody.length > 500 ? 500 : responseBody.length)}');
          afLog('aetherfin:error',
              'InnerTube browse failed: ${response.statusCode}');
          return null;
        }

        final json = jsonDecode(responseBody) as Map<String, dynamic>;
        return InnerTubeBrowseResponse.fromJson(json);
      } finally {
        client.close();
      }
    } catch (e, stack) {
      afLog('aetherfin:error', 'InnerTube browse error',
          error: e, stackTrace: stack);
      return null;
    }
  }

  /// Browse a playlist by its browseId (e.g. "VLPLxxxx") and return track items.
  Future<List<InnerTubeItem>> browsePlaylist(String browseId) async {
    final parts = _locale.split('|');
    final gl = parts[0];
    final hl = parts[1];

    try {
      final visitorData = await _getVisitorData();

      final body = <String, dynamic>{
        'context': _buildContext(gl: gl, hl: hl, visitorData: visitorData),
        'browseId': browseId,
      };

      final uri = Uri.parse('$_baseUrl/browse?prettyPrint=false');
      final client = HttpClient();

      try {
        final request = await client.postUrl(uri);
        request.headers.set('Content-Type', 'application/json');
        request.headers.set('X-Goog-Api-Format-Version', '1');
        request.headers.set('X-YouTube-Client-Name', _clientId);
        request.headers.set('X-YouTube-Client-Version', _clientVersion);
        request.headers.set('X-Origin', _origin);
        request.headers.set('Referer', _referer);
        request.headers.set(
          'User-Agent',
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) '
          'Gecko/20100101 Firefox/140.0',
        );
        if (visitorData != null) {
          request.headers.set('X-Goog-Visitor-Id', visitorData);
        }

        request.write(jsonEncode(body));

        final response = await request.close();
        final responseBody = await response.transform(utf8.decoder).join();

        if (response.statusCode != 200) return [];

        final json = jsonDecode(responseBody) as Map<String, dynamic>;
        return _parsePlaylistItems(json);
      } finally {
        client.close();
      }
    } catch (e) {
      print('[YT-INNERTUBE] browsePlaylist error: $e');
      return [];
    }
  }

  /// Parse track items from a playlist browse response.
  List<InnerTubeItem> _parsePlaylistItems(Map<String, dynamic> json) {
    final items = <InnerTubeItem>[];
    try {
      // Find musicPlaylistShelfRenderer in any response layout.
      Map<String, dynamic>? shelf;

      // Layout 1: twoColumnBrowseResultsRenderer (playlists)
      final twoCol = json['contents']?['twoColumnBrowseResultsRenderer']
          as Map<String, dynamic>?;
      if (twoCol != null) {
        final secList = twoCol['secondaryContents']
            as Map<String, dynamic>?;
        final contents =
            secList?['sectionListRenderer']?['contents'] as List?;
        if (contents != null && contents.isNotEmpty) {
          shelf = contents[0]['musicPlaylistShelfRenderer']
              as Map<String, dynamic>?;
        }
      }

      // Layout 2: singleColumnBrowseResultsRenderer (artist/album pages)
      if (shelf == null) {
        final tabs =
            json['contents']?['singleColumnBrowseResultsRenderer']?['tabs']
                as List?;
        final tabContent = tabs?[0]?['tabRenderer']?['content'];
        shelf = tabContent?['musicPlaylistShelfRenderer']
            as Map<String, dynamic>?;
        shelf ??=
            tabContent?['musicShelfRenderer'] as Map<String, dynamic>?;
      }

      if (shelf != null) {
        final shelfContents = shelf['contents'] as List?;
        if (shelfContents != null) {
          for (final item in shelfContents) {
            final map = item as Map<String, dynamic>;
            final renderer =
                map['musicResponsiveListItemRenderer']
                    as Map<String, dynamic>?;
            if (renderer == null) continue;
            final parsed = InnerTubeItem.fromResponsive(renderer);
            if (parsed != null) items.add(parsed);
          }
        }
      }
    } catch (e) {
      print('[YT-INNERTUBE] _parsePlaylistItems error: $e');
    }
    return items;
  }

  /// Gets visitor data from /sw.js_data endpoint.
  /// This is how Metrolist (and the official YT Music app) obtains it.
  /// Response is prefixed with ")]}'" (5 chars), then a JSON array.
  Future<String?> _getVisitorData() async {
    try {
      final client = HttpClient();
      try {
        final request = await client.getUrl(
          Uri.parse('https://music.youtube.com/sw.js_data'),
        );
        request.headers.set(
          'User-Agent',
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) '
          'Gecko/20100101 Firefox/140.0',
        );
        request.headers.set('Accept', '*/*');
        request.headers.set('Referer', _referer);

        final response = await request.close();
        final raw = await response.transform(utf8.decoder).join();

        print('[YT-INNERTUBE] sw.js_data status=${response.statusCode} len=${raw.length}');
        if (response.statusCode == 200 && raw.length > 5) {
          // Strip the XSSI prefix ")]}'" and parse as JSON array.
          final jsonStr = raw.substring(5);
          final parsed = jsonDecode(jsonStr);
          // Navigate: parsed[0][2] is an array of strings/arrays.
          final outerArray = parsed as List;
          final innerArray = outerArray[0] as List;
          final candidates = innerArray[2] as List;
          // Find a string matching the visitor data pattern (starts with Cgt or Cgs).
          for (final candidate in candidates) {
            if (candidate is String &&
                (candidate.startsWith('Cgt') ||
                    candidate.startsWith('Cgs'))) {
              print('[YT-INNERTUBE] visitorData found: ${candidate.substring(0, 20)}...');
              return candidate;
            }
          }
          print('[YT-INNERTUBE] visitorData NOT found in candidates (${candidates.length} items)');
        }
      } finally {
        client.close();
      }
    } catch (e) {
      afLog('aetherfin:error', 'Failed to get visitor data', error: e);
    }
    return null;
  }
}

/// Filter chip from the home page.
class InnerTubeChip {
  const InnerTubeChip({required this.title, this.params});

  final String title;
  final String? params;
}

/// Parsed response from the InnerTube browse endpoint.
class InnerTubeBrowseResponse {
  InnerTubeBrowseResponse({
    required this.sections,
    this.continuation,
    this.chips = const [],
  });

  final List<InnerTubeSection> sections;
  final String? continuation;
  final List<InnerTubeChip> chips;

  factory InnerTubeBrowseResponse.fromJson(Map<String, dynamic> json) {
    final sections = <InnerTubeSection>[];
    final chips = <InnerTubeChip>[];
    String? continuation;

    try {
      final contents =
          json['contents']?['singleColumnBrowseResultsRenderer']?['tabs']
              as List?;
      final tabContent = contents?[0]?['tabRenderer']?['content'];
      final sectionList =
          tabContent?['sectionListRenderer'] as Map<String, dynamic>?;

      if (sectionList == null) {
        return InnerTubeBrowseResponse(sections: sections);
      }

      // Parse chips if available.
      final header = sectionList['header'] as Map<String, dynamic>?;
      final chipCloud = header?['chipCloudRenderer'] as Map<String, dynamic>?;
      final chipList = chipCloud?['chips'] as List?;
      if (chipList != null) {
        for (final chipItem in chipList) {
          final renderer =
              chipItem['chipCloudChipRenderer'] as Map<String, dynamic>?;
          if (renderer == null) continue;
          final textObj = renderer['text'] as Map<String, dynamic>?;
          final runs = textObj?['runs'] as List?;
          final title = runs?[0]?['text'] as String? ?? '';
          if (title.isEmpty) continue;

          final browseEndpoint = renderer['navigationEndpoint']
              ?['browseEndpoint'] as Map<String, dynamic>?;
          final params = browseEndpoint?['params'] as String?;
          chips.add(InnerTubeChip(title: title, params: params));
        }
      }

      // Parse continuation token.
      final conts = sectionList['continuations'] as List?;
      if (conts != null && conts.isNotEmpty) {
        final contData = conts[0] as Map<String, dynamic>?;
        continuation = contData?['nextContinuationData']?['continuation']
            as String?;
      }

      // Parse carousel sections.
      final sectionItems = sectionList['contents'] as List?;
      print('[YT-INNERTUBE] sectionItems count: ${sectionItems?.length ?? 0}');
      if (sectionItems != null) {
        for (final item in sectionItems) {
          final itemMap = item as Map<String, dynamic>;
          final keys = itemMap.keys.toList();
          print('[YT-INNERTUBE] section keys: $keys');

          final carousel =
              itemMap['musicCarouselShelfRenderer'] as Map<String, dynamic>?;
          if (carousel == null) {
            print('[YT-INNERTUBE] section: no musicCarouselShelfRenderer, keys=${itemMap.keys.toList()}');
            continue;
          }

          // Debug: dump header + first item
          final hdr = carousel['header'] as Map<String, dynamic>?;
          final hdrKeys = hdr?.keys.toList() ?? [];
          print('[YT-INNERTUBE] carousel header keys: $hdrKeys');
          final contentsList = carousel['contents'] as List?;
          print('[YT-INNERTUBE] carousel contents: ${contentsList?.length ?? 0} items');
          if (contentsList != null && contentsList.isNotEmpty) {
            final firstItem = contentsList[0] as Map<String, dynamic>;
            print('[YT-INNERTUBE] first item keys: ${firstItem.keys.toList()}');
          }

          final section = InnerTubeSection.fromCarousel(carousel);
          if (section != null) {
            print('[YT-INNERTUBE] parsed section: "${section.title}" (${section.items.length} items, types: ${section.items.map((i) => i.type.name).toList()})');
            sections.add(section);
          } else {
            print('[YT-INNERTUBE] fromCarousel returned null');
          }
        }
      }
    } catch (e) {
      afLog('aetherfin:error', 'InnerTube browse parse error', error: e);
    }

    return InnerTubeBrowseResponse(
      sections: sections,
      continuation: continuation,
      chips: chips,
    );
  }
}

/// A single section/carousel from the home page.
class InnerTubeSection {
  InnerTubeSection({required this.title, required this.items});

  final String title;
  final List<InnerTubeItem> items;

  static InnerTubeSection? fromCarousel(Map<String, dynamic> carousel) {
    try {
      final header = carousel['header'] as Map<String, dynamic>?;
      var headerRenderer =
          header?['musicCarouselShelfHeaderRenderer'] as Map<String, dynamic>?;
      headerRenderer ??= header?['musicCarouselShelfBasicHeaderRenderer']
          as Map<String, dynamic>?;

      final titleObj = headerRenderer?['title'];
      String title = '';
      if (titleObj is Map && titleObj['runs'] is List) {
        title = (titleObj['runs'] as List)
            .map((r) =>
                (r as Map<String, dynamic>)['text'] as String? ?? '')
            .join();
      } else if (titleObj is String) {
        title = titleObj;
      }

      final contents = carousel['contents'] as List?;
      if (contents == null || contents.isEmpty) return null;

      final items = <InnerTubeItem>[];
      for (final content in contents) {
        final contentMap = content as Map<String, dynamic>;

        final twoRow = contentMap['musicTwoRowItemRenderer']
            as Map<String, dynamic>?;
        if (twoRow != null) {
          final item = InnerTubeItem.fromTwoRow(twoRow);
          if (item != null) items.add(item);
          continue;
        }

        final listItem = contentMap['musicResponsiveListItemRenderer']
            as Map<String, dynamic>?;
        if (listItem != null) {
          final item = InnerTubeItem.fromResponsive(listItem);
          if (item != null) items.add(item);
        }
      }

      if (items.isEmpty) return null;
      return InnerTubeSection(title: title, items: items);
    } catch (e) {
      return null;
    }
  }
}

/// A single item in a section (song, album, playlist, artist).
class InnerTubeItem {
  InnerTubeItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.thumbnailUrl,
    required this.type,
    this.videoId,
    this.browseId,
  });

  final String id;
  final String title;
  final String subtitle;
  final String thumbnailUrl;
  final InnerTubeItemType type;
  final String? videoId;
  final String? browseId;

  static InnerTubeItem? fromTwoRow(Map<String, dynamic> renderer) {
    try {
      final titleRuns = renderer['title'] as Map<String, dynamic>?;
      final runs = titleRuns?['runs'] as List?;
      final title = runs?[0]?['text'] as String? ?? '';
      if (title.isEmpty) return null;

      final subtitleObj = renderer['subtitle'] as Map<String, dynamic>?;
      final subtitleRuns = subtitleObj?['runs'] as List?;
      final subtitle = subtitleRuns
              ?.map((r) =>
                  (r as Map<String, dynamic>)['text'] as String? ?? '')
              .join() ??
          '';

      final thumbnailRenderer =
          renderer['thumbnailRenderer'] as Map<String, dynamic>?;
      final musicThumb =
          thumbnailRenderer?['musicThumbnailRenderer'] as Map<String, dynamic>?;
      final thumbnailObj =
          musicThumb?['thumbnail'] as Map<String, dynamic>?;
      final thumbnails = thumbnailObj?['thumbnails'] as List?;
      final thumbnailUrl = thumbnails?.isNotEmpty == true
          ? (thumbnails!.last as Map<String, dynamic>)['url'] as String? ?? ''
          : '';

      final nav = renderer['navigationEndpoint'] as Map<String, dynamic>?;
      final watchEndpoint = nav?['watchEndpoint'] as Map<String, dynamic>?;
      final browseEndpoint = nav?['browseEndpoint'] as Map<String, dynamic>?;
      final configs = browseEndpoint?['browseEndpointContextSupportedConfigs']
          as Map<String, dynamic>?;
      final musicConfig =
          configs?['browseEndpointContextMusicConfig'] as Map<String, dynamic>?;
      final pageType = musicConfig?['pageType'] as String?;

      final videoId = watchEndpoint?['videoId'] as String?;

      InnerTubeItemType type;
      String id;

      if (watchEndpoint != null && videoId != null) {
        type = InnerTubeItemType.song;
        id = videoId;
      } else if (pageType == 'MUSIC_PAGE_TYPE_ALBUM') {
        type = InnerTubeItemType.album;
        id = browseEndpoint?['browseId'] as String? ?? '';
      } else if (pageType == 'MUSIC_PAGE_TYPE_PLAYLIST') {
        type = InnerTubeItemType.playlist;
        id = (browseEndpoint?['browseId'] as String? ?? '')
            .replaceFirst('VL', '');
      } else if (pageType == 'MUSIC_PAGE_TYPE_ARTIST') {
        type = InnerTubeItemType.artist;
        id = browseEndpoint?['browseId'] as String? ?? '';
      } else {
        return null;
      }

      if (id.isEmpty) return null;

      return InnerTubeItem(
        id: id,
        title: title,
        subtitle: subtitle,
        thumbnailUrl: thumbnailUrl,
        type: type,
        videoId: videoId,
        browseId: browseEndpoint?['browseId'] as String?,
      );
    } catch (e) {
      return null;
    }
  }

  static InnerTubeItem? fromResponsive(Map<String, dynamic> renderer) {
    try {
      final flexColumns = renderer['flexColumns'] as List?;
      final firstCol = flexColumns?[0] as Map<String, dynamic>?;
      final firstColRenderer =
          firstCol?['musicResponsiveListItemFlexColumnRenderer']
              as Map<String, dynamic>?;
      final textObj = firstColRenderer?['text'] as Map<String, dynamic>?;
      final runs = textObj?['runs'] as List?;
      final title = runs?[0]?['text'] as String? ?? '';
      if (title.isEmpty) return null;

      final secondCol = flexColumns?[1] as Map<String, dynamic>?;
      final secondColRenderer =
          secondCol?['musicResponsiveListItemFlexColumnRenderer']
              as Map<String, dynamic>?;
      final subTextObj =
          secondColRenderer?['text'] as Map<String, dynamic>?;
      final subRuns = subTextObj?['runs'] as List?;
      final subtitle = subRuns
              ?.map((r) =>
                  (r as Map<String, dynamic>)['text'] as String? ?? '')
              .join() ??
          '';

      final thumbnailObj = renderer['thumbnail'] as Map<String, dynamic>?;
      final musicThumb =
          thumbnailObj?['musicThumbnailRenderer'] as Map<String, dynamic>?;
      final thumbObj = musicThumb?['thumbnail'] as Map<String, dynamic>?;
      final thumbnails = thumbObj?['thumbnails'] as List?;
      final thumbnailUrl = thumbnails?.isNotEmpty == true
          ? (thumbnails!.last as Map<String, dynamic>)['url'] as String? ?? ''
          : '';

      // Try onTap first, then playlistItemData fallback.
      final onTap = renderer['onTap'] as Map<String, dynamic>?;
      final watchEndpoint =
          onTap?['watchEndpoint'] as Map<String, dynamic>?;
      var videoId = watchEndpoint?['videoId'] as String?;
      if (videoId == null) {
        final playlistItemData =
            renderer['playlistItemData'] as Map<String, dynamic>?;
        videoId = playlistItemData?['videoId'] as String?;
      }
      if (videoId == null) return null;

      return InnerTubeItem(
        id: videoId,
        title: title,
        subtitle: subtitle,
        thumbnailUrl: thumbnailUrl,
        type: InnerTubeItemType.song,
        videoId: videoId,
      );
    } catch (e) {
      return null;
    }
  }
}

enum InnerTubeItemType { song, album, playlist, artist }
