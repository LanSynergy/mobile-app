import 'package:flutter_test/flutter_test.dart';

import 'package:aetherfin/core/subsonic/client.dart';
import 'package:aetherfin/core/jellyfin/models/server.dart';

SubsonicClient _client({
  String baseUrl = 'http://srv:4533',
  String username = 'user1',
  String password = 'pass123Password',
  String clientVersion = '9.9.9-test',
}) {
  return SubsonicClient(
    server: JellyfinServer(baseUrl: baseUrl, name: 'srv'),
    username: username,
    password: password,
    clientVersion: clientVersion,
  );
}

void main() {
  group('trackStreamUrl', () {
    test(
      'uses format=raw and omits maxBitRate when maxBitrateKbps is null (Original / Lossless)',
      () {
        final url = _client().trackStreamUrl('track-1', maxBitrateKbps: null);
        final uri = Uri.parse(url);
        expect(uri.queryParameters['id'], 'track-1');
        expect(uri.queryParameters['format'], 'raw');
        expect(uri.queryParameters.containsKey('maxBitRate'), isFalse);
      },
    );

    test(
      'uses format=mp3 and sets maxBitRate when maxBitrateKbps is specified',
      () {
        final url = _client().trackStreamUrl('track-1', maxBitrateKbps: 256);
        final uri = Uri.parse(url);
        expect(uri.queryParameters['id'], 'track-1');
        expect(uri.queryParameters['format'], 'mp3');
        expect(uri.queryParameters['maxBitRate'], '256');
      },
    );

    test('includes standard subsonic query parameters (u, v, c, f, t, s)', () {
      final url = _client().trackStreamUrl('track-1');
      final uri = Uri.parse(url);
      expect(uri.queryParameters['u'], 'user1');
      expect(uri.queryParameters['v'], isNotEmpty);
      expect(uri.queryParameters['c'], 'Aetherfin');
      expect(uri.queryParameters['f'], 'json');
      expect(uri.queryParameters['t'], isNotEmpty);
      expect(uri.queryParameters['s'], isNotEmpty);
    });
  });
}
