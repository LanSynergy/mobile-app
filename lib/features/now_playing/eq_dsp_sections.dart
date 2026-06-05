import 'dart:async';

import 'package:flutter/material.dart';

import 'eq_dsp_widgets.dart';

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
                0.001,
                1.0,
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
                1.0,
                20.0,
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
                0.01,
                200.0,
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
                5.0,
                2000.0,
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
                0.001,
                1.0,
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
                1.0,
                20.0,
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
                0.01,
                200.0,
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
                5.0,
                2000.0,
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
                0.0,
                1.0,
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
                0.0,
                1.0,
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
                0.0,
                1.0,
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

// ── Modulation Section ───────────────────────────────────────────────────────

class EqModulationSection extends StatefulWidget {
  const EqModulationSection({
    super.key,
    required this.phaser,
    required this.phaserInGain,
    required this.phaserOutGain,
    required this.phaserDelay,
    required this.phaserDecay,
    required this.phaserSpeed,
    required this.flanger,
    required this.flangerDelay,
    required this.flangerDepth,
    required this.flangerRegen,
    required this.flangerWidth,
    required this.flangerSpeed,
    required this.chorus,
    required this.chorusInGain,
    required this.chorusOutGain,
    required this.chorusDelays,
    required this.chorusDecays,
    required this.chorusSpeeds,
    required this.chorusDepths,
    required this.tremolo,
    required this.tremoloFreq,
    required this.tremoloDepth,
    required this.vibrato,
    required this.vibratoFreq,
    required this.vibratoDepth,
    required this.onChanged,
    required this.onApply,
  });

  final bool phaser;
  final double phaserInGain;
  final double phaserOutGain;
  final double phaserDelay;
  final double phaserDecay;
  final double phaserSpeed;
  final bool flanger;
  final double flangerDelay;
  final double flangerDepth;
  final double flangerRegen;
  final double flangerWidth;
  final double flangerSpeed;
  final bool chorus;
  final double chorusInGain;
  final double chorusOutGain;
  final String chorusDelays;
  final String chorusDecays;
  final String chorusSpeeds;
  final String chorusDepths;
  final bool tremolo;
  final double tremoloFreq;
  final double tremoloDepth;
  final bool vibrato;
  final double vibratoFreq;
  final double vibratoDepth;
  final void Function(String field, dynamic value) onChanged;
  final Future<void> Function() onApply;

  @override
  State<EqModulationSection> createState() => _EqModulationSectionState();
}

class _EqModulationSectionState extends State<EqModulationSection> {
  late bool _phaser = widget.phaser;
  late double _phaserInGain = widget.phaserInGain;
  late double _phaserOutGain = widget.phaserOutGain;
  late double _phaserDelay = widget.phaserDelay;
  late double _phaserDecay = widget.phaserDecay;
  late double _phaserSpeed = widget.phaserSpeed;
  late bool _flanger = widget.flanger;
  late double _flangerDelay = widget.flangerDelay;
  late double _flangerDepth = widget.flangerDepth;
  late double _flangerRegen = widget.flangerRegen;
  late double _flangerWidth = widget.flangerWidth;
  late double _flangerSpeed = widget.flangerSpeed;
  late bool _chorus = widget.chorus;
  late double _chorusInGain = widget.chorusInGain;
  late double _chorusOutGain = widget.chorusOutGain;
  late String _chorusDelays = widget.chorusDelays;
  late String _chorusDecays = widget.chorusDecays;
  late String _chorusSpeeds = widget.chorusSpeeds;
  late String _chorusDepths = widget.chorusDepths;
  late bool _tremolo = widget.tremolo;
  late double _tremoloFreq = widget.tremoloFreq;
  late double _tremoloDepth = widget.tremoloDepth;
  late bool _vibrato = widget.vibrato;
  late double _vibratoFreq = widget.vibratoFreq;
  late double _vibratoDepth = widget.vibratoDepth;

  @override
  void didUpdateWidget(covariant EqModulationSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phaser != widget.phaser) _phaser = widget.phaser;
    if (oldWidget.phaserInGain != widget.phaserInGain) {
      _phaserInGain = widget.phaserInGain;
    }
    if (oldWidget.phaserOutGain != widget.phaserOutGain) {
      _phaserOutGain = widget.phaserOutGain;
    }
    if (oldWidget.phaserDelay != widget.phaserDelay) {
      _phaserDelay = widget.phaserDelay;
    }
    if (oldWidget.phaserDecay != widget.phaserDecay) {
      _phaserDecay = widget.phaserDecay;
    }
    if (oldWidget.phaserSpeed != widget.phaserSpeed) {
      _phaserSpeed = widget.phaserSpeed;
    }
    if (oldWidget.flanger != widget.flanger) _flanger = widget.flanger;
    if (oldWidget.flangerDelay != widget.flangerDelay) {
      _flangerDelay = widget.flangerDelay;
    }
    if (oldWidget.flangerDepth != widget.flangerDepth) {
      _flangerDepth = widget.flangerDepth;
    }
    if (oldWidget.flangerRegen != widget.flangerRegen) {
      _flangerRegen = widget.flangerRegen;
    }
    if (oldWidget.flangerWidth != widget.flangerWidth) {
      _flangerWidth = widget.flangerWidth;
    }
    if (oldWidget.flangerSpeed != widget.flangerSpeed) {
      _flangerSpeed = widget.flangerSpeed;
    }
    if (oldWidget.chorus != widget.chorus) _chorus = widget.chorus;
    if (oldWidget.chorusInGain != widget.chorusInGain) {
      _chorusInGain = widget.chorusInGain;
    }
    if (oldWidget.chorusOutGain != widget.chorusOutGain) {
      _chorusOutGain = widget.chorusOutGain;
    }
    if (oldWidget.chorusDelays != widget.chorusDelays) {
      _chorusDelays = widget.chorusDelays;
    }
    if (oldWidget.chorusDecays != widget.chorusDecays) {
      _chorusDecays = widget.chorusDecays;
    }
    if (oldWidget.chorusSpeeds != widget.chorusSpeeds) {
      _chorusSpeeds = widget.chorusSpeeds;
    }
    if (oldWidget.chorusDepths != widget.chorusDepths) {
      _chorusDepths = widget.chorusDepths;
    }
    if (oldWidget.tremolo != widget.tremolo) _tremolo = widget.tremolo;
    if (oldWidget.tremoloFreq != widget.tremoloFreq) {
      _tremoloFreq = widget.tremoloFreq;
    }
    if (oldWidget.tremoloDepth != widget.tremoloDepth) {
      _tremoloDepth = widget.tremoloDepth;
    }
    if (oldWidget.vibrato != widget.vibrato) _vibrato = widget.vibrato;
    if (oldWidget.vibratoFreq != widget.vibratoFreq) {
      _vibratoFreq = widget.vibratoFreq;
    }
    if (oldWidget.vibratoDepth != widget.vibratoDepth) {
      _vibratoDepth = widget.vibratoDepth;
    }
  }

  void _set(String field, dynamic value) => widget.onChanged(field, value);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Phaser ──
        EqEffectToggle(
          title: 'Phaser',
          subtitle: 'Phase-shifting sweep effect',
          value: _phaser,
          onChanged: (v) {
            setState(() => _phaser = v);
            _set('phaser', v);
            unawaited(widget.onApply());
          },
        ),
        EqExpandableContent(
          visible: _phaser,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              eqSliderRow(
                'In gain',
                _phaserInGain,
                0.0,
                1.0,
                20,
                (v) {
                  setState(() => _phaserInGain = v);
                  _set('phaserInGain', v);
                },
                widget.onApply,
                precision: 2,
              ),
              eqSliderRow(
                'Out gain',
                _phaserOutGain,
                0.0,
                1.0,
                20,
                (v) {
                  setState(() => _phaserOutGain = v);
                  _set('phaserOutGain', v);
                },
                widget.onApply,
                precision: 2,
              ),
              eqSliderRow(
                'Delay',
                _phaserDelay,
                0.0,
                5.0,
                50,
                (v) {
                  setState(() => _phaserDelay = v);
                  _set('phaserDelay', v);
                },
                widget.onApply,
                precision: 1,
                suffix: 'ms',
              ),
              eqSliderRow(
                'Decay',
                _phaserDecay,
                0.0,
                0.99,
                99,
                (v) {
                  setState(() => _phaserDecay = v);
                  _set('phaserDecay', v);
                },
                widget.onApply,
                precision: 2,
              ),
              eqSliderRow(
                'Speed',
                _phaserSpeed,
                0.1,
                2.0,
                19,
                (v) {
                  setState(() => _phaserSpeed = v);
                  _set('phaserSpeed', v);
                },
                widget.onApply,
                precision: 2,
                suffix: 'Hz',
              ),
            ],
          ),
        ),
        // ── Flanger ──
        EqEffectToggle(
          title: 'Flanger',
          subtitle: 'Flanging with feedback',
          value: _flanger,
          onChanged: (v) {
            setState(() => _flanger = v);
            _set('flanger', v);
            unawaited(widget.onApply());
          },
        ),
        EqExpandableContent(
          visible: _flanger,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              eqSliderRow(
                'Delay',
                _flangerDelay,
                0.0,
                30.0,
                60,
                (v) {
                  setState(() => _flangerDelay = v);
                  _set('flangerDelay', v);
                },
                widget.onApply,
                precision: 1,
                suffix: 'ms',
              ),
              eqSliderRow(
                'Depth',
                _flangerDepth,
                0.0,
                10.0,
                20,
                (v) {
                  setState(() => _flangerDepth = v);
                  _set('flangerDepth', v);
                },
                widget.onApply,
                precision: 1,
              ),
              eqSliderRow(
                'Regen',
                _flangerRegen,
                -95.0,
                95.0,
                38,
                (v) {
                  setState(() => _flangerRegen = v);
                  _set('flangerRegen', v);
                },
                widget.onApply,
                precision: 0,
                suffix: '%',
              ),
              eqSliderRow(
                'Width',
                _flangerWidth,
                0.0,
                100.0,
                20,
                (v) {
                  setState(() => _flangerWidth = v);
                  _set('flangerWidth', v);
                },
                widget.onApply,
                precision: 0,
                suffix: '%',
              ),
              eqSliderRow(
                'Speed',
                _flangerSpeed,
                0.1,
                10.0,
                99,
                (v) {
                  setState(() => _flangerSpeed = v);
                  _set('flangerSpeed', v);
                },
                widget.onApply,
                precision: 1,
                suffix: 'Hz',
              ),
            ],
          ),
        ),
        // ── Chorus ──
        EqEffectToggle(
          title: 'Chorus',
          subtitle: 'Multi-voice chorus effect',
          value: _chorus,
          onChanged: (v) {
            setState(() => _chorus = v);
            _set('chorus', v);
            unawaited(widget.onApply());
          },
        ),
        EqExpandableContent(
          visible: _chorus,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              eqSliderRow(
                'In gain',
                _chorusInGain,
                0.0,
                1.0,
                20,
                (v) {
                  setState(() => _chorusInGain = v);
                  _set('chorusInGain', v);
                },
                widget.onApply,
                precision: 2,
              ),
              eqSliderRow(
                'Out gain',
                _chorusOutGain,
                0.0,
                1.0,
                20,
                (v) {
                  setState(() => _chorusOutGain = v);
                  _set('chorusOutGain', v);
                },
                widget.onApply,
                precision: 2,
              ),
              eqTextFieldRow(
                context,
                'Delays (ms)',
                _chorusDelays,
                'e.g. 40|60',
                (v) {
                  setState(() => _chorusDelays = v);
                  _set('chorusDelays', v);
                  unawaited(widget.onApply());
                },
              ),
              eqTextFieldRow(
                context,
                'Decays',
                _chorusDecays,
                'e.g. 0.4|0.32',
                (v) {
                  setState(() => _chorusDecays = v);
                  _set('chorusDecays', v);
                  unawaited(widget.onApply());
                },
              ),
              eqTextFieldRow(
                context,
                'Speeds (Hz)',
                _chorusSpeeds,
                'e.g. 0.25|0.4',
                (v) {
                  setState(() => _chorusSpeeds = v);
                  _set('chorusSpeeds', v);
                  unawaited(widget.onApply());
                },
              ),
              eqTextFieldRow(
                context,
                'Depths',
                _chorusDepths,
                'e.g. 2|3',
                (v) {
                  setState(() => _chorusDepths = v);
                  _set('chorusDepths', v);
                  unawaited(widget.onApply());
                },
              ),
            ],
          ),
        ),
        // ── Tremolo ──
        EqEffectToggle(
          title: 'Tremolo',
          subtitle: 'Amplitude modulation',
          value: _tremolo,
          onChanged: (v) {
            setState(() => _tremolo = v);
            _set('tremolo', v);
            unawaited(widget.onApply());
          },
        ),
        EqExpandableContent(
          visible: _tremolo,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              eqSliderRow(
                'Frequency',
                _tremoloFreq,
                0.1,
                20.0,
                40,
                (v) {
                  setState(() => _tremoloFreq = v);
                  _set('tremoloFreq', v);
                },
                widget.onApply,
                precision: 1,
                suffix: 'Hz',
              ),
              eqSliderRow(
                'Depth',
                _tremoloDepth,
                0.0,
                1.0,
                20,
                (v) {
                  setState(() => _tremoloDepth = v);
                  _set('tremoloDepth', v);
                },
                widget.onApply,
                precision: 2,
              ),
            ],
          ),
        ),
        // ── Vibrato ──
        EqEffectToggle(
          title: 'Vibrato',
          subtitle: 'Pitch modulation',
          value: _vibrato,
          onChanged: (v) {
            setState(() => _vibrato = v);
            _set('vibrato', v);
            unawaited(widget.onApply());
          },
        ),
        EqExpandableContent(
          visible: _vibrato,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              eqSliderRow(
                'Frequency',
                _vibratoFreq,
                0.1,
                20.0,
                40,
                (v) {
                  setState(() => _vibratoFreq = v);
                  _set('vibratoFreq', v);
                },
                widget.onApply,
                precision: 1,
                suffix: 'Hz',
              ),
              eqSliderRow(
                'Depth',
                _vibratoDepth,
                0.0,
                1.0,
                20,
                (v) {
                  setState(() => _vibratoDepth = v);
                  _set('vibratoDepth', v);
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
            -10.0,
            10.0,
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
                1.0,
                16.0,
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
                0.0,
                1.0,
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
                1.0,
                250.0,
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
