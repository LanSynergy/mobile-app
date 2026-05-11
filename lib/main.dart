import 'dart:async';
import 'dart:developer' as developer;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/audio/player_service.dart';
import 'design_tokens/tokens.dart';
import 'state/providers.dart';

/// A holder so the OS-integrated audio handler — once initialized — can be
/// injected into the Riverpod tree. Init runs in the background after the
/// first frame so the UI is never blocked by audio_service warm-up.
final _handlerCompleter = Completer<AfPlayerService>();

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Surface framework errors via Logcat AND keep a visible breadcrumb on
    // screen via [_RootErrorWidget]. Without this a single thrown exception
    // can leave the user staring at an empty surface.
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      developer.log(
        'FlutterError: ${details.exceptionAsString()}',
        name: 'aetherfin',
        error: details.exception,
        stackTrace: details.stack,
      );
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      developer.log(
        'PlatformDispatcher: $error',
        name: 'aetherfin',
        error: error,
        stackTrace: stack,
      );
      return true;
    };
    ErrorWidget.builder = (details) => _RootErrorWidget(details: details);

    // Launch the UI immediately — audio init runs in the background.
    runApp(
      ProviderScope(
        overrides: [
          playerServiceProvider.overrideWith((ref) {
            // Until AudioService.init resolves, hand out a bare service so the
            // UI doesn't crash if it reads playerServiceProvider before the
            // OS-integrated handler is ready. Once the OS handler arrives, it
            // is exposed to the rest of the tree via [audioHandlerProvider].
            final svc = AfPlayerService();
            ref.onDispose(svc.dispose);
            return svc;
          }),
        ],
        child: const AetherfinApp(),
      ),
    );

    // Warm up audio_service in the background — never block the UI on this.
    // If init fails (e.g. on a stripped-down device), we log + carry on; the
    // app still works without lock-screen controls.
    unawaited(_warmUpAudio());
  }, (error, stack) {
    developer.log(
      'Zoned uncaught: $error',
      name: 'aetherfin',
      error: error,
      stackTrace: stack,
    );
  });
}

Future<void> _warmUpAudio() async {
  try {
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
    if (!_handlerCompleter.isCompleted) {
      _handlerCompleter.complete(handler);
    }
  } catch (e, stack) {
    developer.log(
      'AudioService.init failed: $e',
      name: 'aetherfin',
      error: e,
      stackTrace: stack,
    );
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
