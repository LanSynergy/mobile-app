import 'package:flutter/material.dart';

import '../design_tokens/tokens.dart';

/// Replaces Material's default ripple with the Aetherfin press grammar:
/// a brief 0.97 scale-down on press + an optional tint shift on the child.
///
/// Per §7.1 / motion §7.2 — Material ripple is OFF GLOBALLY in the theme;
/// every tappable element should wrap its target in [PressScale] (or its
/// helper variants) so we keep press feedback consistent.
class PressScale extends StatefulWidget {

  const PressScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.duration = AfDurations.instant,
    this.pressedScale = 0.97,
    this.behavior = HitTestBehavior.opaque,
    this.ensureHitTarget = true,
  });
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Duration duration;
  final double pressedScale;
  final HitTestBehavior behavior;

  /// Minimum hit-target enforcement. Defaults to true — every tap target
  /// inflates to 48×48 dp via transparent padding.
  final bool ensureHitTarget;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: widget.duration,
    reverseDuration: const Duration(milliseconds: 120),
    lowerBound: 0,
    upperBound: 1,
  );

  late final Animation<double> _scale = Tween<double>(
    begin: 1,
    end: widget.pressedScale,
  ).animate(CurvedAnimation(
    parent: _ctrl,
    curve: AfCurves.easeStandard,
  ));

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _press([_]) => _ctrl.forward();
  void _release([_]) => _ctrl.reverse();

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.of(context).disableAnimations;
    final target = GestureDetector(
      behavior: widget.behavior,
      onTapDown: reduced ? null : _press,
      onTapUp: reduced ? null : _release,
      onTapCancel: reduced ? null : _release,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: reduced
          ? widget.child
          : ScaleTransition(scale: _scale, child: widget.child),
    );

    if (!widget.ensureHitTarget) return target;
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: AfSpacing.minHitTarget,
        minHeight: AfSpacing.minHitTarget,
      ),
      child: target,
    );
  }
}
