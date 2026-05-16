import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../design_tokens/tokens.dart';
import '../features/sleep_timer/sleep_timer_screen.dart';
import '../state/providers.dart';
import 'bottom_nav.dart';
import 'mini_player.dart';

/// App shell — wraps every authed-app tab with the persistent 4-tab
/// bottom nav and the floating mini-player.
///
/// The mini-player is rendered as a `Positioned` overlay 16dp above the
/// bottom nav so it floats independently of the tab content (per
/// non-negotiable §4.1).
class AppShell extends ConsumerWidget {
  final StatefulNavigationShell shell;
  const AppShell({super.key, required this.shell});

  static const _items = [
    AfBottomNavItem(
      icon: Icons.home_outlined,
      filledIcon: Icons.home_rounded,
      label: 'Home',
    ),
    AfBottomNavItem(
      icon: Icons.search_outlined,
      filledIcon: Icons.search_rounded,
      label: 'Search',
    ),
    AfBottomNavItem(
      icon: Icons.library_music_outlined,
      filledIcon: Icons.library_music_rounded,
      label: 'Library',
    ),
    AfBottomNavItem(
      icon: Icons.person_outline_rounded,
      filledIcon: Icons.person_rounded,
      label: 'Profile',
    ),
  ];

  void _onSelect(BuildContext context, int index) {
    shell.goBranch(index, initialLocation: index == shell.currentIndex);
  }

  /// Android system back / gesture handler.
  ///
  /// Default `go_router` behaviour at a shell root is to pop the
  /// underlying `Navigator`, which has no entries — so the system back
  /// closes the app immediately. That's jarring when the user is two tabs
  /// deep and just wants to return to Home.
  ///
  /// Behaviour we want:
  ///   • Any non-Home tab → switch to Home (don't exit).
  ///   • Home tab → show "press back again to exit" confirmation.
  ///
  /// Implemented via `PopScope(canPop:false)` + `onPopInvokedWithResult`
  /// instead of `WillPopScope` (deprecated in Flutter 3.41).
  static DateTime? _lastBackPress;

  Future<bool> _onBackPressed(BuildContext context) async {
    if (shell.currentIndex != 0) {
      shell.goBranch(0);
      return false;
    }
    final now = DateTime.now();
    if (_lastBackPress != null &&
        now.difference(_lastBackPress!) < const Duration(seconds: 2)) {
      return true;
    }
    _lastBackPress = now;
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text('Press back again to exit'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
    return false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasMini = ref.watch(hasActivePlaybackProvider);
    final bottomNav = MediaQuery.of(context).padding.bottom;
    final miniBottom =
        AfSpacing.bottomNavHeight + bottomNav + AfSpacing.miniPlayerNavGap;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldExit = await _onBackPressed(context);
        if (shouldExit) {
          // We deliberately *do not* call `Navigator.of(context).pop()`
          // here — that would pop the (empty) shell navigator and crash.
          // `SystemNavigator.pop()` returns the user to the launcher,
          // matching the historical Android "back from root" behaviour.
          await SystemNavigator.pop();
        }
      },
      child: _buildScaffold(context, ref, hasMini, miniBottom),
    );
  }

  Widget _buildScaffold(
      BuildContext context, WidgetRef ref, bool hasMini, double miniBottom) {
    return Scaffold(
      backgroundColor: AfColors.surfaceCanvas,
      extendBody: true,
      // StackFit.expand ensures the Stack fills the Scaffold body even when
      // all children are Positioned (no non-positioned child to size from).
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Tab content fills the entire body area.
          // Must be first (bottom of stack) so overlays paint on top.
          shell,

          // Sleep timer watcher — zero-sized, invisible.
          // Kept as Positioned so it doesn't affect Stack sizing.
          const Positioned(
            width: 0,
            height: 0,
            child: SleepTimerWatcher(),
          ),

          // Floating mini-player overlay.
          if (hasMini)
            Positioned(
              left: 0,
              right: 0,
              bottom: miniBottom,
              child: MiniPlayer(
                onTap: () => context.push('/now-playing'),
                onPlayPause: () {
                  final svc = ref.read(playerServiceProvider);
                  if (svc.position == Duration.zero) {
                    svc.play();
                  } else {
                    final playing = ref
                        .read(playingStreamProvider)
                        .maybeWhen(data: (v) => v, orElse: () => false);
                    if (playing) {
                      svc.pause();
                    } else {
                      svc.play();
                    }
                  }
                },
                onSkipNext: () => ref.read(playerServiceProvider).skipToNext(),
              ),
            ),
        ],
      ),
      bottomNavigationBar: AfBottomNav(
        currentIndex: shell.currentIndex,
        onSelect: (i) => _onSelect(context, i),
        items: _items,
      ),
    );
  }
}
