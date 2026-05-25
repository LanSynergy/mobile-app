import 'package:flutter/material.dart';
import 'package:aetherfin/design_tokens/tokens.dart';

// ---------------------------------------------------------------------------
// ShimmerWrap — animation engine for shimmer skeletons
// ---------------------------------------------------------------------------

/// Wraps a child widget and paints a shimmer sweep over it via [ShaderMask].
///
/// The sweep is a `LinearGradient` with three stops (transparent →
/// semi-transparent white → transparent) that moves from left (-1.0) to
/// right (2.0) over 1.5s, repeating indefinitely.
///
/// Each [ShimmerWrap] has its own [AnimationController] so multiple
/// skeleton primitives shimmer with a natural cascade effect.
class ShimmerWrap extends StatefulWidget {
  const ShimmerWrap({super.key, required this.child});

  /// The skeleton content to paint the shimmer over. Should be a
  /// [Container] with [AfColors.surfaceBase] fill and the desired shape.
  final Widget child;

  @override
  State<ShimmerWrap> createState() => _ShimmerState();
}

class _ShimmerState extends State<ShimmerWrap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // Map animation value 0→1 to gradient position -1.0→2.0
        final dx = -1.0 + (_controller.value * 3.0);

        // Clamp stops to [0, 1] so the gradient never wraps
        final stopA = (dx - 0.2).clamp(0.0, 1.0);
        final stopB = dx.clamp(0.0, 1.0);
        final stopC = (dx + 0.2).clamp(0.0, 1.0);

        return ShaderMask(
          shaderCallback: (bounds) {
            // Guard against zero/infinite bounds
            if (bounds.isEmpty || bounds.isInfinite) {
              return const LinearGradient(
                colors: [Colors.transparent, Colors.transparent],
              ).createShader(bounds);
            }
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              stops: [stopA, stopB, stopC],
              colors: const [
                Colors.transparent,
                Colors.white10,
                Colors.transparent,
              ],
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcOver,
          child: child!,
        );
      },
      child: widget.child,
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

  /// Fill color. Defaults to [AfColors.surfaceBase].
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ShimmerWrap(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: color ?? AfColors.surfaceBase,
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

  /// Fill color. Defaults to [AfColors.surfaceBase].
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ShimmerWrap(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: color ?? AfColors.surfaceBase,
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

  /// Fill color. Defaults to [AfColors.surfaceBase].
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ShimmerWrap(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color ?? AfColors.surfaceBase,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
