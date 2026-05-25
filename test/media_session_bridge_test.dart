import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aetherfin/core/audio/media_session_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NativeMediaSessionBridge bridge;
  late List<MethodCall> recordedCalls;

  setUp(() {
    bridge = NativeMediaSessionBridge();
    recordedCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('aetherfin.media_session'),
          (MethodCall call) async {
            recordedCalls.add(call);
            return null;
          },
        );
  });

  tearDown(() {
    bridge.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('aetherfin.media_session'),
          null,
        );
  });

  group('NativeMediaSessionBridge', () {
    // -----------------------------------------------------------------------
    // pushState
    // -----------------------------------------------------------------------
    test('pushState sends updateState with correct arguments', () {
      bridge.pushState(
        const MediaSessionState(
          playing: true,
          buffering: false,
          position: Duration(seconds: 30),
          duration: Duration(seconds: 200),
          speed: 1.0,
          title: 'Test Song',
          artist: 'Test Artist',
          album: 'Test Album',
          artPath: '/tmp/cover.jpg',
          queueIndex: 0,
          queueSize: 10,
        ),
      );

      expect(recordedCalls, hasLength(1));
      final call = recordedCalls.first;
      expect(call.method, 'updateState');
      expect(call.arguments['playing'], isTrue);
      expect(call.arguments['buffering'], isFalse);
      expect(call.arguments['positionMs'], 30000);
      expect(call.arguments['durationMs'], 200000);
      expect(call.arguments['speed'], 1.0);
      expect(call.arguments['title'], 'Test Song');
      expect(call.arguments['artist'], 'Test Artist');
      expect(call.arguments['album'], 'Test Album');
      expect(call.arguments['artPath'], '/tmp/cover.jpg');
      expect(call.arguments['queueIndex'], 0);
      expect(call.arguments['queueSize'], 10);
    });

    test('pushState handles minimal state (no metadata)', () {
      bridge.pushState(
        const MediaSessionState(
          playing: false,
          buffering: true,
          position: Duration.zero,
          duration: Duration.zero,
          speed: 1.0,
          queueSize: 0,
        ),
      );

      expect(recordedCalls, hasLength(1));
      final call = recordedCalls.first;
      expect(call.method, 'updateState');
      expect(call.arguments['playing'], isFalse);
      expect(call.arguments['buffering'], isTrue);
      expect(call.arguments['title'], isNull);
      expect(call.arguments['artist'], isNull);
      expect(call.arguments['album'], isNull);
      expect(call.arguments['artPath'], isNull);
      expect(call.arguments['queueIndex'], isNull);
    });

    test('pushState handles null queueIndex', () {
      bridge.pushState(
        const MediaSessionState(
          playing: true,
          buffering: false,
          position: Duration.zero,
          duration: Duration(seconds: 100),
          speed: 1.0,
          title: 'No Index',
          queueSize: 5,
        ),
      );

      expect(recordedCalls, hasLength(1));
      expect(recordedCalls.first.arguments['queueIndex'], isNull);
    });

    // -----------------------------------------------------------------------
    // clear
    // -----------------------------------------------------------------------
    test('clear invokes clear method', () {
      bridge.clear();

      expect(recordedCalls, hasLength(1));
      expect(recordedCalls.first.method, 'clear');
      expect(recordedCalls.first.arguments, isNull);
    });

    // -----------------------------------------------------------------------
    // Platform callbacks (simulated from native side)
    // -----------------------------------------------------------------------
    test('platform play call triggers onPlay callback', () async {
      var played = false;
      bridge.onPlay = () {
        played = true;
      };

      await bridge.handleMethodCall(const MethodCall('play'));

      expect(played, isTrue);
    });

    test('platform pause call triggers onPause callback', () async {
      var paused = false;
      bridge.onPause = () {
        paused = true;
      };

      await bridge.handleMethodCall(const MethodCall('pause'));

      expect(paused, isTrue);
    });

    test('platform next call triggers onNext callback', () async {
      var next = false;
      bridge.onNext = () {
        next = true;
      };

      await bridge.handleMethodCall(const MethodCall('next'));

      expect(next, isTrue);
    });

    test('platform previous call triggers onPrevious callback', () async {
      var previous = false;
      bridge.onPrevious = () {
        previous = true;
      };

      await bridge.handleMethodCall(const MethodCall('previous'));

      expect(previous, isTrue);
    });

    test('platform stop call triggers onStop callback', () async {
      var stopped = false;
      bridge.onStop = () {
        stopped = true;
      };

      await bridge.handleMethodCall(const MethodCall('stop'));

      expect(stopped, isTrue);
    });

    test('platform seek call triggers onSeek with correct duration', () async {
      Duration? seekedTo;
      bridge.onSeek = (pos) {
        seekedTo = pos;
      };

      await bridge.handleMethodCall(
        const MethodCall('seek', {'positionMs': 5000}),
      );

      expect(seekedTo, const Duration(seconds: 5));
    });

    test(
      'platform skipTo call triggers onSkipToQueueItem with correct index',
      () async {
        int? skipToIdx;
        bridge.onSkipToQueueItem = (idx) {
          skipToIdx = idx;
        };

        await bridge.handleMethodCall(
          const MethodCall('skipTo', {'queueIndex': 3}),
        );

        expect(skipToIdx, 3);
      },
    );

    test(
      'platform toggleShuffle call triggers onToggleShuffle callback',
      () async {
        var toggled = false;
        bridge.onToggleShuffle = () {
          toggled = true;
        };

        await bridge.handleMethodCall(const MethodCall('toggleShuffle'));

        expect(toggled, isTrue);
      },
    );

    test('platform cycleRepeat call triggers onCycleRepeat callback', () async {
      var cycled = false;
      bridge.onCycleRepeat = () {
        cycled = true;
      };

      await bridge.handleMethodCall(const MethodCall('cycleRepeat'));

      expect(cycled, isTrue);
    });

    test(
      'platform toggleFavorite call triggers onToggleFavorite callback',
      () async {
        var toggled = false;
        bridge.onToggleFavorite = () {
          toggled = true;
        };

        await bridge.handleMethodCall(const MethodCall('toggleFavorite'));

        expect(toggled, isTrue);
      },
    );

    test(
      'platform shortcutAction call triggers onShortcutAction callback',
      () async {
        String? actionResult;
        bridge.onShortcutAction = (action) {
          actionResult = action;
        };

        await bridge.handleMethodCall(
          const MethodCall('shortcutAction', 'play_favorites'),
        );

        expect(actionResult, 'play_favorites');
      },
    );

    test(
      'getShortcutAction queries method channel and returns result',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('aetherfin.media_session'),
              (MethodCall call) async {
                if (call.method == 'getShortcutAction') {
                  return 'search_music';
                }
                return null;
              },
            );

        final action = await bridge.getShortcutAction();
        expect(action, 'search_music');
      },
    );

    test('unknown platform method throws PlatformException', () async {
      expect(
        () => bridge.handleMethodCall(const MethodCall('unknownMethod')),
        throwsA(
          isA<PlatformException>().having(
            (PlatformException e) => e.code,
            'code',
            'Unimplemented',
          ),
        ),
      );
    });

    // -----------------------------------------------------------------------
    // onArtworkNeeded
    // -----------------------------------------------------------------------
    test(
      'pushState fires onArtworkNeeded when artPath is null and needsArtworkDownload',
      () {
        var artworkNeeded = false;
        bridge.onArtworkNeeded = () {
          artworkNeeded = true;
        };

        bridge.pushState(
          const MediaSessionState(
            playing: true,
            buffering: false,
            position: Duration.zero,
            duration: Duration(seconds: 100),
            speed: 1.0,
            title: 'No Art',
            artist: 'Test',
            queueSize: 1,
            needsArtworkDownload: true,
          ),
        );

        expect(artworkNeeded, isTrue);
      },
    );

    test('pushState does NOT fire onArtworkNeeded when artPath is present', () {
      var artworkNeeded = false;
      bridge.onArtworkNeeded = () {
        artworkNeeded = true;
      };

      bridge.pushState(
        const MediaSessionState(
          playing: true,
          buffering: false,
          position: Duration.zero,
          duration: Duration(seconds: 100),
          speed: 1.0,
          title: 'Has Art',
          artist: 'Test',
          artPath: '/tmp/cover.jpg',
          queueSize: 1,
          needsArtworkDownload: true,
        ),
      );

      expect(artworkNeeded, isFalse);
    });

    test(
      'pushState does NOT fire onArtworkNeeded when needsArtworkDownload is false',
      () {
        var artworkNeeded = false;
        bridge.onArtworkNeeded = () {
          artworkNeeded = true;
        };

        bridge.pushState(
          const MediaSessionState(
            playing: true,
            buffering: false,
            position: Duration.zero,
            duration: Duration(seconds: 100),
            speed: 1.0,
            title: 'No Art Needed',
            artist: 'Test',
            queueSize: 1,
            needsArtworkDownload: false,
          ),
        );

        expect(artworkNeeded, isFalse);
      },
    );

    // -----------------------------------------------------------------------
    // Throttle behavior
    // -----------------------------------------------------------------------
    test('pushState throttles rapid calls with unchanged state', () {
      const state = MediaSessionState(
        playing: true,
        buffering: false,
        position: Duration.zero,
        duration: Duration(seconds: 200),
        speed: 1.0,
        title: 'Throttle Test',
        artist: 'Test',
        queueSize: 5,
      );

      bridge.pushState(state);
      bridge.pushState(state);
      bridge.pushState(state);

      // Only the first call should have been sent; subsequent calls
      // are within the throttle window with no state change.
      expect(recordedCalls, hasLength(1));
    });

    test('pushState sends immediately on playing state change', () {
      bridge.pushState(
        const MediaSessionState(
          playing: true,
          buffering: false,
          position: Duration.zero,
          duration: Duration(seconds: 200),
          speed: 1.0,
          title: 'State Change',
          artist: 'Test',
          queueSize: 5,
        ),
      );

      bridge.pushState(
        const MediaSessionState(
          playing: false, // changed
          buffering: false,
          position: Duration.zero,
          duration: Duration(seconds: 200),
          speed: 1.0,
          title: 'State Change',
          artist: 'Test',
          queueSize: 5,
        ),
      );

      expect(recordedCalls, hasLength(2));
    });

    test('pushState sends immediately on buffering state change', () {
      bridge.pushState(
        const MediaSessionState(
          playing: true,
          buffering: false,
          position: Duration.zero,
          duration: Duration(seconds: 200),
          speed: 1.0,
          title: 'Buffer Change',
          artist: 'Test',
          queueSize: 5,
        ),
      );

      bridge.pushState(
        const MediaSessionState(
          playing: true,
          buffering: true, // changed
          position: Duration.zero,
          duration: Duration(seconds: 200),
          speed: 1.0,
          title: 'Buffer Change',
          artist: 'Test',
          queueSize: 5,
        ),
      );

      expect(recordedCalls, hasLength(2));
    });

    test('pushState sends after throttle window expires', () async {
      const state = MediaSessionState(
        playing: true,
        buffering: false,
        position: Duration.zero,
        duration: Duration(seconds: 200),
        speed: 1.0,
        title: 'Throttle Expiry',
        artist: 'Test',
        queueSize: 5,
      );

      bridge.pushState(state); // 1st: sent
      bridge.pushState(state); // 2nd: throttled
      bridge.pushState(state); // 3rd: throttled

      await Future<void>.delayed(const Duration(milliseconds: 150));

      bridge.pushState(state); // 4th: sent (throttle window expired)

      expect(recordedCalls, hasLength(2));
    });

    // -----------------------------------------------------------------------
    // dispose
    // -----------------------------------------------------------------------
    test('dispose does not crash and nulls the method call handler', () {
      // Pre-dispose push works.
      bridge.pushState(
        const MediaSessionState(
          playing: true,
          buffering: false,
          position: Duration.zero,
          duration: Duration(seconds: 100),
          speed: 1.0,
          queueSize: 0,
        ),
      );

      bridge.dispose();

      // Post-dispose operations must not throw.
      bridge.pushState(
        const MediaSessionState(
          playing: false,
          buffering: false,
          position: Duration.zero,
          duration: Duration.zero,
          speed: 1.0,
          queueSize: 0,
        ),
      );
      bridge.clear();
      bridge.pushState(
        const MediaSessionState(
          playing: true,
          buffering: false,
          position: Duration.zero,
          duration: Duration.zero,
          speed: 1.0,
          queueSize: 0,
        ),
      );
      // No crash = pass.
    });

    test('callback is not required to be set', () async {
      // Should not throw even though callbacks are null.
      await bridge.handleMethodCall(const MethodCall('play'));
      await bridge.handleMethodCall(const MethodCall('pause'));
      await bridge.handleMethodCall(
        const MethodCall('seek', {'positionMs': 1000}),
      );
      await bridge.handleMethodCall(
        const MethodCall('skipTo', {'queueIndex': 0}),
      );

      // No assertions — must complete without error.
    });
  });
}
