import 'dart:async';

import 'package:flutter/material.dart';

import '../eq_dsp_widgets.dart';

// ── Echo Section ─────────────────────────────────────────────────────────────

class EqEchoSection extends StatefulWidget {
  const EqEchoSection({
    super.key,
    required this.echoEnabled,
    required this.echoInGain,
    required this.echoOutGain,
    required this.echoDelays,
    required this.echoDecays,
    required this.onChanged,
    required this.onApply,
  });

  final bool echoEnabled;
  final double echoInGain;
  final double echoOutGain;
  final String echoDelays;
  final String echoDecays;
  final void Function(String field, dynamic value) onChanged;
  final Future<void> Function() onApply;

  @override
  State<EqEchoSection> createState() => _EqEchoSectionState();
}

class _EqEchoSectionState extends State<EqEchoSection> {
  late bool _echoEnabled = widget.echoEnabled;
  late double _echoInGain = widget.echoInGain;
  late double _echoOutGain = widget.echoOutGain;
  late String _echoDelays = widget.echoDelays;
  late String _echoDecays = widget.echoDecays;

  @override
  void didUpdateWidget(covariant EqEchoSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.echoEnabled != widget.echoEnabled) {
      _echoEnabled = widget.echoEnabled;
    }
    if (oldWidget.echoInGain != widget.echoInGain) {
      _echoInGain = widget.echoInGain;
    }
    if (oldWidget.echoOutGain != widget.echoOutGain) {
      _echoOutGain = widget.echoOutGain;
    }
    if (oldWidget.echoDelays != widget.echoDelays) {
      _echoDelays = widget.echoDelays;
    }
    if (oldWidget.echoDecays != widget.echoDecays) {
      _echoDecays = widget.echoDecays;
    }
  }

  void _set(String field, dynamic value) => widget.onChanged(field, value);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        EqEffectToggle(
          title: 'Echo',
          subtitle: 'Multi-tap delay effect',
          value: _echoEnabled,
          onChanged: (v) {
            setState(() => _echoEnabled = v);
            _set('echoEnabled', v);
            unawaited(widget.onApply());
          },
        ),
        EqExpandableContent(
          visible: _echoEnabled,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              eqSliderRow(
                'In gain',
                _echoInGain,
                0.0,
                1.0,
                20,
                (v) {
                  setState(() => _echoInGain = v);
                  _set('echoInGain', v);
                },
                widget.onApply,
                precision: 2,
              ),
              eqSliderRow(
                'Out gain',
                _echoOutGain,
                0.0,
                1.0,
                20,
                (v) {
                  setState(() => _echoOutGain = v);
                  _set('echoOutGain', v);
                },
                widget.onApply,
                precision: 2,
              ),
              eqTextFieldRow(
                context,
                'Delays (ms)',
                _echoDelays,
                'e.g. 500|250',
                (v) {
                  setState(() => _echoDelays = v);
                  _set('echoDelays', v);
                  unawaited(widget.onApply());
                },
              ),
              eqTextFieldRow(
                context,
                'Decays (0-1)',
                _echoDecays,
                'e.g. 0.5|0.3',
                (v) {
                  setState(() => _echoDecays = v);
                  _set('echoDecays', v);
                  unawaited(widget.onApply());
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
