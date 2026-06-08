import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../eq_dsp_widgets.dart';

// ── Dynamics Section ─────────────────────────────────────────────────────────

class EqDynamicsSection extends StatefulWidget {
  const EqDynamicsSection({
    super.key,
    required this.loudnorm,
    required this.compressor,
    required this.compThreshold,
    required this.compRatio,
    required this.compAttack,
    required this.compRelease,
    required this.gate,
    required this.gateThreshold,
    required this.gateRatio,
    required this.gateAttack,
    required this.gateRelease,
    required this.deesser,
    required this.deesserIntensity,
    required this.deesserMix,
    required this.deesserFreq,
    required this.onChanged,
    required this.onApply,
  });

  final bool loudnorm;
  final bool compressor;
  final double compThreshold;
  final double compRatio;
  final double compAttack;
  final double compRelease;
  final bool gate;
  final double gateThreshold;
  final double gateRatio;
  final double gateAttack;
  final double gateRelease;
  final bool deesser;
  final double deesserIntensity;
  final double deesserMix;
  final double deesserFreq;
  final void Function(String field, dynamic value) onChanged;
  final Future<void> Function() onApply;

  @override
  State<EqDynamicsSection> createState() => _EqDynamicsSectionState();
}

class _EqDynamicsSectionState extends State<EqDynamicsSection> {
  late bool _loudnorm = widget.loudnorm;
  late bool _compressor = widget.compressor;
  late double _compThreshold = widget.compThreshold;
  late double _compRatio = widget.compRatio;
  late double _compAttack = widget.compAttack;
  late double _compRelease = widget.compRelease;
  late bool _gate = widget.gate;
  late double _gateThreshold = widget.gateThreshold;
  late double _gateRatio = widget.gateRatio;
  late double _gateAttack = widget.gateAttack;
  late double _gateRelease = widget.gateRelease;
  late bool _deesser = widget.deesser;
  late double _deesserIntensity = widget.deesserIntensity;
  late double _deesserMix = widget.deesserMix;
  late double _deesserFreq = widget.deesserFreq;

  @override
  void didUpdateWidget(covariant EqDynamicsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loudnorm != widget.loudnorm) _loudnorm = widget.loudnorm;
    if (oldWidget.compressor != widget.compressor) {
      _compressor = widget.compressor;
    }
    if (oldWidget.compThreshold != widget.compThreshold) {
      _compThreshold = widget.compThreshold;
    }
    if (oldWidget.compRatio != widget.compRatio) {
      _compRatio = widget.compRatio;
    }
    if (oldWidget.compAttack != widget.compAttack) {
      _compAttack = widget.compAttack;
    }
    if (oldWidget.compRelease != widget.compRelease) {
      _compRelease = widget.compRelease;
    }
    if (oldWidget.gate != widget.gate) _gate = widget.gate;
    if (oldWidget.gateThreshold != widget.gateThreshold) {
      _gateThreshold = widget.gateThreshold;
    }
    if (oldWidget.gateRatio != widget.gateRatio) {
      _gateRatio = widget.gateRatio;
    }
    if (oldWidget.gateAttack != widget.gateAttack) {
      _gateAttack = widget.gateAttack;
    }
    if (oldWidget.gateRelease != widget.gateRelease) {
      _gateRelease = widget.gateRelease;
    }
    if (oldWidget.deesser != widget.deesser) _deesser = widget.deesser;
    if (oldWidget.deesserIntensity != widget.deesserIntensity) {
      _deesserIntensity = widget.deesserIntensity;
    }
    if (oldWidget.deesserMix != widget.deesserMix) {
      _deesserMix = widget.deesserMix;
    }
    if (oldWidget.deesserFreq != widget.deesserFreq) {
      _deesserFreq = widget.deesserFreq;
    }
  }

  void _set(String field, dynamic value) {
    widget.onChanged(field, value);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        eqToggleTile(
          'Loudness normalization',
          'EBU R128 (-16 LUFS)',
          _loudnorm,
          (v) {
            setState(() => _loudnorm = v);
            _set('loudnorm', v);
            unawaited(widget.onApply());
          },
        ),
        EqEffectToggle(
          title: 'Dynamic compressor',
          subtitle: 'Reduces volume spikes',
          value: _compressor,
          onChanged: (v) {
            setState(() => _compressor = v);
            _set('compressor', v);
            unawaited(widget.onApply());
          },
        ),
        EqExpandableContent(
          visible: _compressor,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              eqSliderRow(
                'Threshold',
                _compThreshold,
                AcompressorSettings.thresholdMin,
                AcompressorSettings.thresholdMax,
                100,
                (v) {
                  setState(() => _compThreshold = v);
                  _set('compThreshold', v);
                },
                widget.onApply,
                precision: 3,
              ),
              eqSliderRow(
                'Ratio',
                _compRatio,
                AcompressorSettings.ratioMin,
                AcompressorSettings.ratioMax,
                38,
                (v) {
                  setState(() => _compRatio = v);
                  _set('compRatio', v);
                },
                widget.onApply,
                precision: 1,
                suffix: ':1',
              ),
              eqSliderRow(
                'Attack',
                _compAttack,
                AcompressorSettings.attackMin,
                AcompressorSettings.attackMax,
                100,
                (v) {
                  setState(() => _compAttack = v);
                  _set('compAttack', v);
                },
                widget.onApply,
                precision: 1,
                suffix: 'ms',
              ),
              eqSliderRow(
                'Release',
                _compRelease,
                AcompressorSettings.releaseMin,
                AcompressorSettings.releaseMax,
                100,
                (v) {
                  setState(() => _compRelease = v);
                  _set('compRelease', v);
                },
                widget.onApply,
                precision: 0,
                suffix: 'ms',
              ),
            ],
          ),
        ),
        EqEffectToggle(
          title: 'Noise gate',
          subtitle: 'Silences signal below threshold',
          value: _gate,
          onChanged: (v) {
            setState(() => _gate = v);
            _set('gate', v);
            unawaited(widget.onApply());
          },
        ),
        EqExpandableContent(
          visible: _gate,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              eqSliderRow(
                'Threshold',
                _gateThreshold,
                AgateSettings.thresholdMin,
                AgateSettings.thresholdMax,
                100,
                (v) {
                  setState(() => _gateThreshold = v);
                  _set('gateThreshold', v);
                },
                widget.onApply,
                precision: 3,
              ),
              eqSliderRow(
                'Ratio',
                _gateRatio,
                AgateSettings.ratioMin,
                AgateSettings.ratioMax,
                38,
                (v) {
                  setState(() => _gateRatio = v);
                  _set('gateRatio', v);
                },
                widget.onApply,
                precision: 1,
                suffix: ':1',
              ),
              eqSliderRow(
                'Attack',
                _gateAttack,
                AgateSettings.attackMin,
                AgateSettings.attackMax,
                100,
                (v) {
                  setState(() => _gateAttack = v);
                  _set('gateAttack', v);
                },
                widget.onApply,
                precision: 1,
                suffix: 'ms',
              ),
              eqSliderRow(
                'Release',
                _gateRelease,
                AgateSettings.releaseMin,
                AgateSettings.releaseMax,
                100,
                (v) {
                  setState(() => _gateRelease = v);
                  _set('gateRelease', v);
                },
                widget.onApply,
                precision: 0,
                suffix: 'ms',
              ),
            ],
          ),
        ),
        EqEffectToggle(
          title: 'De-esser',
          subtitle: 'Reduces sibilance',
          value: _deesser,
          onChanged: (v) {
            setState(() => _deesser = v);
            _set('deesser', v);
            unawaited(widget.onApply());
          },
        ),
        EqExpandableContent(
          visible: _deesser,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              eqSliderRow(
                'Intensity',
                _deesserIntensity,
                DeesserSettings.iMin,
                DeesserSettings.iMax,
                20,
                (v) {
                  setState(() => _deesserIntensity = v);
                  _set('deesserIntensity', v);
                },
                widget.onApply,
                precision: 2,
              ),
              eqSliderRow(
                'Mix',
                _deesserMix,
                DeesserSettings.mMin,
                DeesserSettings.mMax,
                20,
                (v) {
                  setState(() => _deesserMix = v);
                  _set('deesserMix', v);
                },
                widget.onApply,
                precision: 2,
              ),
              eqSliderRow(
                'Frequency keep',
                _deesserFreq,
                DeesserSettings.fMin,
                DeesserSettings.fMax,
                20,
                (v) {
                  setState(() => _deesserFreq = v);
                  _set('deesserFreq', v);
                },
                widget.onApply,
                precision: 2,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
