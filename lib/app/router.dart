import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import '../features/onboarding/mode_select_screen.dart';
import '../features/onboarding/server_discovery_screen.dart';
import '../features/onboarding/sign_in_screen.dart';
import '../features/onboarding/welcome_screen.dart';
import '../features/playlist/playlist_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/queue/queue_screen.dart';
import '../features/search/search_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/sleep_timer/sleep_timer_screen.dart';
import '../widgets/app_shell.dart';

// ─────────────────────────────────────────────────────────────────────────────
// All navigation state is module-level so it is created exactly once for
// the lifetime of the process. Recreating GoRouter or its navigator keys
// causes Duplicate GlobalKey errors and blanks all screens.
// ─────────────────────────────────────────────────────────────────────────────

final _rootKey = GlobalKey<NavigatorState>();
final _shellKey = GlobalKey<NavigatorState>();
final _authRefresh = _AuthRefreshListenable();

// Container reference set by main.dart before runApp so the router's
// redirect can read auth state without depending on BuildContext.
ProviderContainer? _container;

/// The single [GoRouter] instance. Created once; never recreated.
final _router = GoRouter(
  navigatorKey: _rootKey,
  initialLocation: '/',
  refreshListenable: _authRefresh,
  redirect: (context, state) {
    final auth = _container?.read(authProvider);
    final loc = state.matchedLocation;
    final inOnboarding = loc == '/' || loc.startsWith('/onboarding');
    if (auth != null && inOnboarding) return '/home';
    if (auth == null && !inOnboarding) return '/';
    return null;
  },
  routes: [
    // Onboarding
    GoRoute(
      path: '/',
      builder: (context, state) => const WelcomeScreen(),
    ),
    GoRoute(
      path: '/onboarding/mode',
      builder: (context, state) => const ModeSelectScreen(),
    ),
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
        final extra = state.extra!;
        if (extra is JellyfinServer) {
          return SignInScreen(server: extra);
        }
        final rec = extra as ({JellyfinServer server, ServerType serverType});
        return SignInScreen(server: rec.server, serverType: rec.serverType);
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
          navigatorKey: _shellKey,
          routes: [
            GoRoute(
              path: '/home',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: HomeScreen()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/search',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: SearchScreen()),
            ),
          ],
        ),
        StatefulShellBranch(
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
      builder: (context, state) => const LyricsScreen(),
    ),
    GoRoute(
      path: '/queue',
      parentNavigatorKey: _rootKey,
      builder: (context, state) => const QueueScreen(),
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
      builder: (_, state) =>
          AlbumScreen(albumId: state.pathParameters['id']!),
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
      path: '/genre/:name',
      parentNavigatorKey: _rootKey,
      builder: (_, state) => GenreScreen(
          genreName:
              Uri.decodeComponent(state.pathParameters['name']!)),
    ),
  ],
);

/// Provides the singleton [GoRouter]. The provider itself never rebuilds
/// the router — it only wires the auth listener that notifies [_authRefresh]
/// so [_router.redirect] re-runs when auth state changes.
final routerProvider = Provider<GoRouter>((ref) {
  ref.listen<JellyfinAuth?>(
    authProvider,
    (prev, next) => _authRefresh._notify(),
    fireImmediately: false,
  );
  return _router;
});

/// Direct access to the singleton router for use in [AetherfinApp].
/// Prefer this over [routerProvider] to avoid unnecessary rebuilds.
GoRouter get appRouter => _router;

// ─────────────────────────────────────────────────────────────────────────────

class _AuthRefreshListenable extends ChangeNotifier {
  void _notify() => notifyListeners();
}

/// Called from main.dart to wire the container before runApp.
void setRouterContainer(ProviderContainer container) {
  _container = container;
}

/// Called from main.dart when auth state changes to trigger router redirect.
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
