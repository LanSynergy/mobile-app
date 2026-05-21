import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';

class ReactiveBackground extends ConsumerWidget {
  const ReactiveBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spectral = ref.watch(currentSpectralProvider);
    return AnimatedContainer(
      duration: AfDurations.expressive,
      curve: AfCurves.easeStandard,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AfColors.surfaceCanvas, spectral.shadow],
          stops: const [0.4, 1.0],
        ),
      ),
      child: child,
    );
  }
}
