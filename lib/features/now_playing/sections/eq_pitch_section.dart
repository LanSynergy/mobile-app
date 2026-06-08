import 'dart:async';

import 'package:flutter/material.dart';

import '../eq_dsp_widgets.dart';

// ── Pitch Section ────────────────────────────────────────────────────────────

class EqPitchSection extends StatefulWidget {
  const EqPitchSection({
    super.key,
    required this.rubberbandEnabled,
    required this.pitch,
    required this.tempo,
    required this.onChanged,
    required this.onApply,
  });

  final bool rubberbandEnabled;
  final double pitch;
  final double tempo;
  final void Function(String field, dynamic value) onChanged;
  final Future<void> Function() onApply;

  @override
  State<EqPitchSection> createState() => _EqPitchSectionState();
}

class _EqPitchSectionState extends State<EqPitchSection> {
  late bool _rubberbandEnabled = widget.rubberbandEnabled;
  late double _pitch = widget.pitch;
  late double _tempo = widget.tempo;

  @override
  void didUpdateWidget(covariant EqPitchSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rubberbandEnabled != widget.rubberbandEnabled) {
      _rubberbandEnabled = widget.rubberbandEnabled;
    }
    if (oldWidget.pitch != widget.pitch) _pitch = widget.pitch;
    if (oldWidget.tempo != widget.tempo) _tempo = widget.tempo;
  }

  void _set(String field, dynamic value) => widget.onChanged(field, value);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        EqEffectToggle(
          title: 'Enable pitch/tempo shift',
          subtitle: 'High-quality rubberband engine',
          value: _rubberbandEnabled,
          onChanged: (v) {
            setState(() => _rubberbandEnabled = v);
            _set('rubberbandEnabled', v);
            unawaited(widget.onApply());
          },
        ),
        EqExpandableContent(
          visible: _rubberbandEnabled,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              eqSliderRow(
                'Pitch',
                _pitch,
                0.5,
                2.0,
                30,
                (v) {
                  setState(() => _pitch = v);
                  _set('pitch', v);
                },
                widget.onApply,
                suffix: '\u00d7',
                precision: 2,
              ),
              eqSliderRow(
                'Tempo',
                _tempo,
                0.5,
                2.0,
                30,
                (v) {
                  setState(() => _tempo = v);
                  _set('tempo', v);
                },
                widget.onApply,
                suffix: '\u00d7',
                precision: 2,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
