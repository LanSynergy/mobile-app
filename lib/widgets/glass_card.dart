import 'dart:ui';

import 'package:flutter/material.dart';

import '../design_tokens/tokens.dart';

/// Frosted-glass card — [ClipRRect] + [BackdropFilter] + semi-transparent fill.
///
/// Reusable across now-playing bottom content, top bar, or any overlay
/// that needs to read over album art / dynamic backgrounds.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.borderRadius = AfRadii.borderLg,
    this.blurSigma = 16,
    this.color = const Color(0x730A0A0A), // surfaceCanvas @ 45%
    this.borderColor,
    this.borderWidth = 0.5,
    this.padding = const EdgeInsets.all(AfSpacing.s16),
    this.margin,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final double blurSigma;
  final Color color;
  final Color? borderColor;
  final double borderWidth;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          margin: margin,
          padding: padding,
          decoration: BoxDecoration(
            color: color,
            borderRadius: borderRadius,
            border: borderColor != null
                ? Border.all(color: borderColor!, width: borderWidth)
                : null,
          ),
          child: child,
        ),
      ),
    );
  }
}
