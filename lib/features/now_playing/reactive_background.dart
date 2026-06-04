import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../utils/oklch.dart';

/// Animated background that transitions between spectral-derived colors.
///
/// Watches [currentSpectralProvider] and smoothly animates the background
/// fill color when the artwork's dominant color changes.
///
/// Uses an explicit [ColorTween] so the transition from old → new color is
/// guaranteed to animate, even across rebuilds.
class ReactiveBackground extends ConsumerStatefulWidget {
  const ReactiveBackground({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<ReactiveBackground> createState() => _ReactiveBackgroundState();
}

class _ReactiveBackgroundState extends ConsumerState<ReactiveBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<Color?> _colorAnimation;
  Color _current = AfColors.surfaceCanvas;
  Color _target = AfColors.surfaceCanvas;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AfDurations.expressive,
    );
    _colorAnimation = ColorTween(begin: _current, end: _current).animate(
      CurvedAnimation(parent: _controller, curve: AfCurves.easeStandard),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final energy = ref.watch(currentSpectralProvider.select((s) => s.energy));
    final oklch = srgbToOklch(energy);
    final target = OklchColor(0.35, 0.12, oklch.h).toColor();

    if (target != _target) {
      _target = target;
      // Start the new tween from wherever the animation currently is,
      // not the previous target — avoids a jump if color changes mid-transition.
      _current = _colorAnimation.value ?? _current;
      _colorAnimation = ColorTween(begin: _current, end: target).animate(
        CurvedAnimation(parent: _controller, curve: AfCurves.easeStandard),
      );
      _controller
        ..reset()
        ..forward();
      _current = target;
    }

    final luminance = target.computeLuminance();
    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: luminance > 0.5
          ? Brightness.dark
          : Brightness.light,
      statusBarBrightness: luminance > 0.5 ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: luminance > 0.5
          ? Brightness.dark
          : Brightness.light,
      systemNavigationBarDividerColor: Colors.transparent,
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: AnimatedBuilder(
        animation: _colorAnimation,
        builder: (context, child) =>
            Container(color: _colorAnimation.value, child: child),
        child: widget.child,
      ),
    );
  }
}
