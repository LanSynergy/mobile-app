import 'package:cupertino_liquid_glass/cupertino_liquid_glass.dart';
import 'package:flutter/material.dart';

import '../design_tokens/tokens.dart';

/// Frosted-glass card using [CupertinoLiquidGlass].
///
/// Real BackdropFilter blur + vibrancy + noise grain + inner shadow +
/// specular gradient + edge-lit border. Auto-adapts to dark mode.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.borderRadius = AfRadii.borderLg,
    this.blurSigma = 24,
    this.tintOpacity = 0.12,
    this.padding = const EdgeInsets.all(AfSpacing.s16),
    this.margin,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final double blurSigma;
  final double tintOpacity;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: CupertinoLiquidGlass(
        borderRadius: borderRadius,
        blurSigma: blurSigma,
        tintOpacity: tintOpacity,
        padding: padding,
        child: child,
      ),
    );
  }
}
