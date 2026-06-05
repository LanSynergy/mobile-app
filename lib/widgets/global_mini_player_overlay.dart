import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/router.dart';
import '../design_tokens/tokens.dart';
import '../state/providers.dart';
import 'mini_player.dart';

/// Exposes only the current route location string — avoids full rebuilds
/// on every router delegate change.
final _currentRouteProvider = NotifierProvider<_CurrentRouteNotifier, String>(
  _CurrentRouteNotifier.new,
);

class _CurrentRouteNotifier extends Notifier<String> {
  late final VoidCallback _routerListener;

  @override
  String build() {
    _routerListener = () {
      final config = appRouter.routerDelegate.currentConfiguration;
      state = config.isEmpty ? '/' : config.last.matchedLocation;
    };
    _routerListener(); // seed initial value
    appRouter.routerDelegate.addListener(_routerListener);
    ref.onDispose(() {
      appRouter.routerDelegate.removeListener(_routerListener);
    });
    return '/';
  }
}

class GlobalMiniPlayerOverlay extends ConsumerWidget {
  const GlobalMiniPlayerOverlay({super.key});

  static const _hiddenLocations = {
    '/',
    '/now-playing',
    '/queue',
    '/sleep',
    '/cast',
    '/settings',
    '/eq-dsp',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasMini = ref.watch(hasActivePlaybackProvider);
    if (!hasMini) return const SizedBox.shrink();

    final location = ref.watch(_currentRouteProvider);

    final isHidden =
        _hiddenLocations.contains(location) ||
        location.startsWith('/onboarding');
    final showMini = !isHidden && MediaQuery.of(context).viewInsets.bottom == 0;

    final bottomNav = MediaQuery.of(context).padding.bottom;
    final double targetBottom =
        bottomNav + AfSpacing.bottomNavHeight + AfSpacing.miniPlayerNavGap;

    return AnimatedPositioned(
      left: 0,
      right: 0,
      bottom: targetBottom,
      duration: AfDurations.standard,
      curve: AfCurves.easeStandard,
      child: AnimatedOpacity(
        opacity: showMini ? 1.0 : 0.0,
        duration: AfDurations.quick,
        child: IgnorePointer(
          ignoring: !showMini,
          child: AnimatedSlide(
            offset: showMini ? Offset.zero : const Offset(0, 1.5),
            duration: AfDurations.standard,
            curve: AfCurves.easeStandard,
            child: MiniPlayer(
              onTap: () {
                final size = MediaQuery.of(context).size;
                final miniY =
                    size.height -
                    (bottomNav +
                        AfSpacing.bottomNavHeight +
                        AfSpacing.miniPlayerNavGap +
                        AfSpacing.miniPlayerHeight);
                final rect = Rect.fromLTWH(
                  AfSpacing.miniPlayerSideMargin,
                  miniY,
                  size.width - (AfSpacing.miniPlayerSideMargin * 2),
                  AfSpacing.miniPlayerHeight,
                );
                appRouter.push('/now-playing', extra: rect);
              },
              onPlayPause: () {
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
              onDismiss: () => ref.read(playerServiceProvider).stopAndClear(),
            ),
          ),
        ),
      ),
    );
  }
}
