import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show MpvAudioKit;
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/router.dart' show notifyAuthChanged;
import 'core/audio/player_service.dart';
import 'core/jellyfin/auth_storage.dart';
import 'core/jellyfin/models/server.dart';
import 'design_tokens/tokens.dart';
import 'state/providers.dart';
import 'utils/log.dart';

/// Plain-prefs key for the fallback device ID used when the encrypted
/// secure-storage keystore can't be reached. Persisting the fallback
/// means even a permanently-broken keystore looks like the SAME device
/// across launches instead of a fresh one (which would create a stale
/// Jellyfin session per launch and trip the 500-on-AuthenticateByName
/// described in CLAUDE.md §5.1).
const _fallbackDeviceIdKey = 'aetherfin.deviceId.fallback.v1';

/// Boot breadcrumb — every checkpoint prefixes with this so a single
/// `adb logcat | grep aetherfin:boot` shows the full startup trace.
void _boot(String message) => afLog('boot', message);



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
      afLog(
        'error',
        'FlutterError: ${details.exceptionAsString()}',
        error: details.exception,
        stackTrace: details.stack,
      );
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      afLog(
        'error',
        'PlatformDispatcher uncaught: $error',
        error: error,
        stackTrace: stack,
      );
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
      afLog(
        'error',
        'device id / auth load failed',
        error: e,
        stackTrace: stack,
      );
      // Last-ditch fallback so onboarding can still proceed. Persist
      // the fallback ID to plain shared_preferences so it survives the
      // next launch even when secure_storage stays broken — otherwise
      // Jellyfin sees a new device on every launch and accumulates
      // stale sessions (the known cause of `AuthenticateByName` 500s).
      deviceId = await _loadOrCreateFallbackDeviceId();
      initialAuth = null;
    }

    // Initialize mpv_audio_kit's native backend BEFORE creating any Player
    // instances. This loads libmpv.so and cleans up any handles leaked
    // across a Flutter Hot-Restart. Must happen before AfPlayerService().
    MpvAudioKit.ensureInitialized();
    _boot('MpvAudioKit.ensureInitialized OK');

    // Initialize audio_service BEFORE runApp so the foreground service is
    // registered with the OS before any playback call can arrive.
    //
    // audio_service's builder() is called by the framework to create the
    // handler — we construct AfPlayerService() inside it so the same
    // instance is returned to both audio_service and Riverpod.
    late final AfPlayerService handler;
    try {
      _boot('AudioService.init starting');
      handler = await AudioService.init(
        builder: () {
          final svc = AfPlayerService();
          return svc;
        },
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'dev.aetherfin.audio',
          androidNotificationChannelName: 'Aetherfin playback',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
          notificationColor: Color(0xFF332C7A),
        ),
      );
      _boot('AudioService.init OK');
    } catch (e, stack) {
      afLog('error', 'AudioService.init failed', error: e, stackTrace: stack);
      // Fallback: create the handler without OS integration so the app
      // still works (in-app controls work, lock-screen controls won't).
      handler = AfPlayerService();
      _boot('AudioService.init failed — using bare handler');
    }

    _boot('calling runApp');
    final container = ProviderContainer(
      overrides: [
        deviceIdProvider.overrideWithValue(deviceId),
        initialAuthProvider.overrideWithValue(initialAuth),
        playerServiceProvider.overrideWith((ref) {
          wirePlayerService(ref, handler);
          return handler;
        }),
      ],
    );

    // Wire the auth → router redirect listener on the container directly.
    // This avoids putting ref.listen inside routerProvider which caused
    // routerProvider to rebuild on every auth change, triggering
    // MaterialApp.router to rebuild with a new routerConfig and causing
    // the "Duplicate GlobalKey" crash on StatefulNavigationShell.
    container.listen<JellyfinAuth?>(
      authProvider,
      (prev, next) => notifyAuthChanged(),
      fireImmediately: false,
    );

    runApp(
      UncontrolledProviderScope(
        container: container,
        child: const AetherfinApp(),
      ),
    );
    _boot('runApp returned');
  }, (error, stack) {
    afLog('error', 'zoned uncaught', error: error, stackTrace: stack);
  });
}

/// Read or generate the persistent fallback device ID.
///
/// Only used when `flutter_secure_storage` is unreachable (corrupt
/// keystore, brand-new device with no biometric setup, etc.). The ID
/// lives in plain `shared_preferences` — not as secure as the encrypted
/// store, but it's just a random opaque token (not a credential) and
/// having it survive launches is far more important than hiding it.
Future<String> _loadOrCreateFallbackDeviceId() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_fallbackDeviceIdKey);
    if (existing != null && existing.isNotEmpty) {
      _boot('fallback device id reused (len=${existing.length})');
      return existing;
    }
    final fresh =
        'aetherfin-fallback-${DateTime.now().microsecondsSinceEpoch}';
    await prefs.setString(_fallbackDeviceIdKey, fresh);
    _boot('fallback device id generated (len=${fresh.length})');
    return fresh;
  } catch (e, stack) {
    afLog(
      'error',
      'fallback device id load failed',
      error: e,
      stackTrace: stack,
    );
    // shared_preferences itself is unavailable — pick a per-launch ID
    // so the rest of the app still functions, even if Jellyfin sees a
    // new device every time. This branch is essentially unreachable on
    // a normal Android device.
    return 'aetherfin-fallback-${DateTime.now().microsecondsSinceEpoch}';
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
