import 'package:flutter/material.dart';
import 'package:flutter_shaders_ui/flutter_shaders_ui.dart';

import '../design_tokens/tokens.dart';

// ---------------------------------------------------------------------------
// ShimmerWrap — animation engine for shimmer skeletons
// ---------------------------------------------------------------------------

/// Wraps a child widget and paints a shimmer sweep over it via
/// [ShimmerEffect].
class ShimmerWrap extends StatelessWidget {
  const ShimmerWrap({super.key, required this.child});

  /// The skeleton content to paint the shimmer over. Should be a
  /// [Container] with [AfColors.surfaceRaised] fill and the desired shape.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ShimmerEffect(
      color: Colors.white.withValues(alpha: 0.06),
      speed: 1.0,
      width: 0.35,
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// SkeletonBar — rectangular bar (for text lines, labels, metadata)
// ---------------------------------------------------------------------------

/// A rectangular skeleton bar with shimmer animation.
///
/// Use for text lines, labels, metadata, and other linear placeholders.
class SkeletonBar extends StatelessWidget {
  const SkeletonBar({
    super.key,
    this.width,
    this.height = 14.0,
    this.borderRadius,
    this.color,
  });

  /// Width of the bar. `null` means fill the parent width.
  final double? width;

  /// Height of the bar. Default 14dp.
  final double height;

  /// Border radius. Defaults to [AfRadii.borderSm].
  final BorderRadiusGeometry? borderRadius;

  /// Fill color. Defaults to [AfColors.surfaceRaised].
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ShimmerWrap(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: color ?? AfColors.surfaceRaised,
          borderRadius: borderRadius ?? AfRadii.borderSm,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SkeletonBlock — larger area (for artwork, hero images, cards)
// ---------------------------------------------------------------------------

/// A rectangular skeleton block with shimmer animation.
///
/// Use for artwork placeholders, hero images, card areas, and full-width
/// sections. Unlike [SkeletonBar], [width] is required.
class SkeletonBlock extends StatelessWidget {
  const SkeletonBlock({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius,
    this.color,
  });

  /// Width of the block. Required (unlike [SkeletonBar]).
  final double width;

  /// Height of the block.
  final double height;

  /// Border radius. Defaults to [AfRadii.borderMd].
  final BorderRadiusGeometry? borderRadius;

  /// Fill color. Defaults to [AfColors.surfaceRaised].
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ShimmerWrap(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: color ?? AfColors.surfaceRaised,
          borderRadius: borderRadius ?? AfRadii.borderMd,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SkeletonCircle — circular (for avatars, icon placeholders)
// ---------------------------------------------------------------------------

/// A circular skeleton shape with shimmer animation.
///
/// Use for artist avatars, user profile pictures, and icon placeholders.
class SkeletonCircle extends StatelessWidget {
  const SkeletonCircle({super.key, required this.size, this.color});

  /// Diameter of the circle.
  final double size;

  /// Fill color. Defaults to [AfColors.surfaceRaised].
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ShimmerWrap(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color ?? AfColors.surfaceRaised,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
