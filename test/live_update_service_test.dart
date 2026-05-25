import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aetherfin/core/audio/live_update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> recordedCalls;

  setUp(() {
    recordedCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('aetherfin.live_update'),
          (MethodCall call) async {
            recordedCalls.add(call);
            if (call.method == 'isSupported' ||
                call.method == 'isSamsungDevice' ||
                call.method == 'requestPermission' ||
                call.method == 'start' ||
                call.method == 'update') {
              return true;
            }
            return null;
          },
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('aetherfin.live_update'),
          null,
        );
  });

  group('LiveUpdateService', () {
    test('isSupported invokes platform method', () async {
      final supported = await LiveUpdateService.isSupported();
      expect(supported, isTrue);
      expect(recordedCalls, hasLength(1));
      expect(recordedCalls.first.method, 'isSupported');
    });

    test('isSamsungDevice invokes platform method', () async {
      final isSamsung = await LiveUpdateService.isSamsungDevice();
      expect(isSamsung, isTrue);
      expect(recordedCalls, hasLength(1));
      expect(recordedCalls.first.method, 'isSamsungDevice');
    });

    test('requestPermission invokes platform method', () async {
      final granted = await LiveUpdateService.requestPermission();
      expect(granted, isTrue);
      expect(recordedCalls, hasLength(1));
      expect(recordedCalls.first.method, 'requestPermission');
    });

    test('start invokes platform method with correct arguments', () async {
      final result = await LiveUpdateService.start(
        title: 'Song Title',
        artist: 'Artist Name',
        durationMs: 180000,
        positionMs: 30000,
        isPlaying: true,
        shortCriticalText: '0:30 / 3:00',
        artworkPath: '/path/to/artwork.jpg',
      );

      expect(result, isTrue);
      expect(recordedCalls, hasLength(1));
      final call = recordedCalls.first;
      expect(call.method, 'start');
      expect(call.arguments['title'], 'Song Title');
      expect(call.arguments['artist'], 'Artist Name');
      expect(call.arguments['durationMs'], 180000);
      expect(call.arguments['positionMs'], 30000);
      expect(call.arguments['isPlaying'], isTrue);
      expect(call.arguments['shortCriticalText'], '0:30 / 3:00');
      expect(call.arguments['artworkPath'], '/path/to/artwork.jpg');
    });

    test('update invokes platform method with correct arguments', () async {
      final result = await LiveUpdateService.update(
        title: 'Song Title',
        artist: 'Artist Name',
        durationMs: 180000,
        positionMs: 40000,
        isPlaying: false,
        shortCriticalText: '0:40 / 3:00',
        artworkPath: null,
      );

      expect(result, isTrue);
      expect(recordedCalls, hasLength(1));
      final call = recordedCalls.first;
      expect(call.method, 'update');
      expect(call.arguments['title'], 'Song Title');
      expect(call.arguments['artist'], 'Artist Name');
      expect(call.arguments['durationMs'], 180000);
      expect(call.arguments['positionMs'], 40000);
      expect(call.arguments['isPlaying'], isFalse);
      expect(call.arguments['shortCriticalText'], '0:40 / 3:00');
      expect(call.arguments['artworkPath'], isNull);
    });

    test('stop invokes platform method', () async {
      await LiveUpdateService.stop();
      expect(recordedCalls, hasLength(1));
      expect(recordedCalls.first.method, 'stop');
    });

    test('formatDuration formats milliseconds correctly', () {
      expect(LiveUpdateService.formatDuration(0), '0:00');
      expect(LiveUpdateService.formatDuration(5000), '0:05');
      expect(LiveUpdateService.formatDuration(65000), '1:05');
      expect(LiveUpdateService.formatDuration(600000), '10:00');
    });
  });
}
