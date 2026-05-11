import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/audio/player_service.dart';
import 'core/jellyfin/auth_storage.dart';
import 'core/jellyfin/models/server.dart';
import 'design_tokens/tokens.dart';
import 'state/providers.dart';

/// Boot breadcrumb — every checkpoint prefixes with this so a single
/// `adb logcat | grep aetherfin:boot` shows the full startup trace.
void _boot(String message) {
  // ignore: avoid_print
  print('aetherfin:boot $message');
}

/// A holder so the OS-integrated audio handler — once initialized — can be
/// injected into the Riverpod tree. Init runs in the background AFTER the
/// first frame so the UI is never blocked by audio_service warm-up.
final _handlerCompleter = Completer<AfPlayerService>();

Future<void> main() async {
  _boot('main() entered');
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    _boot('WidgetsFlutterBinding.ensureInitialized OK');

    // Surface framework errors to Logcat (always) AND keep a visible
    // breadcrumb on screen via [_RootErrorWidget]. Without this a single
    // thrown exception can leave the user staring at an empty surface.
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      // ignore: avoid_print
      print('aetherfin:error FlutterError: ${details.exceptionAsString()}');
      if (details.stack != null) {
        // ignore: avoid_print
        print('aetherfin:error stack: ${details.stack}');
      }
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      // ignore: avoid_print
      print('aetherfin:error PlatformDispatcher: $error');
      // ignore: avoid_print
      print('aetherfin:error stack: $stack');
      return true;
    };
    ErrorWidget.builder = (details) => _RootErrorWidget(details: details);
    _boot('error handlers installed');

    // Load the stable per-install device ID + the persisted auth blob
    // before mounting the app so every Jellyfin request uses the same
    // identifier from the very first frame, AND so the router can
    // immediately route an already-signed-in user past the welcome screen
    // to /home. Two sub-100 ms keystore reads — we await them in parallel
    // so they don't stack. If either fails (corrupt keystore, etc.) we
    // fall back gracefully rather than blocking the user.
    final storage = AuthStorage();
    String deviceId;
    JellyfinAuth? initialAuth;
    try {
      final results = await Future.wait([
        storage.loadOrCreateDeviceId(),
        storage.load(),
      ]);
      deviceId = results[0] as String;
      initialAuth = results[1] as JellyfinAuth?;
      _boot('device id loaded (len=${deviceId.length}); '
          'auth ${initialAuth != null ? "restored for ${initialAuth.userName}" : "absent"}');
    } catch (e, stack) {
      // ignore: avoid_print
      print('aetherfin:error device id / auth load failed: $e');
      // ignore: avoid_print
      print('aetherfin:error stack: $stack');
      // Last-ditch fallback so onboarding can still proceed. The cost is
      // that this install will look like a new device to Jellyfin on
      // every launch until secure storage starts working again.
      deviceId = 'aetherfin-fallback-${DateTime.now().microsecondsSinceEpoch}';
      initialAuth = null;
    }

    // Launch the UI immediately — audio init runs in the background AFTER
    // the first frame.
    _boot('calling runApp');
    runApp(
      ProviderScope(
        overrides: [
          deviceIdProvider.overrideWithValue(deviceId),
          initialAuthProvider.overrideWithValue(initialAuth),
          playerServiceProvider.overrideWith((ref) {
            // Until AudioService.init resolves, hand out a bare service so
            // the UI doesn't crash if it reads playerServiceProvider before
            // the OS-integrated handler is ready.
            final svc = AfPlayerService();
            ref.onDispose(svc.dispose);
            return svc;
          }),
        ],
        child: const AetherfinApp(),
      ),
    );
    _boot('runApp returned');

    // Schedule audio_service init AFTER the first frame is painted so we
    // are 100% sure the UI is alive before we touch the OS. If init fails
    // (e.g. on a stripped-down device), we log + carry on; the app still
    // works without lock-screen controls.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _boot('first frame painted — kicking AudioService init');
      unawaited(_warmUpAudio());
    });
  }, (error, stack) {
    // ignore: avoid_print
    print('aetherfin:error zoned uncaught: $error');
    // ignore: avoid_print
    print('aetherfin:error stack: $stack');
  });
}

Future<void> _warmUpAudio() async {
  try {
    _boot('AudioService.init starting');
    final handler = AfPlayerService();
    await AudioService.init(
      builder: () => handler,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'dev.aetherfin.audio',
        androidNotificationChannelName: 'Aetherfin playback',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
        notificationColor: Color(0xFF332C7A),
      ),
    );
    _boot('AudioService.init OK');
    if (!_handlerCompleter.isCompleted) {
      _handlerCompleter.complete(handler);
    }
  } catch (e, stack) {
    // ignore: avoid_print
    print('aetherfin:error AudioService.init failed: $e');
    // ignore: avoid_print
    print('aetherfin:error stack: $stack');
    // Don't rethrow — the UI must keep working even without OS audio
    // integration. The mini-player + Now Playing will still drive playback
    // via the in-app handler that was already wired through ProviderScope.
  }
}

/// Last-line-of-defense error widget so the user always sees *something*
/// (with the actual exception text) instead of a gray rectangle when a
/// build throws.
class _RootErrorWidget extends StatelessWidget {
  final FlutterErrorDetails details;
  const _RootErrorWidget({required this.details});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: AfColors.surfaceCanvas,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Aetherfin hit a snag',
                  style: TextStyle(
                    color: AfColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Text(
                      details.exceptionAsString(),
                      style: const TextStyle(
                        color: AfColors.textSecondary,
                        fontSize: 13,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  kReleaseMode
                      ? 'Tap Restart on Android to retry.'
                      : 'Hot reload to retry.',
                  style: const TextStyle(
                    color: AfColors.textTertiary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
