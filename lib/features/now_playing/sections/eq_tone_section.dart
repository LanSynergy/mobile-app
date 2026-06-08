import 'package:flutter/material.dart';

import '../eq_dsp_widgets.dart';

// ── Tone Section ─────────────────────────────────────────────────────────────

class EqToneSection extends StatefulWidget {
  const EqToneSection({
    super.key,
    required this.bass,
    required this.treble,
    required this.onBassChanged,
    required this.onTrebleChanged,
    required this.onApply,
  });

  final double bass;
  final double treble;
  final ValueChanged<double> onBassChanged;
  final ValueChanged<double> onTrebleChanged;
  final Future<void> Function() onApply;

  @override
  State<EqToneSection> createState() => _EqToneSectionState();
}

class _EqToneSectionState extends State<EqToneSection> {
  late double _bass = widget.bass;
  late double _treble = widget.treble;

  @override
  void didUpdateWidget(covariant EqToneSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bass != widget.bass) _bass = widget.bass;
    if (oldWidget.treble != widget.treble) _treble = widget.treble;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        eqSliderRow(
          'Bass',
          _bass,
          -12,
          12,
          24,
          (v) {
            setState(() => _bass = v);
            widget.onBassChanged(v);
          },
          widget.onApply,
          suffix: 'dB',
        ),
        eqSliderRow(
          'Treble',
          _treble,
          -12,
          12,
          24,
          (v) {
            setState(() => _treble = v);
            widget.onTrebleChanged(v);
          },
          widget.onApply,
          suffix: 'dB',
        ),
      ],
    );
  }
}
