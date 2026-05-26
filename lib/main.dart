import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show MpvAudioKit;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'app/app.dart';
import 'app/router.dart'
    show notifyAuthChanged, resetRouterMode, setRouterAuthState;
import 'core/audio/player_service.dart';
import 'core/audio/player_settings_store.dart';
import 'core/local/app_mode_store.dart';
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
/// PII (usernames, server URLs) is redacted in release builds.
void _boot(String message) => afLog('boot', message);

Future<void> main() async {
  _boot('main() entered');
  // runZonedGuarded provides secondary error containment for synchronous
  // throws that escape the primary handlers below. It does NOT reliably
  // catch all async errors in Flutter (platform channel failures, engine
  // async exceptions, isolate errors). Primary handlers are:
  //   FlutterError.onError       — framework widget/render errors
  //   PlatformDispatcher.onError — uncaught async errors from Dart
  // runZonedGuarded is belt-and-suspenders only.
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      _boot('WidgetsFlutterBinding.ensureInitialized OK');

      // PRIMARY error handlers — these catch the vast majority of errors.
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

      // ── Phase 1: Storage / auth hydration ────────────────────────────────
      // Parallel reads so device-id and auth don't serialize.
      // Wrapped in a timeout so a hung keystore doesn't block boot forever.
      final storage = AuthStorage();
      String deviceId;
      JellyfinAuth? initialAuth;
      try {
        // Run the two storage reads concurrently. `Future.wait` collapses
        // to `List<Object>` for heterogeneous result types — we sequence
        // the device-id load first so the index→type mapping below is
        // unambiguous (no records here; the previous "Dart 3 destructuring"
        // comment was stale, the call site was list-based all along).
        final results =
            await Future.wait<Object?>([
              storage.loadOrCreateDeviceId(),
              storage.load(),
            ]).timeout(
              const Duration(seconds: 5),
              onTimeout: () => throw TimeoutException('storage timeout'),
            );
        deviceId = results[0]! as String;
        initialAuth = results[1] as JellyfinAuth?;
        // Redact username in release builds — logs may be shared in bug reports.
        _boot(
          'device id loaded (len=${deviceId.length}); '
          'auth ${initialAuth != null ? "restored" : "absent"}',
        );
      } catch (e, stack) {
        afLog(
          'error',
          'device id / auth load failed',
          error: e,
          stackTrace: stack,
        );
        deviceId = await _loadOrCreateFallbackDeviceId();
        initialAuth = null;
      }

      // Load persisted app mode (server | local | null).
      final persistedMode = await AppModeStore.load();
      _boot('appMode=${persistedMode?.name ?? "null"}');

      // Load persisted artwork pulse setting.
      final prefs = await SharedPreferences.getInstance();
      final artworkPulse = prefs.getBool('af.artwork_pulse_enabled') ?? true;
      _boot('artworkPulse=$artworkPulse');

      final localOnboardingCompleted =
          prefs.getBool('af.local_onboarding_completed') ?? false;
      _boot('localOnboardingCompleted=$localOnboardingCompleted');

      // Load offline cache settings.
      final offlineCacheEnabled =
          prefs.getBool('af.offline_cache_enabled') ?? false;
      final offlineCacheMaxSize =
          prefs.getInt('af.offline_cache_max_size') ?? (1024 * 1024 * 1024);
      final maxBitrate = prefs.getInt('af.max_bitrate_kbps') ?? 0;
      final autoplayEnabled = prefs.getBool('af.autoplay_enabled') ?? false;
      _boot(
        'offlineCacheEnabled=$offlineCacheEnabled maxSize=$offlineCacheMaxSize maxBitrate=$maxBitrate autoplayEnabled=$autoplayEnabled',
      );


      // Resolve the app version once at boot so every HTTP client can stamp
      // its `User-Agent` and Jellyfin `Version="…"` header from a single
      // source of truth (pubspec.yaml → platform manifest → PackageInfo).
      // `package_info_plus` is async (platform-channel lookup), but we're
      // already awaiting four async reads above in this phase, so adding
      // one more keeps boot ordering unchanged. The fallback string keeps
      // boot moving on the rare platforms where the channel times out
      // — it's preferable to ship a generic version than to crash startup.
      final aetherfinVersion = await _loadAetherfinVersion();
      _boot('aetherfinVersion=$aetherfinVersion');

      // ── Phase 2: Native media engine ─────────────────────────────────────
      // MPV must be initialized before any Player() is constructed.
      MpvAudioKit.ensureInitialized();
      _boot('MpvAudioKit.ensureInitialized OK');

      // ── Phase 3: OS audio service ─────────────────────────────────────────
      final handler = AfPlayerService();
      _boot('AfPlayerService initialized');

      // ── Phase 3.5: Apply persisted settings before any user interaction ───
      await PlayerSettingsStore.applyPersisted(handler);
      _boot('persisted settings applied');

      // ── Phase 4: Provider container + router wiring ───────────────────────
      _boot('calling runApp');
      final container = ProviderContainer(
        overrides: [
          deviceIdProvider.overrideWithValue(deviceId),
          initialAuthProvider.overrideWithValue(initialAuth),
          aetherfinVersionProvider.overrideWithValue(aetherfinVersion),
          if (persistedMode != null)
            appModeProvider.overrideWith((ref) => persistedMode),
          artworkPulseEnabledProvider.overrideWith((ref) => artworkPulse),
          offlineCacheEnabledProvider.overrideWith(
            (ref) => offlineCacheEnabled,
          ),
          offlineCacheMaxSizeProvider.overrideWith(
            (ref) => offlineCacheMaxSize,
          ),
          maxBitrateProvider.overrideWith((ref) => maxBitrate),
          autoplayEnabledProvider.overrideWith((ref) => autoplayEnabled),

          playerServiceProvider.overrideWith((ref) {
            wirePlayerService(ref, handler);
            return handler;
          }),
          localOnboardingCompletedProvider.overrideWith(
            (ref) => localOnboardingCompleted,
          ),
        ],
      );

      // Initialize offline cache service.
      try {
        final cacheSvc = container.read(offlineCacheServiceProvider);
        await cacheSvc.init();
        _boot('OfflineCacheService init OK');
      } catch (e, stack) {
        afLog(
          'error',
          'OfflineCacheService init failed',
          error: e,
          stackTrace: stack,
        );
      }

      // Seed the router with the initial auth/mode so its redirect runs
      // correctly on the very first frame.
      setRouterAuthState(
        auth: initialAuth,
        mode: persistedMode,
        localOnboardingCompleted: localOnboardingCompleted,
      );

      // Wire auth → router redirect. The subscription lives for the process
      // lifetime — it intentionally keeps `container` alive (which is fine
      // since `container` is the app's root provider scope). If the architecture
      // ever supports hot-restart of the provider tree, this subscription would
      // need to be disposed. Accept as-is for now.
      // ignore: unused_local_variable
      final authSub = container.listen<JellyfinAuth?>(authProvider, (
        prev,
        next,
      ) {
        setRouterAuthState(auth: next);
        notifyAuthChanged();
      }, fireImmediately: false);

      // Wire mode → router redirect. Without this, selecting "Play local
      // files" on the welcome screen updates appModeProvider but the
      // router's _appMode snapshot stays null — so after scanning,
      // context.go('/home') hits effectiveMode==null → redirect to '/'.
      //
      // When mode is cleared to null (mode switch, clear app data), explicitly
      // reset the router snapshot via resetRouterMode().  setRouterAuthState's
      // null guard prevents clearing _appMode through that path.
      // ignore: unused_local_variable
      final modeSub = container.listen<AppMode?>(appModeProvider, (prev, next) {
        setRouterAuthState(auth: container.read(authProvider), mode: next);
        if (next == null) {
          resetRouterMode();
        }
        notifyAuthChanged();
      }, fireImmediately: false);

      // Wire local onboarding completion → router redirect.
      // ignore: unused_local_variable
      final onboardingSub = container.listen<bool>(
        localOnboardingCompletedProvider,
        (prev, next) {
          setRouterAuthState(
            auth: container.read(authProvider),
            localOnboardingCompleted: next,
          );
          notifyAuthChanged();
        },
        fireImmediately: false,
      );

      runApp(
        UncontrolledProviderScope(
          container: container,
          child: const AetherfinApp(),
        ),
      );
      _boot('runApp returned');
    },
    (error, stack) {
      afLog('error', 'zoned uncaught', error: error, stackTrace: stack);
    },
  );
}

/// Resolve the running app version from the platform manifest.
///
/// Returns the value `package_info_plus` reads out of the Android
/// `versionName` (which Flutter wires from pubspec.yaml `version:`). The
/// `+buildNumber` suffix is stripped because the Jellyfin / Subsonic
/// `Version` field is meant for the semver triple, not the CI build
/// counter — a server-side log line of `Version="0.2.3"` is far more
/// useful than `Version="0.2.3+4"`.
///
/// On any failure (channel timeout, missing platform manifest, test mode)
/// returns a sentinel `'unknown'` rather than throwing, so a hung
/// PackageInfo doesn't take down boot. The provider override happens
/// before `runApp`, so by the time any HTTP client is constructed the
/// real value (or `'unknown'`) is already in the container.
Future<String> _loadAetherfinVersion() async {
  try {
    final info = await PackageInfo.fromPlatform().timeout(
      const Duration(seconds: 3),
      onTimeout: () => throw TimeoutException('PackageInfo timeout'),
    );
    final raw = info.version;
    if (raw.isEmpty) return 'unknown';
    // Strip a trailing `+buildNumber` if PackageInfo ever surfaces it.
    final plusIdx = raw.indexOf('+');
    return plusIdx < 0 ? raw : raw.substring(0, plusIdx);
  } catch (e, stack) {
    afLog(
      'error',
      'PackageInfo.fromPlatform failed; using fallback version string',
      error: e,
      stackTrace: stack,
    );
    return 'unknown';
  }
}

/// Read or generate the persistent fallback device ID.
///
/// Only used when `flutter_secure_storage` is unreachable (corrupt
/// keystore, brand-new device with no biometric setup, etc.). The ID
/// lives in plain `shared_preferences` — not as secure as the encrypted
/// store, but it's just a random opaque token (not a credential) and
/// having it survive launches is far more important than hiding it.
///
/// Uses UUID v4 (cryptographically random) instead of a timestamp so the
/// ID is not predictable even if an attacker knows the approximate boot time.
Future<String> _loadOrCreateFallbackDeviceId() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_fallbackDeviceIdKey);
    if (existing != null && existing.isNotEmpty) {
      _boot('fallback device id reused (len=${existing.length})');
      return existing;
    }
    // UUID v4 — cryptographically random, not timestamp-predictable.
    final fresh = 'aetherfin-fallback-${const Uuid().v4()}';
    await prefs.setString(_fallbackDeviceIdKey, fresh);
    _boot('fallback device id generated');
    return fresh;
  } catch (e, stack) {
    afLog(
      'error',
      'fallback device id load failed',
      error: e,
      stackTrace: stack,
    );
    // shared_preferences itself is unavailable — per-launch ID as last resort.
    return 'aetherfin-fallback-${const Uuid().v4()}';
  }
}

/// Last-line-of-defense error widget so the user always sees *something*
/// instead of a gray rectangle when a build throws.
///
/// In release builds: shows a generic message — exception strings may
/// contain server URLs, tokens, or internal state that shouldn't appear
/// on screen (shoulder-surfing, screenshots shared in bug reports).
/// In debug builds: shows the full exception for developer diagnosis.
class _RootErrorWidget extends StatelessWidget {
  const _RootErrorWidget({required this.details});
  final FlutterErrorDetails details;

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
                      // Release: generic message — no PII/tokens on screen.
                      // Debug: full exception for developer diagnosis.
                      kReleaseMode
                          ? 'An unexpected error occurred. Please restart the app.'
                          : details.exceptionAsString(),
                      style: const TextStyle(
                        color: AfColors.textSecondary,
                        fontSize: 13,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  kReleaseMode
                      ? 'Tap Restart on Android to retry.'
                      : 'Hot reload to retry.',
                  style: TextStyle(color: AfColors.textTertiary, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
