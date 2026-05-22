import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show CoverArt;

import 'package:aetherfin/core/audio/artwork_manager.dart';
import 'package:aetherfin/core/jellyfin/models/items.dart';

class MockHttpClient extends Fake implements HttpClient {
  @override
  Duration? connectionTimeout;
  @override
  Duration idleTimeout = const Duration(seconds: 15);

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
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
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  ContentType? get contentType => ContentType.parse('image/jpeg');
}

class MockHttpClientResponse extends Fake implements HttpClientResponse {
  @override
  int get statusCode => 200;

  @override
  final HttpHeaders headers = MockHttpHeaders();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final stream = Stream<List<int>>.fromIterable([
      [1, 2, 3, 4]
    ]);
    return stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
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
        const AfTrack(id: 'track1', title: 'T', artistName: 'A', albumName: 'Al'),
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
      expect(await embeddedFile.exists(), isTrue, reason: 'Embedded cover art should not be deleted');

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
  });
}
