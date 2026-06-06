import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_shaders_ui/flutter_shaders_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../design_tokens/tokens.dart';
import '../features/sleep_timer/sleep_timer_screen.dart';
import '../state/providers.dart';
import 'bottom_nav.dart';

/// App shell — wraps every authed-app tab with the persistent 4-tab
/// bottom nav.
///
/// Design:
///   - Full-bleed gradient background: deep dark (#0A0A0A → #111111)
///   - Tab content with AnimatedSwitcher cross-fade
///   - Sleep timer watcher (zero-sized, invisible)
///   - Bottom nav bar
///   - PopScope for Android back handling (non-Home → Home; Home → exit)
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  static final _items = [
    const AfBottomNavItem(icon: LucideIcons.home, label: 'Home'),
    const AfBottomNavItem(icon: LucideIcons.library, label: 'Library'),
    const AfBottomNavItem(icon: LucideIcons.listMusic, label: 'Playlists'),
    const AfBottomNavItem(icon: LucideIcons.user, label: 'Profile'),
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
            duration: AfDurations.snackBarInfo,
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
    return false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch spectral for a dynamic accent on the bottom nav pill.
    final spectral = ref.watch(
      currentSpectralProvider.select(
        (s) => (shadow: s.shadow, energy: s.energy),
      ),
    );

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
      child: _buildScaffold(
        context,
        ref,
        shadow: spectral.shadow,
        energy: spectral.energy,
      ),
    );
  }

  Widget _buildScaffold(
    BuildContext context,
    WidgetRef ref, {
    required Color shadow,
    required Color energy,
  }) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Full-bleed background — GPU shader (zero banding)
          Positioned.fill(
            child: WaveBackground(
              color1: shadow,
              color2: AfColors.surfaceCanvas,
              amplitude: 0.15,
              speed: 0.3,
            ),
          ),

          // Tab content — transparent so gradient shows through.
          // AnimatedSwitcher cross-fades between tab changes.
          RepaintBoundary(
            child: AnimatedSwitcher(
              duration: AfDurations.quick,
              switchInCurve: AfCurves.easeOut,
              switchOutCurve: AfCurves.easeIn,
              child: KeyedSubtree(
                key: ValueKey('shell-tab-${shell.currentIndex}'),
                child: shell,
              ),
            ),
          ),

          // Sleep timer watcher — zero-sized, invisible.
          const Positioned(
            key: ValueKey('sleep-timer-watcher'),
            width: 0,
            height: 0,
            child: SleepTimerWatcher(),
          ),
        ],
      ),
      bottomNavigationBar: AfBottomNav(
        currentIndex: shell.currentIndex,
        onSelect: (i) => _onSelect(context, i),
        items: _items,
        accentColor: energy,
      ),
    );
  }
}
