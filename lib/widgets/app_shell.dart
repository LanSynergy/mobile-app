import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../design_tokens/tokens.dart';
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasMini = ref.watch(hasActivePlaybackProvider);
    final bottomNav = MediaQuery.of(context).padding.bottom;
    final miniBottom =
        AfSpacing.bottomNavHeight + bottomNav + AfSpacing.miniPlayerNavGap;

    return Scaffold(
      backgroundColor: AfColors.surfaceCanvas,
      extendBody: true,
      body: Stack(
        children: [
          // Tab content.
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: AfDurations.instant,
              switchInCurve: AfCurves.linear,
              switchOutCurve: AfCurves.linear,
              child: KeyedSubtree(
                key: ValueKey(shell.currentIndex),
                child: shell,
              ),
            ),
          ),

          // Floating mini-player.
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
