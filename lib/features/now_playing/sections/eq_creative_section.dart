import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../eq_dsp_widgets.dart';

// ── Creative Section ─────────────────────────────────────────────────────────

class EqCreativeSection extends StatefulWidget {
  const EqCreativeSection({
    super.key,
    required this.exciter,
    required this.exciterAmount,
    required this.crystalizer,
    required this.crystalizerIntensity,
    required this.virtualBass,
    required this.virtualBassCutoff,
    required this.crusher,
    required this.crusherBits,
    required this.crusherMix,
    required this.crusherSamples,
    required this.onChanged,
    required this.onApply,
  });

  final bool exciter;
  final double exciterAmount;
  final bool crystalizer;
  final double crystalizerIntensity;
  final bool virtualBass;
  final double virtualBassCutoff;
  final bool crusher;
  final double crusherBits;
  final double crusherMix;
  final double crusherSamples;
  final void Function(String field, dynamic value) onChanged;
  final Future<void> Function() onApply;

  @override
  State<EqCreativeSection> createState() => _EqCreativeSectionState();
}

class _EqCreativeSectionState extends State<EqCreativeSection> {
  late bool _exciter = widget.exciter;
  late double _exciterAmount = widget.exciterAmount;
  late bool _crystalizer = widget.crystalizer;
  late double _crystalizerIntensity = widget.crystalizerIntensity;
  late bool _virtualBass = widget.virtualBass;
  late double _virtualBassCutoff = widget.virtualBassCutoff;
  late bool _crusher = widget.crusher;
  late double _crusherBits = widget.crusherBits;
  late double _crusherMix = widget.crusherMix;
  late double _crusherSamples = widget.crusherSamples;

  @override
  void didUpdateWidget(covariant EqCreativeSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.exciter != widget.exciter) _exciter = widget.exciter;
    if (oldWidget.exciterAmount != widget.exciterAmount) {
      _exciterAmount = widget.exciterAmount;
    }
    if (oldWidget.crystalizer != widget.crystalizer) {
      _crystalizer = widget.crystalizer;
    }
    if (oldWidget.crystalizerIntensity != widget.crystalizerIntensity) {
      _crystalizerIntensity = widget.crystalizerIntensity;
    }
    if (oldWidget.virtualBass != widget.virtualBass) {
      _virtualBass = widget.virtualBass;
    }
    if (oldWidget.virtualBassCutoff != widget.virtualBassCutoff) {
      _virtualBassCutoff = widget.virtualBassCutoff;
    }
    if (oldWidget.crusher != widget.crusher) _crusher = widget.crusher;
    if (oldWidget.crusherBits != widget.crusherBits) {
      _crusherBits = widget.crusherBits;
    }
    if (oldWidget.crusherMix != widget.crusherMix) {
      _crusherMix = widget.crusherMix;
    }
    if (oldWidget.crusherSamples != widget.crusherSamples) {
      _crusherSamples = widget.crusherSamples;
    }
  }

  void _set(String field, dynamic value) => widget.onChanged(field, value);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Exciter ──
        EqEffectToggle(
          title: 'Harmonic exciter',
          subtitle: 'Adds harmonic overtones',
          value: _exciter,
          onChanged: (v) {
            setState(() => _exciter = v);
            _set('exciter', v);
            unawaited(widget.onApply());
          },
        ),
        EqExpandableContent(
          visible: _exciter,
          child: eqSliderRow(
            'Amount',
            _exciterAmount,
            0.0,
            10.0,
            20,
            (v) {
              setState(() => _exciterAmount = v);
              _set('exciterAmount', v);
            },
            widget.onApply,
            precision: 1,
          ),
        ),
        // ── Crystalizer ──
        EqEffectToggle(
          title: 'Crystalizer',
          subtitle: 'Audio sharpener / brightener',
          value: _crystalizer,
          onChanged: (v) {
            setState(() => _crystalizer = v);
            _set('crystalizer', v);
            unawaited(widget.onApply());
          },
        ),
        EqExpandableContent(
          visible: _crystalizer,
          child: eqSliderRow(
            'Intensity',
            _crystalizerIntensity,
            CrystalizerSettings.iMin,
            CrystalizerSettings.iMax,
            40,
            (v) {
              setState(() => _crystalizerIntensity = v);
              _set('crystalizerIntensity', v);
            },
            widget.onApply,
            precision: 1,
          ),
        ),
        // ── Virtual Bass ──
        EqEffectToggle(
          title: 'Virtual bass',
          subtitle: 'Psychoacoustic bass enhancement',
          value: _virtualBass,
          onChanged: (v) {
            setState(() => _virtualBass = v);
            _set('virtualBass', v);
            unawaited(widget.onApply());
          },
        ),
        EqExpandableContent(
          visible: _virtualBass,
          child: eqSliderRow(
            'Cutoff',
            _virtualBassCutoff,
            100.0,
            500.0,
            40,
            (v) {
              setState(() => _virtualBassCutoff = v);
              _set('virtualBassCutoff', v);
            },
            widget.onApply,
            suffix: 'Hz',
            precision: 0,
          ),
        ),
        // ── Bit-crusher ──
        EqEffectToggle(
          title: 'Bit-crusher',
          subtitle: 'Lo-fi resolution and rate reduction',
          value: _crusher,
          onChanged: (v) {
            setState(() => _crusher = v);
            _set('crusher', v);
            unawaited(widget.onApply());
          },
        ),
        EqExpandableContent(
          visible: _crusher,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              eqSliderRow(
                'Bits',
                _crusherBits,
                AcrusherSettings.bitsMin,
                AcrusherSettings.bitsMax,
                15,
                (v) {
                  setState(() => _crusherBits = v);
                  _set('crusherBits', v);
                },
                widget.onApply,
                precision: 0,
              ),
              eqSliderRow(
                'Mix',
                _crusherMix,
                AcrusherSettings.mixMin,
                AcrusherSettings.mixMax,
                20,
                (v) {
                  setState(() => _crusherMix = v);
                  _set('crusherMix', v);
                },
                widget.onApply,
                precision: 2,
              ),
              eqSliderRow(
                'Samples',
                _crusherSamples,
                AcrusherSettings.samplesMin,
                AcrusherSettings.samplesMax,
                50,
                (v) {
                  setState(() => _crusherSamples = v);
                  _set('crusherSamples', v);
                },
                widget.onApply,
                precision: 0,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
