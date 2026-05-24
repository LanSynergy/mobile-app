import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  static final _items = [
    const AfBottomNavItem(
      icon: LucideIcons.home,
      filledIcon: LucideIcons.home,
      label: 'Home',
    ),
    const AfBottomNavItem(
      icon: LucideIcons.search,
      filledIcon: LucideIcons.search,
      label: 'Search',
    ),
    const AfBottomNavItem(
      icon: LucideIcons.disc3,
      filledIcon: LucideIcons.disc3,
      label: 'Library',
    ),
    const AfBottomNavItem(
      icon: LucideIcons.user,
      filledIcon: LucideIcons.user,
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
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Full-bleed gradient background
          const RepaintBoundary(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF271640),
                    Color(0xFF040319),
                  ],
                  stops: [0.0, 1.0],
                ),
              ),
            ),
          ),

          // Tab content — transparent so gradient shows through
          RepaintBoundary(
            child: KeyedSubtree(
              key: const ValueKey('shell-content'),
              child: shell,
            ),
          ),

          // Sleep timer watcher — zero-sized, invisible.
          const Positioned(
            key: ValueKey('sleep-timer-watcher'),
            width: 0,
            height: 0,
            child: SleepTimerWatcher(),
          ),

          // Floating mini-player overlay.
          // Hidden when keyboard is open to avoid overlapping input fields.
          Positioned(
              key: const ValueKey('mini-player'),
              left: 0,
              right: 0,
              bottom: miniBottom,
              child: AnimatedSlide(
                offset: (hasMini && MediaQuery.of(context).viewInsets.bottom == 0)
                    ? Offset.zero
                    : const Offset(0, 2),
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: (hasMini && MediaQuery.of(context).viewInsets.bottom == 0)
                      ? 1.0
                      : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: IgnorePointer(
                    ignoring: !hasMini,
                    child: MiniPlayer(
                      onTap: () => context.push('/now-playing'),
                      onPlayPause: () {
                        // Toggle off mpv's own `playing` state — the only
                        // signal that stays correct in the first ~250 ms
                        // of a freshly-started track. The previous check
                        // (`position == Duration.zero`) would silently
                        // upgrade a tap-to-pause into a redundant play()
                        // whenever the user caught the track at 0:00.
                        final svc = ref.read(playerServiceProvider);
                        if (svc.isPlaying) {
                          svc.pause();
                        } else {
                          svc.play();
                        }
                      },
                      onSkipNext: () => ref.read(playerServiceProvider).skipToNext(),
                      onSkipPrevious: () =>
                          ref.read(playerServiceProvider).skipToPrevious(),
                    ),
                  ),
                ),
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
