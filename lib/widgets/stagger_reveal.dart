import 'package:flutter/material.dart';

import '../design_tokens/tokens.dart';

/// Wraps [children] in a staggered fade+slide-up reveal animation.
///
/// Each child starts invisible and 12dp below its final position, then
/// animates to visible + offset zero with a per-item delay defined by
/// [AfStagger]. Items beyond [AfStagger.maxStaggered] share the last
/// stagger slot so the total reveal time stays bounded.
///
/// The animation plays once on first build. Subsequent rebuilds reuse the
/// completed state — no re-trigger.
class StaggerReveal extends StatefulWidget {
  const StaggerReveal({
    super.key,
    required this.children,
    this.duration,
    this.slideOffset = AfSpacing.s12,
  });

  /// Widgets to reveal in order.
  final List<Widget> children;

  /// Total stagger sequence duration. Defaults to ~400ms for 8 items.
  final Duration? duration;

  /// Vertical slide distance in logical pixels.
  final double slideOffset;

  @override
  State<StaggerReveal> createState() => _StaggerRevealState();
}

class _StaggerRevealState extends State<StaggerReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    final total =
        widget.duration ??
        Duration(
          milliseconds:
              AfStagger.perItem.inMilliseconds * AfStagger.maxStaggered +
              AfStagger.itemDuration.inMilliseconds,
        );
    _ctrl = AnimationController(vsync: this, duration: total)..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = _ctrl.duration!.inMilliseconds;
    final itemMs = AfStagger.itemDuration.inMilliseconds;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          _StaggeredItem(
            controller: _ctrl,
            begin: (AfStagger.perItem.inMilliseconds * i) / totalMs,
            end: ((AfStagger.perItem.inMilliseconds * i) + itemMs) / totalMs,
            slideOffset: widget.slideOffset,
            child: widget.children[i],
          ),
      ],
    );
  }
}

class _StaggeredItem extends StatelessWidget {
  const _StaggeredItem({
    required this.controller,
    required this.begin,
    required this.end,
    required this.slideOffset,
    required this.child,
  });

  final AnimationController controller;
  final double begin;
  final double end;
  final double slideOffset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.of(context).disableAnimations;
    if (reduced) return child;

    final fade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: controller,
        curve: Interval(
          begin.clamp(0, 1),
          end.clamp(0, 1),
          curve: AfCurves.easeOut,
        ),
      ),
    );

    final slide = Tween<double>(begin: slideOffset, end: 0).animate(
      CurvedAnimation(
        parent: controller,
        curve: Interval(
          begin.clamp(0, 1),
          end.clamp(0, 1),
          curve: AfCurves.easeOut,
        ),
      ),
    );

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) => Opacity(
        opacity: fade.value,
        child: Transform.translate(
          offset: Offset(0, slide.value),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
