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
import '../features/onboarding/all_set_screen.dart';
import '../features/onboarding/library_scope_screen.dart';
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

/// Stable navigator keys — declared at module level so they are never
/// recreated when [routerProvider] rebuilds on auth state changes.
/// Recreating these keys causes `Duplicate GlobalKey` errors because the
/// old [GoRouter] still holds a reference to the previous key while the
/// new one is being inserted into the tree.
final _rootKey = GlobalKey<NavigatorState>();
final _shellKey = GlobalKey<NavigatorState>();

/// Single source of truth for all in-app navigation.
///
/// Onboarding lives outside the shell so the bottom nav doesn't appear
/// before the user has chosen a library. All four tabs sit inside a
/// [StatefulShellRoute], which preserves each tab's stack across switches
/// (per design spec §11.6).
final routerProvider = Provider<GoRouter>((ref) {
  // Re-evaluate redirects whenever auth changes so signing in lands you on
  // /home and signing out drops you back at /.
  final refresh = _AuthRefreshListenable();
  ref.listen<JellyfinAuth?>(authProvider, (prev, next) => refresh._notify(),
      fireImmediately: false);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final loc = state.matchedLocation;
      final inOnboarding = loc == '/' || loc.startsWith('/onboarding');
      if (auth != null && inOnboarding) {
        // Already signed in — fast-forward past welcome / discovery.
        return '/home';
      }
      if (auth == null && !inOnboarding) {
        // No credentials — send the user through onboarding before we
        // try to render any post-auth screen (which would 401 anyway).
        return '/';
      }
      return null;
    },
    routes: [
      // Onboarding
      GoRoute(
        path: '/',
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/onboarding/discover',
        builder: (context, state) => const ServerDiscoveryScreen(),
      ),
      GoRoute(
        path: '/onboarding/sign-in',
        builder: (_, state) =>
            SignInScreen(server: state.extra! as JellyfinServer),
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
                      : LibrarySection.values.where((s) => s.name == raw).firstOrNull;
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

      // Top-level sheets / overlays (live above the shell).
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

      // Top-level album / artist routes. We register these above the shell
      // so that `context.push('/album/<id>')` and
      // `context.push('/artist/<id>')` resolve identically regardless of
      // which tab the user is currently on — code in widgets like
      // `library_screen.dart` and `home_screen.dart` pushes the bare path,
      // and previously hit `GoException: no routes for location: /artist/<id>`
      // because the routes were only registered as nested children of each
      // shell branch (e.g. `/home/artist/:id`). Living above the shell also
      // hides the bottom nav while the user is browsing detail screens.
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
        builder: (_, state) =>
            GenreScreen(genreName: Uri.decodeComponent(state.pathParameters['name']!)),
      ),
    ],
  );
});

/// Thin ChangeNotifier we hand to GoRouter so it re-runs `redirect` when
/// auth state flips. We can't pass `authProvider` directly because
/// GoRouter expects a Listenable and Riverpod providers are not Listenables.
class _AuthRefreshListenable extends ChangeNotifier {
  void _notify() => notifyListeners();
}

class _NowPlayingPage extends Page<void> {
  @override
  Route<void> createRoute(BuildContext context) {
    return PageRouteBuilder<void>(
      settings: this,
      transitionDuration: AfDurations.expressive,
      reverseTransitionDuration: AfDurations.expressive,
      pageBuilder: (context, animation, secondaryAnimation) => const NowPlayingScreen(),
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
