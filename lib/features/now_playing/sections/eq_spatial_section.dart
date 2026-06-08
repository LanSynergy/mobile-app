import 'dart:async';

import 'package:flutter/material.dart';

import '../eq_dsp_widgets.dart';

// ── Spatial Section ──────────────────────────────────────────────────────────

class EqSpatialSection extends StatefulWidget {
  const EqSpatialSection({
    super.key,
    required this.crossfeed,
    required this.crossfeedStrength,
    required this.stereoWiden,
    required this.stereoWidenDelay,
    required this.onChanged,
    required this.onApply,
  });

  final bool crossfeed;
  final double crossfeedStrength;
  final bool stereoWiden;
  final double stereoWidenDelay;
  final void Function(String field, dynamic value) onChanged;
  final Future<void> Function() onApply;

  @override
  State<EqSpatialSection> createState() => _EqSpatialSectionState();
}

class _EqSpatialSectionState extends State<EqSpatialSection> {
  late bool _crossfeed = widget.crossfeed;
  late double _crossfeedStrength = widget.crossfeedStrength;
  late bool _stereoWiden = widget.stereoWiden;
  late double _stereoWidenDelay = widget.stereoWidenDelay;

  @override
  void didUpdateWidget(covariant EqSpatialSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.crossfeed != widget.crossfeed) {
      _crossfeed = widget.crossfeed;
    }
    if (oldWidget.crossfeedStrength != widget.crossfeedStrength) {
      _crossfeedStrength = widget.crossfeedStrength;
    }
    if (oldWidget.stereoWiden != widget.stereoWiden) {
      _stereoWiden = widget.stereoWiden;
    }
    if (oldWidget.stereoWidenDelay != widget.stereoWidenDelay) {
      _stereoWidenDelay = widget.stereoWidenDelay;
    }
  }

  void _set(String field, dynamic value) => widget.onChanged(field, value);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        EqEffectToggle(
          title: 'Crossfeed',
          subtitle: 'Headphone crossfeed for natural imaging',
          value: _crossfeed,
          onChanged: (v) {
            setState(() => _crossfeed = v);
            _set('crossfeed', v);
            unawaited(widget.onApply());
          },
        ),
        EqExpandableContent(
          visible: _crossfeed,
          child: eqSliderRow(
            'Strength',
            _crossfeedStrength,
            0.0,
            1.0,
            20,
            (v) {
              setState(() => _crossfeedStrength = v);
              _set('crossfeedStrength', v);
            },
            widget.onApply,
            precision: 2,
          ),
        ),
        EqEffectToggle(
          title: 'Stereo widening',
          subtitle: 'Expands stereo image',
          value: _stereoWiden,
          onChanged: (v) {
            setState(() => _stereoWiden = v);
            _set('stereoWiden', v);
            unawaited(widget.onApply());
          },
        ),
        EqExpandableContent(
          visible: _stereoWiden,
          child: eqSliderRow(
            'Delay',
            _stereoWidenDelay,
            1.0,
            100.0,
            99,
            (v) {
              setState(() => _stereoWidenDelay = v);
              _set('stereoWidenDelay', v);
            },
            widget.onApply,
            suffix: 'ms',
            precision: 0,
          ),
        ),
      ],
    );
  }
}
