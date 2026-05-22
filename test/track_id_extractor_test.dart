import 'package:flutter_test/flutter_test.dart';

import 'package:aetherfin/core/audio/track_id_extractor.dart';

void main() {
  group('JellyfinTrackIdExtractor', () {
    const extractor = JellyfinTrackIdExtractor();

    test('extracts ID from /Audio/{id}/stream path', () {
      expect(
        extractor.extractId('https://server.com/Audio/123/stream'),
        '123',
      );
    });

    test('extracts ID from /Audio/{id}/stream with query params', () {
      expect(
        extractor.extractId('https://server.com/Audio/456/stream?static=true'),
        '456',
      );
    });

    test('extracts ID from id query parameter fallback', () {
      expect(
        extractor.extractId('https://server.com/Items/789/Download?id=789'),
        '789',
      );
    });

    test('returns null for unrecognized URLs', () {
      expect(
        extractor.extractId('https://server.com/not-audio/123'),
        isNull,
      );
    });

    test('returns null for empty string', () {
      expect(extractor.extractId(''), isNull);
    });

    test('returns null for invalid URI string', () {
      expect(extractor.extractId('not a uri at all !!!'), isNull);
    });
  });

  group('SubsonicTrackIdExtractor', () {
    const extractor = SubsonicTrackIdExtractor();

    test('extracts ID from /rest/stream.view?id=xxx', () {
      expect(
        extractor.extractId(
          'https://navidrome.server/rest/stream.view?id=abc123&u=user&t=token&s=1',
        ),
        'abc123',
      );
    });

    test('extracts ID from /rest/getCoverArt.view?id=xxx', () {
      expect(
        extractor.extractId(
          'https://navidrome.server/rest/getCoverArt.view?id=cover456',
        ),
        'cover456',
      );
    });

    test('returns null when no id param present', () {
      expect(
        extractor.extractId('https://navidrome.server/rest/stream.view'),
        isNull,
      );
    });

    test('returns null for empty string', () {
      expect(extractor.extractId(''), isNull);
    });
  });

  group('LocalTrackIdExtractor', () {
    const extractor = LocalTrackIdExtractor();

    test('extracts last segment from content:// URI', () {
      expect(
        extractor.extractId('content://media/external/audio/media/12345'),
        '12345',
      );
    });

    test('returns full file:// URI as-is', () {
      const uri = 'file:///storage/music/track.flac';
      expect(extractor.extractId(uri), uri);
    });

    test('returns plain path as-is', () {
      const uri = '/storage/music/track.flac';
      expect(extractor.extractId(uri), uri);
    });

    test('returns null for empty string', () {
      expect(extractor.extractId(''), isNull);
    });
  });
}
