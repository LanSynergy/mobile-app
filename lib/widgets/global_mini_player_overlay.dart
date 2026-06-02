import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/router.dart';
import '../design_tokens/tokens.dart';
import '../state/providers.dart';
import 'mini_player.dart';

class GlobalMiniPlayerOverlay extends ConsumerStatefulWidget {
  const GlobalMiniPlayerOverlay({super.key});

  @override
  ConsumerState<GlobalMiniPlayerOverlay> createState() =>
      _GlobalMiniPlayerOverlayState();
}

class _GlobalMiniPlayerOverlayState
    extends ConsumerState<GlobalMiniPlayerOverlay> {
  late final VoidCallback _routerListener;

  static const _hiddenLocations = {
    '/',
    '/now-playing',
    '/lyrics',
    '/queue',
    '/sleep',
    '/cast',
    '/settings',
    '/eq-dsp',
  };

  @override
  void initState() {
    super.initState();
    _routerListener = () {
      if (mounted) setState(() {});
    };
    appRouter.routerDelegate.addListener(_routerListener);
  }

  @override
  void dispose() {
    appRouter.routerDelegate.removeListener(_routerListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasMini = ref.watch(hasActivePlaybackProvider);
    if (!hasMini) return const SizedBox.shrink();

    final routeMatchList = appRouter.routerDelegate.currentConfiguration;
    final location = routeMatchList.isEmpty
        ? '/'
        : routeMatchList.last.matchedLocation;

    final isHidden =
        _hiddenLocations.contains(location) ||
        location.startsWith('/onboarding');
    final showMini = !isHidden && MediaQuery.of(context).viewInsets.bottom == 0;

    final bottomNav = MediaQuery.of(context).padding.bottom;
    final double targetBottom = bottomNav + AfSpacing.miniPlayerNavGap;

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
