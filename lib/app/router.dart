import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show Provider;
import 'package:go_router/go_router.dart';

import '../core/jellyfin/models/server.dart';
import '../state/providers.dart';
import '../design_tokens/tokens.dart';
import '../features/album/album_screen.dart';
import '../features/artist/artist_screen.dart';
import '../features/cast_picker/cast_picker_screen.dart';
import '../features/genre/genre_screen.dart';
import '../features/home/home_screen.dart';
import '../features/library/library_screen.dart';
import '../features/lyrics/lyrics_screen.dart';
import '../features/now_playing/now_playing_screen.dart';
import '../features/now_playing/eq_dsp_screen.dart';
import '../features/onboarding/all_set_screen.dart';
import '../features/onboarding/library_scope_screen.dart';
import '../features/onboarding/local_setup_screen.dart';
import '../features/onboarding/server_discovery_screen.dart';
import '../features/onboarding/sign_in_screen.dart';
import '../features/onboarding/welcome_screen.dart';
import '../features/playlist/playlist_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/queue/queue_screen.dart';
import '../features/search/search_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/sleep_timer/sleep_timer_screen.dart';
import '../features/smart_playlist/smart_playlist_detail_screen.dart';
import '../features/smart_playlist/smart_playlist_edit_screen.dart';
import '../features/smart_playlist/smart_playlist_list_screen.dart';
import '../widgets/app_shell.dart';

// ─────────────────────────────────────────────────────────────────────────────
// All navigation state is module-level so it is created exactly once for
// the lifetime of the process. Recreating GoRouter or its navigator keys
// causes Duplicate GlobalKey errors and blanks all screens.
// ─────────────────────────────────────────────────────────────────────────────

final _rootKey = GlobalKey<NavigatorState>();
final _shellBranch1Key = GlobalKey<NavigatorState>();
final _shellBranch2Key = GlobalKey<NavigatorState>();
final _shellBranch3Key = GlobalKey<NavigatorState>();
final _shellBranch4Key = GlobalKey<NavigatorState>();
final _authRefresh = _AuthRefreshListenable();

/// Auth & mode snapshot for the router redirect. Set by [setRouterAuthState]
/// in main.dart before runApp, then kept in sync via provider listeners.
/// Exists as module-level vars instead of a ProviderContainer reference so
/// the router has zero dependency on the Riverpod container API.
JellyfinAuth? _auth;
AppMode? _appMode;
bool _localOnboardingCompleted = false;

/// The single [GoRouter] instance. Created once; never recreated.
final _router = GoRouter(
  navigatorKey: _rootKey,
  initialLocation: '/',
  refreshListenable: _authRefresh,
  redirect: (context, state) {
    final auth = _auth;
    final mode = _appMode;
    final loc = state.matchedLocation;
    final inOnboarding = loc == '/' || loc.startsWith('/onboarding');

    // Migration: if user has auth but no mode set (pre-local-mode install),
    // treat as server mode.
    final effectiveMode = mode ?? (auth != null ? AppMode.server : null);

    // Server mode: redirect based on auth state
    //
    // IMPORTANT: only redirect from '/' (fresh app launch with restored auth).
    // Do NOT redirect from within the onboarding flow (/onboarding/sign-in,
    // /onboarding/scope, etc.) — those screens navigate explicitly with
    // context.go().  A redirect there races with save(auth) → notifyAuthChanged
    // and skips the library scope screen entirely.
    if (effectiveMode == AppMode.server) {
      if (auth != null && loc == '/') {
        return '/home';
      }
      if (auth == null && !inOnboarding) return '/onboarding/discover';
    }

    // Local mode: redirect to home if onboarding is done.
    // Otherwise, redirect to local setup if we are in onboarding.
    if (effectiveMode == AppMode.local) {
      if (inOnboarding) {
        if (!_localOnboardingCompleted) {
          if (loc != '/onboarding/local-setup') return '/onboarding/local-setup';
        } else {
          return '/home';
        }
      }
    }

    // No mode chosen yet and no auth: stay on onboarding
    if (effectiveMode == null && !inOnboarding) return '/';

    return null;
  },
  routes: [
    // Onboarding
    GoRoute(path: '/', builder: (context, state) => const WelcomeScreen()),
    GoRoute(
      path: '/onboarding/discover',
      builder: (context, state) => const ServerDiscoveryScreen(),
    ),
    GoRoute(
      path: '/onboarding/local-setup',
      builder: (context, state) => const LocalSetupScreen(),
    ),
    GoRoute(
      path: '/onboarding/sign-in',
      builder: (_, state) {
        final extra = state.extra;
        if (extra is JellyfinServer) {
          return SignInScreen(server: extra);
        }
        if (extra is ({JellyfinServer server, ServerType serverType})) {
          return SignInScreen(
            server: extra.server,
            serverType: extra.serverType,
          );
        }
        return const Scaffold(
          body: Center(child: Text('Missing server information.')),
        );
      },
    ),
    GoRoute(
      path: '/onboarding/scope',
      builder: (context, state) => const LibraryScopeScreen(),
    ),
    GoRoute(
      path: '/onboarding/done',
      builder: (context, state) => const AllSetScreen(),
    ),

    // Shell — 4 tabs.
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AppShell(shell: shell),
      branches: [
        StatefulShellBranch(
          navigatorKey: _shellBranch1Key,
          routes: [
            GoRoute(
              path: '/home',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: HomeScreen()),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _shellBranch2Key,
          routes: [
            GoRoute(
              path: '/search',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: SearchScreen()),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _shellBranch3Key,
          routes: [
            GoRoute(
              path: '/library',
              pageBuilder: (_, state) {
                final raw = state.uri.queryParameters['section'];
                final section = raw == null
                    ? null
                    : LibrarySection.values
                          .where((s) => s.name == raw)
                          .firstOrNull;
                return NoTransitionPage(
                  child: LibraryScreen(initialSection: section),
                );
              },
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _shellBranch4Key,
          routes: [
            GoRoute(
              path: '/profile',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: ProfileScreen()),
            ),
          ],
        ),
      ],
    ),

    // Overlays above the shell.
    GoRoute(
      path: '/now-playing',
      parentNavigatorKey: _rootKey,
      pageBuilder: (context, state) => _NowPlayingPage(),
    ),
    GoRoute(
      path: '/lyrics',
      parentNavigatorKey: _rootKey,
      pageBuilder: (context, state) =>
          const NoTransitionPage(child: LyricsScreen()),
    ),
    GoRoute(
      path: '/queue',
      parentNavigatorKey: _rootKey,
      pageBuilder: (context, state) =>
          const NoTransitionPage(child: QueueScreen()),
    ),
    GoRoute(
      path: '/sleep',
      parentNavigatorKey: _rootKey,
      builder: (context, state) => const SleepTimerScreen(),
    ),
    GoRoute(
      path: '/cast',
      parentNavigatorKey: _rootKey,
      builder: (context, state) => const CastPickerScreen(),
    ),
    GoRoute(
      path: '/settings',
      parentNavigatorKey: _rootKey,
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/eq-dsp',
      parentNavigatorKey: _rootKey,
      builder: (context, state) => const EqDspScreen(),
    ),
    GoRoute(
      path: '/album/:id',
      parentNavigatorKey: _rootKey,
      builder: (_, state) => AlbumScreen(albumId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/artist/:id',
      parentNavigatorKey: _rootKey,
      builder: (_, state) =>
          ArtistScreen(artistId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/playlist/:id',
      parentNavigatorKey: _rootKey,
      builder: (_, state) =>
          PlaylistScreen(playlistId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/smart-playlists',
      parentNavigatorKey: _rootKey,
      builder: (context, state) => const SmartPlaylistListScreen(),
    ),
    GoRoute(
      path: '/smart-playlist/new',
      parentNavigatorKey: _rootKey,
      builder: (context, state) => const SmartPlaylistEditScreen(),
    ),
    GoRoute(
      path: '/smart-playlist/:id',
      parentNavigatorKey: _rootKey,
      builder: (_, state) =>
          SmartPlaylistDetailScreen(playlistId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/smart-playlist/:id/edit',
      parentNavigatorKey: _rootKey,
      builder: (_, state) =>
          SmartPlaylistEditScreen(playlistId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/genre/:name',
      parentNavigatorKey: _rootKey,
      builder: (_, state) => GenreScreen(
        genreName: Uri.decodeComponent(state.pathParameters['name']!),
      ),
    ),
  ],
);

/// Provides the singleton [GoRouter].
///
/// Auth-change and mode-change notifications are wired in [main.dart] via
/// [setRouterAuthState] and [notifyAuthChanged]. This provider exists only
/// for tests that need to read the router through Riverpod.
final routerProvider = Provider<GoRouter>((ref) {
  return _router;
});

/// Direct access to the singleton router for use in [AetherfinApp].
/// Prefer this over [routerProvider] to avoid unnecessary rebuilds.
GoRouter get appRouter => _router;

// ─────────────────────────────────────────────────────────────────────────────

class _AuthRefreshListenable extends ChangeNotifier {
  void _notify() => notifyListeners();
}

/// Called from main.dart to initialise auth/mode state before runApp,
/// and from provider listeners to keep the redirect snapshot in sync.
///
/// NOTE: the `if (mode != null)` guard is intentional — it prevents
/// `authSub` (which only passes auth) from accidentally clearing `_appMode`.
/// To explicitly clear mode to null, use [resetRouterMode].
void setRouterAuthState({
  JellyfinAuth? auth,
  AppMode? mode,
  bool? localOnboardingCompleted,
}) {
  _auth = auth;
  if (mode != null) _appMode = mode;
  if (localOnboardingCompleted != null) {
    _localOnboardingCompleted = localOnboardingCompleted;
  }
}

/// Explicitly clear the router's mode snapshot to null.
/// Used when the user switches modes or clears app data, so the redirect
/// doesn't read stale `_appMode` and skip onboarding.
void resetRouterMode() {
  _appMode = null;
  _localOnboardingCompleted = false;
}

/// Called from main.dart when auth/mode changes to trigger router redirect.
void notifyAuthChanged() => _authRefresh._notify();

class _NowPlayingPage extends Page<void> {
  @override
  Route<void> createRoute(BuildContext context) {
    return PageRouteBuilder<void>(
      settings: this,
      transitionDuration: AfDurations.expressive,
      reverseTransitionDuration: AfDurations.expressive,
      pageBuilder: (context, animation, secondaryAnimation) =>
          const NowPlayingScreen(),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final reduced = MediaQuery.of(context).disableAnimations;
        if (reduced) {
          return FadeTransition(opacity: animation, child: child);
        }
        final curved = CurvedAnimation(
          parent: animation,
          curve: AfCurves.easeEmphasized,
          reverseCurve: AfCurves.easeEmphasized,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );
  }
}
