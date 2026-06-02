import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/press_scale.dart';

class TransportButton extends StatelessWidget {
  const TransportButton({
    super.key,
    required this.icon,
    required this.onPressed,
  });

  final Widget icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onPressed,
      child: SizedBox(
        width: AfSpacing.minHitTarget,
        height: AfSpacing.minHitTarget,
        child: Center(child: icon),
      ),
    );
  }
}

class PlayButton extends ConsumerWidget {
  const PlayButton({super.key, required this.isPlaying});

  final bool isPlaying;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PressScale(
      onTap: () {
        final svc = ref.read(playerServiceProvider);
        if (isPlaying) {
          svc.pause();
        } else {
          svc.play();
        }
      },
      child: Container(
        width: 64,
        height: 64,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: AfColors.accentPrimary,
        ),
        child: Icon(
          isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          size: 32,
          color: AfColors.surfaceCanvas,
        ),
      ),
    );
  }
}
