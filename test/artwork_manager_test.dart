import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show CoverArt;

import 'package:aetherfin/core/audio/artwork_manager.dart';
import 'package:aetherfin/core/jellyfin/models/items.dart';

class MockHttpClient extends Fake implements HttpClient {
  static int mockStatusCode = 200;
  static ContentType? mockContentType = ContentType.parse('image/jpeg');
  static final Map<String, String> recordedHeaders = {};

  @override
  Duration? connectionTimeout;
  @override
  Duration idleTimeout = const Duration(seconds: 15);

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    recordedHeaders.clear();
    return MockHttpClientRequest();
  }

  @override
  void close({bool force = false}) {}
}

class MockHttpClientRequest extends Fake implements HttpClientRequest {
  @override
  final HttpHeaders headers = MockHttpHeaders();

  @override
  Future<HttpClientResponse> close() async {
    return MockHttpClientResponse();
  }
}

class MockHttpHeaders extends Fake implements HttpHeaders {
  @override
  void set(
    String name,
    Object value, {
    bool preserveHeaderCase = false,
  }) {
    MockHttpClient.recordedHeaders[name] = value.toString();
  }

  @override
  ContentType? get contentType => MockHttpClient.mockContentType;
}

class MockHttpClientResponse extends StreamView<List<int>> implements HttpClientResponse {
  MockHttpClientResponse() : super(Stream<List<int>>.fromIterable([[1, 2, 3, 4]]));

  @override
  int get statusCode => MockHttpClient.mockStatusCode;

  @override
  final HttpHeaders headers = MockHttpHeaders();

  @override
  HttpClientResponseCompressionState get compressionState => HttpClientResponseCompressionState.notCompressed;

  @override
  int get contentLength => 4;

  @override
  bool get persistentConnection => true;

  @override
  bool get isRedirect => false;

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  String get reasonPhrase => 'OK';

  @override
  List<Cookie> get cookies => const [];

  @override
  Future<HttpClientResponse> redirect([String? method, Uri? url, bool? followLoops]) {
    throw UnimplementedError();
  }

  @override
  Future<E> drain<E>([E? defaultValue]) async {
    return defaultValue as E;
  }

  @override
  X509Certificate? get certificate => null;

  @override
  HttpConnectionInfo? get connectionInfo => null;

  @override
  Future<Socket> detachSocket() {
    throw UnimplementedError();
  }
}

class TestHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return MockHttpClient();
  }
}

void main() {
  setUpAll(() {
    HttpOverrides.global = TestHttpOverrides();
  });

  tearDownAll(() {
    HttpOverrides.global = null;
  });

  group('AfArtworkManager', () {
    late AfArtworkManager manager;

    setUp(() {
      manager = AfArtworkManager();
      MockHttpClient.mockStatusCode = 200;
      MockHttpClient.mockContentType = ContentType.parse('image/jpeg');
      MockHttpClient.recordedHeaders.clear();
    });

    tearDown(() {
      manager.dispose();
    });

    test('downloadArtworkForNotification does not delete embedded cover file', () async {
      // 1. Create and persist an embedded cover art.
      final cover = CoverArt(
        bytes: Uint8List.fromList([9, 9, 9, 9]),
        mimeType: 'image/jpeg',
      );
      await manager.persistCover(cover);

      final embeddedUri = manager.artUri(
        const AfTrack(
          id: 'track1',
          title: 'T',
          artistName: 'A',
          albumName: 'Al',
        ),
      );
      expect(embeddedUri, isNotNull);
      expect(embeddedUri!.isScheme('file'), isTrue);

      final embeddedFile = File(embeddedUri.toFilePath());
      expect(await embeddedFile.exists(), isTrue);

      // 2. Download remote artwork.
      const track = AfTrack(
        id: 'track1',
        title: 'T',
        artistName: 'A',
        albumName: 'Al',
        imageUrl: 'https://example.com/artwork.jpg',
      );
      await manager.downloadArtworkForNotification(track);

      // 3. Verify that the embedded cover art file STILL exists on disk.
      expect(
        await embeddedFile.exists(),
        isTrue,
        reason: 'Embedded cover art should not be deleted',
      );

      // Cleanup files
      try {
        await embeddedFile.delete();
      } catch (_) {}

      final finalUri = manager.artUri(track);
      if (finalUri != null && finalUri.isScheme('file')) {
        try {
          await File(finalUri.toFilePath()).delete();
        } catch (_) {}
      }
    });

    test('persistCover(null) clears cover path', () async {
      final cover = CoverArt(
        bytes: Uint8List.fromList([9, 9, 9, 9]),
        mimeType: 'image/jpeg',
      );
      await manager.persistCover(cover);

      const track = AfTrack(
        id: '1',
        title: 'T',
        artistName: 'A',
        albumName: 'Al',
      );
      expect(manager.artUri(track), isNotNull);

      await manager.persistCover(null);
      expect(manager.artUri(track), isNull);
    });

    test('downloadArtworkForNotification with file:// URL does not trigger download', () async {
      const track = AfTrack(
        id: 'track1',
        title: 'T',
        artistName: 'A',
        albumName: 'Al',
        imageUrl: 'file:///local/path/to/art.jpg',
      );

      await manager.downloadArtworkForNotification(track);

      // verify no request was recorded
      expect(MockHttpClient.recordedHeaders, isEmpty);
      expect(
        manager.artUri(track),
        equals(Uri.parse('file:///local/path/to/art.jpg')),
      );
    });

    test('downloadArtworkForNotification with non-200 response drains and returns early', () async {
      MockHttpClient.mockStatusCode = 404;

      const track = AfTrack(
        id: 'track1',
        title: 'T',
        artistName: 'A',
        albumName: 'Al',
        imageUrl: 'https://example.com/artwork.jpg',
      );

      await manager.downloadArtworkForNotification(track);
      expect(manager.artUri(track), isNull);
    });

    test('downloadArtworkForNotification deduplicates download for same track', () async {
      const track = AfTrack(
        id: 'track1',
        title: 'T',
        artistName: 'A',
        albumName: 'Al',
        imageUrl: 'https://example.com/artwork.jpg',
      );

      await manager.downloadArtworkForNotification(track);
      expect(manager.artUri(track), isNotNull);

      // Reset recorded headers
      MockHttpClient.recordedHeaders.clear();

      // Call again for the same track
      await manager.downloadArtworkForNotification(track);
      expect(
        MockHttpClient.recordedHeaders,
        isEmpty,
        reason: 'Should have returned early',
      );
    });

    test('needsRemoteArtwork correctly evaluates combinations', () {
      const trackNoUrl = AfTrack(
        id: '1',
        title: 'T',
        artistName: 'A',
        albumName: 'Al',
      );
      expect(manager.needsRemoteArtwork(trackNoUrl), isFalse);

      const trackFileUrl = AfTrack(
        id: '2',
        title: 'T',
        artistName: 'A',
        albumName: 'Al',
        imageUrl: 'file:///local.jpg',
      );
      expect(manager.needsRemoteArtwork(trackFileUrl), isFalse);

      const trackRemoteUrl = AfTrack(
        id: '3',
        title: 'T',
        artistName: 'A',
        albumName: 'Al',
        imageUrl: 'https://remote.jpg',
      );
      expect(manager.needsRemoteArtwork(trackRemoteUrl), isTrue);
    });

    test('artUri correctly prioritizes coverPath > networkCoverPath > file URL', () async {
      const track = AfTrack(
        id: 'track1',
        title: 'T',
        artistName: 'A',
        albumName: 'Al',
        imageUrl: 'file:///local/path.jpg',
      );

      // Case 3: Only track imageUrl is file://
      expect(
        manager.artUri(track),
        equals(Uri.parse('file:///local/path.jpg')),
      );

      // Case 2: Network artwork is downloaded
      final remoteTrack = AfTrack(
        id: 'track1',
        title: 'T',
        artistName: 'A',
        albumName: 'Al',
        imageUrl: 'https://example.com/artwork.jpg',
      );
      await manager.downloadArtworkForNotification(remoteTrack);
      final networkUri = manager.artUri(remoteTrack);
      expect(networkUri, isNotNull);
      expect(networkUri!.isScheme('file'), isTrue);

      // Case 1: Embedded artwork is persisted
      final cover = CoverArt(
        bytes: Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/jpeg',
      );
      await manager.persistCover(cover);
      final embeddedUri = manager.artUri(remoteTrack);
      expect(embeddedUri, isNotNull);
      expect(embeddedUri!.isScheme('file'), isTrue);
      expect(embeddedUri, isNot(equals(networkUri)));

      // Cleanup files
      try {
        await File(networkUri.toFilePath()).delete();
      } catch (_) {}
      try {
        await File(embeddedUri.toFilePath()).delete();
      } catch (_) {}
    });

    test('setAuthHeaders stores headers and sets them on requests', () async {
      manager.setAuthHeaders(const {'Authorization': 'Bearer token123'});

      const track = AfTrack(
        id: 'track1',
        title: 'T',
        artistName: 'A',
        albumName: 'Al',
        imageUrl: 'https://example.com/artwork.jpg',
      );

      await manager.downloadArtworkForNotification(track);
      expect(
        MockHttpClient.recordedHeaders['Authorization'],
        equals('Bearer token123'),
      );

      final uri = manager.artUri(track);
      if (uri != null && uri.isScheme('file')) {
        try {
          await File(uri.toFilePath()).delete();
        } catch (_) {}
      }
    });

    test('disposed guard blocks operations', () async {
      manager.dispose();

      final cover = CoverArt(
        bytes: Uint8List.fromList([9, 9, 9, 9]),
        mimeType: 'image/jpeg',
      );
      await manager.persistCover(cover);

      const track = AfTrack(
        id: 'track1',
        title: 'T',
        artistName: 'A',
        albumName: 'Al',
        imageUrl: 'https://example.com/artwork.jpg',
      );
      await manager.downloadArtworkForNotification(track);

      expect(manager.artUri(track), isNull);
    });
  });
}
