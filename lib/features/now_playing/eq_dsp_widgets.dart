import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

import '../../design_tokens/tokens.dart';

// ─── Section Label ──────────────────────────────────────────────────────────

Widget eqSectionLabel(String title) => Padding(
  padding: const EdgeInsets.fromLTRB(
    AfSpacing.s4,
    0,
    AfSpacing.s4,
    AfSpacing.s8,
  ),
  child: Text(
    title,
    style: AfTypography.bodySmall.copyWith(
      color: AfColors.textTertiary,
      fontWeight: FontWeight.w500,
    ),
  ),
);

// ─── Card ───────────────────────────────────────────────────────────────────

Widget eqCard(List<Widget> children) => Material(
  color: AfColors.surfaceBase,
  borderRadius: AfRadii.borderLg,
  clipBehavior: Clip.antiAlias,
  child: Padding(
    padding: const EdgeInsets.all(AfSpacing.s16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    ),
  ),
);

// ─── Animated Effect Toggle ─────────────────────────────────────────────────

/// A [SwitchListTile] wrapper that animates its content opacity
/// and provides a subtle scale pulse on toggle.
class EqEffectToggle extends StatefulWidget {
  const EqEffectToggle({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  State<EqEffectToggle> createState() => _EqEffectToggleState();
}

class _EqEffectToggleState extends State<EqEffectToggle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: AfDurations.quick);
    _pulse = Tween<double>(begin: 1, end: 0.97).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: AfCurves.easeStandard),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.of(context).disableAnimations;
    return ScaleTransition(
      scale: reduced ? const AlwaysStoppedAnimation(1) : _pulse,
      child: SwitchListTile.adaptive(
        value: widget.value,
        onChanged: (v) {
          widget.onChanged(v);
          if (!reduced) {
            _pulseCtrl.forward().then((_) => _pulseCtrl.reverse());
          }
        },
        title: Text(widget.title, style: AfTypography.bodyMedium),
        subtitle: Text(
          widget.subtitle,
          style: AfTypography.bodySmall.copyWith(color: AfColors.textTertiary),
        ),
        activeThumbColor: AfColors.indigo500,
        contentPadding: EdgeInsets.zero,
      ),
    );
  }
}

// ─── Animated Toggle Tile (for simple on/off without SwitchListTile) ────────

Widget eqToggleTile(
  String title,
  String subtitle,
  bool value,
  ValueChanged<bool> onChanged, {
  bool enabled = true,
}) {
  return EqEffectToggle(
    title: title,
    subtitle: subtitle,
    value: value,
    onChanged: enabled ? onChanged : (_) {},
  );
}

// ─── Animated Slider Row ────────────────────────────────────────────────────

/// Custom slider with animated value display and optional suffix.
class EqSliderRow extends StatelessWidget {
  const EqSliderRow({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    required this.onChangeEnd,
    this.suffix,
    this.precision = 0,
    this.enabled = true,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final VoidCallback onChangeEnd;
  final String? suffix;
  final int precision;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final display = value >= 0 && suffix == 'dB'
        ? '+${value.toStringAsFixed(precision)}'
        : value.toStringAsFixed(precision);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(label, style: AfTypography.bodyMedium),
            const Spacer(),
            Text(
              suffix != null ? '$display $suffix' : display,
              style: AfTypography.mono.copyWith(color: AfColors.textTertiary),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          activeColor: AfColors.indigo400,
          onChanged: enabled ? onChanged : null,
          onChangeEnd: enabled ? (_) => onChangeEnd() : null,
        ),
      ],
    );
  }
}

/// Backward-compatible alias.
Widget eqSliderRow(
  String label,
  double value,
  double min,
  double max,
  int divisions,
  ValueChanged<double> onChanged,
  VoidCallback onChangeEnd, {
  String? suffix,
  int precision = 0,
  bool enabled = true,
}) {
  return EqSliderRow(
    label: label,
    value: value,
    min: min,
    max: max,
    divisions: divisions,
    onChanged: onChanged,
    onChangeEnd: onChangeEnd,
    suffix: suffix,
    precision: precision,
    enabled: enabled,
  );
}

// ─── Text Field Row ─────────────────────────────────────────────────────────

Widget eqTextFieldRow(
  BuildContext context,
  String label,
  String value,
  String hint,
  ValueChanged<String> onSubmitted,
) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        SizedBox(width: 100, child: Text(label, style: AfTypography.bodySmall)),
        const SizedBox(width: 8),
        Expanded(
          child: TextFormField(
            initialValue: value,
            style: AfTypography.mono.copyWith(fontSize: 13),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: AfTypography.mono.copyWith(
                fontSize: 12,
                color: AfColors.textTertiary,
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: AfColors.surfaceHigh),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: AfColors.surfaceHigh),
              ),
            ),
            onFieldSubmitted: onSubmitted,
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
          ),
        ),
      ],
    ),
  );
}

// ─── Animated Content Reveal ────────────────────────────────────────────────

/// Wraps [child] in an animated size + fade transition.
/// Used to smoothly reveal sub-settings when an effect is toggled on.
class EqExpandableContent extends StatefulWidget {
  const EqExpandableContent({
    super.key,
    required this.visible,
    required this.child,
  });

  final bool visible;
  final Widget child;

  @override
  State<EqExpandableContent> createState() => _EqExpandableContentState();
}

class _EqExpandableContentState extends State<EqExpandableContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _heightFactor;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: AfDurations.standard);
    _heightFactor = _ctrl.drive(Tween<double>(begin: 0, end: 1));
    _opacity = _ctrl.drive(Tween<double>(begin: 0, end: 1));
    if (widget.visible) {
      _ctrl.value = 1;
    }
  }

  @override
  void didUpdateWidget(EqExpandableContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible != oldWidget.visible) {
      if (widget.visible) {
        _ctrl.forward();
      } else {
        _ctrl.reverse();
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.of(context).disableAnimations;
    if (reduced) {
      return widget.visible ? widget.child : const SizedBox.shrink();
    }
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) => ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: _heightFactor.value,
          child: Opacity(opacity: _opacity.value, child: child),
        ),
      ),
      child: widget.child,
    );
  }
}

// ─── EQ Band Vertical Bar ───────────────────────────────────────────────────

/// A single vertical EQ band bar with animated gain height.
class EqBandBar extends StatelessWidget {
  const EqBandBar({
    super.key,
    required this.label,
    required this.gain,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String label;
  final double gain;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final VoidCallback onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.of(context).disableAnimations;
    // Normalize gain to 0..1 for display (0 = min, 1 = max).
    final t = ((gain - min) / (max - min)).clamp(0.0, 1.0);
    // 0.5 = flat (unity), below = cut, above = boost.
    final isFlat = (gain - 1.0).abs() < 0.05;

    return GestureDetector(
      onVerticalDragUpdate: (details) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        final height = box.size.height;
        // Invert: drag up = increase gain.
        final delta = -details.delta.dy / height * (max - min);
        onChanged((gain + delta).clamp(min, max));
      },
      onVerticalDragEnd: (_) => onChangeEnd(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Gain value label.
          Text(
            gain >= 1.0
                ? '+${((gain - 1) * 12).toStringAsFixed(0)}'
                : ((gain - 1) * 12).toStringAsFixed(0),
            style: AfTypography.caption.copyWith(
              color: isFlat ? AfColors.textTertiary : AfColors.indigo400,
              fontSize: 9,
            ),
          ),
          const SizedBox(height: 2),
          // Bar container.
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final totalH = constraints.maxHeight;
                // Fill height: how far from center the bar reaches.
                final fillFrac = (t - 0.5).abs() * 2;

                return AnimatedContainer(
                  duration: reduced ? Duration.zero : AfDurations.quick,
                  curve: AfCurves.easeStandard,
                  decoration: BoxDecoration(
                    color: isFlat
                        ? AfColors.surfaceHigh
                        : AfColors.indigo500.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Align(
                    alignment: Alignment(0, 1 - t * 2),
                    child: Container(
                      height: totalH * 0.08 + totalH * 0.45 * fillFrac,
                      decoration: BoxDecoration(
                        color: isFlat
                            ? AfColors.surfaceHigh
                            : AfColors.indigo400,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 2),
          // Frequency label.
          Text(
            label,
            style: AfTypography.caption.copyWith(
              color: AfColors.textTertiary,
              fontSize: 8,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ─── EQ Band Slider (horizontal, for detailed editing) ──────────────────────

/// A single horizontal EQ band slider with animated value.
class EqBandSlider extends StatelessWidget {
  const EqBandSlider({
    super.key,
    required this.bandKey,
    required this.freq,
    required this.gain,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String bandKey;
  final String freq;
  final double gain;
  final ValueChanged<double> onChanged;
  final VoidCallback onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AfSpacing.s2),
      child: Row(
        children: [
          SizedBox(
            width: 58,
            child: Text(
              freq,
              style: AfTypography.caption.copyWith(
                color: AfColors.textTertiary,
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                key: ValueKey(bandKey),
                value: gain.clamp(0.0, 4.0),
                min: 0,
                max: 4,
                divisions: 40,
                activeColor: AfColors.indigo400,
                onChanged: onChanged,
                onChangeEnd: (_) => onChangeEnd(),
              ),
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              gain.toStringAsFixed(1),
              textAlign: TextAlign.right,
              style: AfTypography.caption.copyWith(
                color: AfColors.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Scroll Absorb Overlay ──────────────────────────────────────────────────

/// Manages scroll-active state to prevent phantom touch events on
/// Slider/Switch/ChoiceChip widgets during scroll momentum.
class ScrollAbsorbController extends ValueNotifier<bool> {
  ScrollAbsorbController() : super(false);

  void markActive() {
    if (!value) value = true;
  }

  void markInactive() {
    if (value) value = false;
  }
}

/// Wraps a [ListView] and manages scroll-absorb state.
class ScrollAbsorbNotification extends StatefulWidget {
  const ScrollAbsorbNotification({
    super.key,
    required this.controller,
    required this.child,
  });

  final ScrollAbsorbController controller;
  final Widget child;

  @override
  State<ScrollAbsorbNotification> createState() =>
      _ScrollAbsorbNotificationState();
}

class _ScrollAbsorbNotificationState extends State<ScrollAbsorbNotification> {
  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification) {
          widget.controller.markActive();
        } else if (notification is ScrollEndNotification ||
            (notification is UserScrollNotification &&
                notification.direction == ScrollDirection.idle)) {
          widget.controller.markInactive();
        }
        return false;
      },
      child: NotificationListener<OverscrollIndicatorNotification>(
        onNotification: (notification) {
          notification.disallowIndicator();
          return true;
        },
        child: widget.child,
      ),
    );
  }
}
