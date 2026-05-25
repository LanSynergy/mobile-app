import 'package:flutter_test/flutter_test.dart';

import 'package:aetherfin/core/jellyfin/client.dart';
import 'package:aetherfin/core/jellyfin/models/server.dart';

JellyfinClient _client({
  String baseUrl = 'http://srv:8096',
  String? token,
  String? userId,
  String clientVersion = '9.9.9-test',
}) {
  return JellyfinClient(
    server: JellyfinServer(baseUrl: baseUrl, name: 'srv'),
    deviceId: 'dev-1',
    clientVersion: clientVersion,
    accessToken: token,
    userId: userId,
  );
}

void main() {
  group('trackStreamUrl', () {
    test('embeds api_key in URL for libmpv/FFmpeg compatibility', () {
      // FFmpeg's HTTP client rejects the MediaBrowser Authorization header
      // because it contains commas (used as field separators). Jellyfin
      // accepts api_key as an equivalent auth mechanism for media streams.
      final url = _client(
        token: 't-abc',
        userId: 'u-1',
      ).trackStreamUrl('track-1', maxBitrateKbps: 320);
      expect(
        url.contains('api_key=t-abc'),
        isTrue,
        reason: 'Token must be embedded as api_key for libmpv compatibility.',
      );
      expect(url.contains('Static=true'), isTrue);
      expect(url.contains('Audio/track-1/stream'), isTrue);
      expect(url.contains('MaxStreamingBitrate=320000'), isTrue);
    });

    test(
      'omits MaxStreamingBitrate when maxBitrateKbps is null (Original / Lossless)',
      () {
        final url = _client(
          token: 't-abc',
          userId: 'u-1',
        ).trackStreamUrl('track-1', maxBitrateKbps: null);
        expect(url.contains('MaxStreamingBitrate'), isFalse);
      },
    );

    test(
      'sets MaxStreamingBitrate correctly for other bitrates (e.g. 192 kbps)',
      () {
        final url = _client(
          token: 't-abc',
          userId: 'u-1',
        ).trackStreamUrl('track-1', maxBitrateKbps: 192);
        expect(url.contains('MaxStreamingBitrate=192000'), isTrue);
      },
    );

    test('URL-encodes path + query values', () {
      // Track IDs with `+` `=` `&` are unusual but exist in some libraries.
      final url = _client(userId: 'a+b=c&d').trackStreamUrl('xyz');
      final uri = Uri.parse(url);
      // The decoded userId must round-trip exactly through `queryParameters`.
      expect(uri.queryParameters['UserId'], 'a+b=c&d');
      // Raw query string must NOT contain the unencoded `+` / `=` / `&`
      // in the middle of the value.
      expect(
        uri.query.contains('UserId=a+b=c'),
        isFalse,
        reason: 'Plus / equals must be percent-encoded.',
      );
    });

    test('preserves nested base path (e.g. /jellyfin)', () {
      final url = _client(
        baseUrl: 'https://host.tld/jellyfin',
        userId: 'u-1',
      ).trackStreamUrl('track-2');
      expect(
        url.startsWith('https://host.tld/jellyfin/Audio/track-2/stream'),
        isTrue,
        reason: 'Server-relative base path must survive Uri.replace.',
      );
    });

    test('handles trailing slash on baseUrl', () {
      final url = _client(
        baseUrl: 'https://host.tld/',
        userId: 'u-1',
      ).trackStreamUrl('track-3');
      expect(url.startsWith('https://host.tld/Audio/track-3/stream'), isTrue);
      expect(
        url.contains('//Audio'),
        isFalse,
        reason: 'Must not produce `//Audio` from a trailing slash.',
      );
    });
  });

  group('authHeaders', () {
    test('returns Authorization with all required fields when authed', () {
      final headers = _client(token: 't-abc', userId: 'u-1').authHeaders;
      final auth = headers['Authorization'] ?? '';
      expect(auth.startsWith('MediaBrowser '), isTrue);
      expect(auth.contains('UserId="u-1"'), isTrue);
      expect(auth.contains('Token="t-abc"'), isTrue);
      expect(auth.contains('Client="Aetherfin"'), isTrue);
      expect(auth.contains('Device="Android"'), isTrue);
      expect(auth.contains('DeviceId="dev-1"'), isTrue);
      // Version flows in via the `clientVersion` constructor param, which
      // in production is loaded from `package_info_plus` in `main()` and
      // injected through `aetherfinVersionProvider`. We pin a sentinel
      // value in `_client()` so this assertion stays stable as pubspec
      // bumps — the test guards the wiring, not the literal version.
      expect(auth.contains('Version="9.9.9-test"'), isTrue);
    });

    test('omits Authorization entirely when no token', () {
      final headers = _client().authHeaders;
      expect(headers.containsKey('Authorization'), isFalse);
    });

    test('escapes quote / backslash / CR / LF in user-supplied values', () {
      // A malicious server returns a userId with `"` so the attacker
      // could inject Token="…", Client="evil" if we didn't escape.
      final auth = _client(
        token: 'safe',
        userId: r'evil",X="y',
      ).authHeaders['Authorization']!;
      // Must not introduce a real `X="y` field — the injection should be
      // neutralized by escaping the inner quotes.
      expect(auth.contains(', X="y'), isFalse);
      // Newlines must be stripped so header smuggling is impossible.
      final crlf = _client(
        token: "abc\r\nX-Evil: hi",
        userId: 'u',
      ).authHeaders['Authorization']!;
      expect(crlf.contains('\n'), isFalse);
      expect(crlf.contains('\r'), isFalse);
    });
  });
}
