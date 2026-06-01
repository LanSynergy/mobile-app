import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart'
    show
        AcompressorSettings,
        AcrusherSettings,
        AechoSettings,
        AexciterSettings,
        AgateSettings,
        AphaserSettings,
        AudioEffects,
        BassSettings,
        ChorusSettings,
        CrossfeedSettings,
        CrystalizerSettings,
        DeesserSettings,
        FlangerSettings,
        LoudnormSettings,
        RubberbandSettings,
        StereowidenSettings,
        SuperequalizerSettings,
        TrebleSettings,
        TremoloSettings,
        VibratoSettings,
        VirtualbassSettings;

import '../../core/audio/player_settings_store.dart';
import '../../design_tokens/tokens.dart';
import '../../utils/display_error.dart';
import '../../state/providers.dart';
import '../../widgets/af_dialog.dart';
import 'eq_band_painter.dart';
import 'eq_dsp_widgets.dart';
import 'eq_preset.dart';

class EqDspScreen extends ConsumerStatefulWidget {
  const EqDspScreen({super.key});

  @override
  ConsumerState<EqDspScreen> createState() => _EqDspScreenState();
}

class _EqDspScreenState extends ConsumerState<EqDspScreen> {
  // ── Master toggle ──
  bool _masterEnabled = true;

  /// Scroll-absorb state to prevent phantom touches during scroll.
  final ScrollAbsorbController _scrollCtrl = ScrollAbsorbController();

  // ── Tone ──
  double _bass = 0.0;
  double _treble = 0.0;

  // ── Dynamics ──
  bool _loudnorm = false;
  bool _compressor = false;
  double _compThreshold = 0.1;
  double _compRatio = 4.0;
  double _compAttack = 20.0;
  double _compRelease = 250.0;

  // ── Gate ──
  bool _gate = false;
  double _gateThreshold = 0.01;
  double _gateRatio = 2.0;
  double _gateAttack = 20.0;
  double _gateRelease = 250.0;

  // ── De-esser ──
  bool _deesser = false;
  double _deesserIntensity = 0.0;
  double _deesserMix = 0.5;
  double _deesserFreq = 0.5;

  // ── 18-band EQ ──
  bool _eqEnabled = false;
  final Map<String, double> _eqBands = {for (final k in kEqBands.keys) k: 1.0};

  // ── EQ Presets ──
  String? _activePreset;
  Map<String, EqPreset> _userPresets = {};

  // ── Pitch & tempo ──
  bool _rubberbandEnabled = false;
  double _pitch = 1.0;
  double _tempo = 1.0;

  // ── Spatial ──
  bool _crossfeed = false;
  double _crossfeedStrength = 0.2;
  bool _stereoWiden = false;
  double _stereoWidenDelay = 20.0;

  // ── Creative ──
  bool _exciter = false;
  double _exciterAmount = 1.0;
  bool _crystalizer = false;
  double _crystalizerIntensity = 2.0;
  bool _virtualBass = false;
  double _virtualBassCutoff = 250.0;

  // ── Echo / Delay ──
  bool _echoEnabled = false;
  double _echoInGain = 0.6;
  double _echoOutGain = 0.3;
  String _echoDelays = '500';
  String _echoDecays = '0.5';

  // ── Modulation ──
  bool _phaser = false;
  double _phaserInGain = 0.4;
  double _phaserOutGain = 0.74;
  double _phaserDelay = 3.0;
  double _phaserDecay = 0.4;
  double _phaserSpeed = 0.5;

  bool _flanger = false;
  double _flangerDelay = 0.0;
  double _flangerDepth = 2.0;
  double _flangerRegen = 0.0;
  double _flangerWidth = 71.0;
  double _flangerSpeed = 0.5;

  bool _chorus = false;
  double _chorusInGain = 0.4;
  double _chorusOutGain = 0.4;
  String _chorusDelays = '40|60';
  String _chorusDecays = '0.4|0.32';
  String _chorusSpeeds = '0.25|0.4';
  String _chorusDepths = '2|3';

  bool _tremolo = false;
  double _tremoloFreq = 5.0;
  double _tremoloDepth = 0.5;

  bool _vibrato = false;
  double _vibratoFreq = 5.0;
  double _vibratoDepth = 0.5;

  // ── Bit-crusher ──
  bool _crusher = false;
  double _crusherBits = 8.0;
  double _crusherMix = 0.5;
  double _crusherSamples = 1.0;

  @override
  void initState() {
    super.initState();
    _loadFxState();
    _loadMasterState();
    _loadPresets();
  }

  void _loadFxState() {
    final fx = ref.read(playerServiceProvider).audioEffects;
    _bass = fx.bass.g;
    _treble = fx.treble.g;
    _loudnorm = fx.loudnorm.enabled;
    _compressor = fx.acompressor.enabled;
    _compThreshold = fx.acompressor.threshold;
    _compRatio = fx.acompressor.ratio;
    _compAttack = fx.acompressor.attack;
    _compRelease = fx.acompressor.release;
    _eqEnabled = fx.superequalizer.enabled;
    for (final entry in fx.superequalizer.params.entries) {
      if (_eqBands.containsKey(entry.key)) {
        _eqBands[entry.key] = entry.value;
      }
    }
    _rubberbandEnabled = fx.rubberband.enabled;
    _pitch = fx.rubberband.pitch;
    _tempo = fx.rubberband.tempo;
    _crossfeed = fx.crossfeed.enabled;
    _crossfeedStrength = fx.crossfeed.strength;
    _stereoWiden = fx.stereowiden.enabled;
    _stereoWidenDelay = fx.stereowiden.delay;
    _exciter = fx.aexciter.enabled;
    _exciterAmount = fx.aexciter.amount;
    _crystalizer = fx.crystalizer.enabled;
    _crystalizerIntensity = fx.crystalizer.i.clamp(-10.0, 10.0);
    _virtualBass = fx.virtualbass.enabled;
    _virtualBassCutoff = fx.virtualbass.cutoff;
    _gate = fx.agate.enabled;
    _gateThreshold = fx.agate.threshold;
    _gateRatio = fx.agate.ratio;
    _gateAttack = fx.agate.attack;
    _gateRelease = fx.agate.release;
    _deesser = fx.deesser.enabled;
    _deesserIntensity = fx.deesser.i.clamp(0.0, 1.0);
    _deesserMix = fx.deesser.m.clamp(0.0, 1.0);
    _deesserFreq = fx.deesser.f.clamp(0.0, 1.0);
    _echoEnabled = fx.aecho.enabled;
    _echoInGain = fx.aecho.in_gain;
    _echoOutGain = fx.aecho.out_gain;
    _echoDelays = fx.aecho.delays;
    _echoDecays = fx.aecho.decays;
    _phaser = fx.aphaser.enabled;
    _phaserInGain = fx.aphaser.in_gain;
    _phaserOutGain = fx.aphaser.out_gain;
    _phaserDelay = fx.aphaser.delay;
    _phaserDecay = fx.aphaser.decay;
    _phaserSpeed = fx.aphaser.speed;
    _flanger = fx.flanger.enabled;
    _flangerDelay = fx.flanger.delay;
    _flangerDepth = fx.flanger.depth;
    _flangerRegen = fx.flanger.regen;
    _flangerWidth = fx.flanger.width;
    _flangerSpeed = fx.flanger.speed;
    _chorus = fx.chorus.enabled;
    _chorusInGain = fx.chorus.in_gain;
    _chorusOutGain = fx.chorus.out_gain;
    _chorusDelays = fx.chorus.delays ?? '40|60';
    _chorusDecays = fx.chorus.decays ?? '0.4|0.32';
    _chorusSpeeds = fx.chorus.speeds ?? '0.25|0.4';
    _chorusDepths = fx.chorus.depths ?? '2|3';
    _tremolo = fx.tremolo.enabled;
    _tremoloFreq = fx.tremolo.f;
    _tremoloDepth = fx.tremolo.d;
    _vibrato = fx.vibrato.enabled;
    _vibratoFreq = fx.vibrato.f;
    _vibratoDepth = fx.vibrato.d;
    _crusher = fx.acrusher.enabled;
    _crusherBits = fx.acrusher.bits;
    _crusherMix = fx.acrusher.mix;
    _crusherSamples = fx.acrusher.samples;
  }

  Future<void> _loadMasterState() async {
    final enabled = await PlayerSettingsStore.loadDspMasterEnabled();
    if (mounted && enabled != _masterEnabled) {
      setState(() => _masterEnabled = enabled);
    }
  }

  Future<void> _loadPresets() async {
    final presets = await PlayerSettingsStore.loadEqPresetsAsync();
    if (mounted) {
      setState(() => _userPresets = presets);
    }
  }

  // ── Apply / Reset ────────────────────────────────────────────────────────

  Future<void> _apply() async {
    if (!_masterEnabled) return;
    final svc = ref.read(playerServiceProvider);
    final effects = AudioEffects(
      bass: BassSettings(enabled: _bass != 0, g: _bass),
      treble: TrebleSettings(enabled: _treble != 0, g: _treble),
      loudnorm: LoudnormSettings(enabled: _loudnorm),
      acompressor: AcompressorSettings(
        enabled: _compressor,
        threshold: _compThreshold,
        ratio: _compRatio,
        attack: _compAttack,
        release: _compRelease,
      ),
      superequalizer: SuperequalizerSettings(
        enabled: _eqEnabled,
        params: _buildEqParams(),
      ),
      rubberband: RubberbandSettings(
        enabled: _rubberbandEnabled,
        pitch: _pitch,
        tempo: _tempo,
      ),
      crossfeed: CrossfeedSettings(
        enabled: _crossfeed,
        strength: _crossfeedStrength,
      ),
      stereowiden: StereowidenSettings(
        enabled: _stereoWiden,
        delay: _stereoWidenDelay,
      ),
      aexciter: AexciterSettings(enabled: _exciter, amount: _exciterAmount),
      crystalizer: CrystalizerSettings(
        enabled: _crystalizer,
        i: _crystalizerIntensity,
      ),
      virtualbass: VirtualbassSettings(
        enabled: _virtualBass,
        cutoff: _virtualBassCutoff,
      ),
      agate: AgateSettings(
        enabled: _gate,
        threshold: _gateThreshold,
        ratio: _gateRatio,
        attack: _gateAttack,
        release: _gateRelease,
      ),
      deesser: DeesserSettings(
        enabled: _deesser,
        i: _deesserIntensity,
        m: _deesserMix,
        f: _deesserFreq,
      ),
      aecho: AechoSettings(
        enabled: _echoEnabled,
        in_gain: _echoInGain,
        out_gain: _echoOutGain,
        delays: _echoDelays,
        decays: _echoDecays,
      ),
      aphaser: AphaserSettings(
        enabled: _phaser,
        in_gain: _phaserInGain,
        out_gain: _phaserOutGain,
        delay: _phaserDelay,
        decay: _phaserDecay,
        speed: _phaserSpeed,
      ),
      flanger: FlangerSettings(
        enabled: _flanger,
        delay: _flangerDelay,
        depth: _flangerDepth,
        regen: _flangerRegen,
        width: _flangerWidth,
        speed: _flangerSpeed,
      ),
      chorus: ChorusSettings(
        enabled: _chorus,
        in_gain: _chorusInGain,
        out_gain: _chorusOutGain,
        delays: _chorusDelays,
        decays: _chorusDecays,
        speeds: _chorusSpeeds,
        depths: _chorusDepths,
      ),
      tremolo: TremoloSettings(
        enabled: _tremolo,
        f: _tremoloFreq,
        d: _tremoloDepth,
      ),
      vibrato: VibratoSettings(
        enabled: _vibrato,
        f: _vibratoFreq,
        d: _vibratoDepth,
      ),
      acrusher: AcrusherSettings(
        enabled: _crusher,
        bits: _crusherBits,
        mix: _crusherMix,
        samples: _crusherSamples,
      ),
    );
    try {
      await svc.setAudioEffects(effects);
      await PlayerSettingsStore.saveAudioEffects(effects);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(displayError(e, prefix: 'Failed to apply'))),
        );
      }
    }
  }

  void _resetAll() {
    setState(() {
      _masterEnabled = true;
      _bass = 0;
      _treble = 0;
      _loudnorm = false;
      _compressor = false;
      _compThreshold = 0.1;
      _compRatio = 4.0;
      _compAttack = 20.0;
      _compRelease = 250.0;
      _eqEnabled = false;
      for (final k in _eqBands.keys) {
        _eqBands[k] = 1.0;
      }
      _activePreset = null;
      _rubberbandEnabled = false;
      _pitch = 1.0;
      _tempo = 1.0;
      _crossfeed = false;
      _crossfeedStrength = 0.2;
      _stereoWiden = false;
      _stereoWidenDelay = 20.0;
      _exciter = false;
      _exciterAmount = 1.0;
      _crystalizer = false;
      _crystalizerIntensity = 2.0;
      _virtualBass = false;
      _virtualBassCutoff = 250.0;
      _gate = false;
      _gateThreshold = 0.01;
      _gateRatio = 2.0;
      _gateAttack = 20.0;
      _gateRelease = 250.0;
      _deesser = false;
      _deesserIntensity = 0.0;
      _deesserMix = 0.5;
      _deesserFreq = 0.5;
      _echoEnabled = false;
      _echoInGain = 0.6;
      _echoOutGain = 0.3;
      _echoDelays = '500';
      _echoDecays = '0.5';
      _phaser = false;
      _phaserInGain = 0.4;
      _phaserOutGain = 0.74;
      _phaserDelay = 3.0;
      _phaserDecay = 0.4;
      _phaserSpeed = 0.5;
      _flanger = false;
      _flangerDelay = 0.0;
      _flangerDepth = 2.0;
      _flangerRegen = 0.0;
      _flangerWidth = 71.0;
      _flangerSpeed = 0.5;
      _chorus = false;
      _chorusInGain = 0.4;
      _chorusOutGain = 0.4;
      _chorusDelays = '40|60';
      _chorusDecays = '0.4|0.32';
      _chorusSpeeds = '0.25|0.4';
      _chorusDepths = '2|3';
      _tremolo = false;
      _tremoloFreq = 5.0;
      _tremoloDepth = 0.5;
      _vibrato = false;
      _vibratoFreq = 5.0;
      _vibratoDepth = 0.5;
      _crusher = false;
      _crusherBits = 8.0;
      _crusherMix = 0.5;
      _crusherSamples = 1.0;
    });
    unawaited(
      ref.read(playerServiceProvider).setAudioEffects(const AudioEffects()),
    );
    unawaited(PlayerSettingsStore.saveActivePreset(null));
  }

  void _applyPreset(String name, EqPreset preset) {
    setState(() {
      _activePreset = name;
      _bass = preset.bass;
      _treble = preset.treble;
      _eqEnabled = preset.bands.isNotEmpty;
      for (final k in _eqBands.keys) {
        _eqBands[k] = preset.bands[k] ?? 1.0;
      }
    });
    unawaited(_apply());
    unawaited(PlayerSettingsStore.saveActivePreset(name));
  }

  Future<void> _saveCurrentAsPreset() async {
    final controller = TextEditingController();
    final String? name;
    try {
      name = await showBlurDialog<String>(
        context: context,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Save EQ Preset', style: AfTypography.titleMedium),
            const SizedBox(height: AfSpacing.s16),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Preset name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AfSpacing.s24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () =>
                      Navigator.pop(context, controller.text.trim()),
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
    if (name == null || name.isEmpty) return;
    final presetName = name;
    final preset = EqPreset(
      bands: Map.of(_eqBands),
      bass: _bass,
      treble: _treble,
    );
    await PlayerSettingsStore.saveEqPreset(presetName, preset);
    setState(() {
      _userPresets[presetName] = preset;
      _activePreset = presetName;
    });
  }

  Future<void> _deletePreset(String name) async {
    await PlayerSettingsStore.deleteEqPreset(name);
    setState(() {
      _userPresets.remove(name);
      if (_activePreset == name) _activePreset = null;
    });
  }

  Map<String, double> _buildEqParams() {
    final params = <String, double>{};
    for (final entry in _eqBands.entries) {
      if (entry.value != 1.0) params[entry.key] = entry.value;
    }
    return params;
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AfColors.surfaceCanvas,
      appBar: AppBar(
        backgroundColor: AfColors.surfaceCanvas,
        surfaceTintColor: Colors.transparent,
        title: const Text('Equalizer & DSP'),
        centerTitle: false,
        actions: [
          Switch.adaptive(
            value: _masterEnabled,
            activeTrackColor: AfColors.indigo500,
            onChanged: (v) {
              setState(() => _masterEnabled = v);
              unawaited(PlayerSettingsStore.saveDspMasterEnabled(v));
              if (v) {
                unawaited(_apply());
              } else {
                final svc = ref.read(playerServiceProvider);
                unawaited(svc.setAudioEffects(const AudioEffects()));
              }
            },
          ),
          TextButton(
            onPressed: _resetAll,
            child: Text(
              'Reset all',
              style: AfTypography.bodySmall.copyWith(
                color: AfColors.semanticError,
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          ScrollAbsorbNotification(
            controller: _scrollCtrl,
            child: ListView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.symmetric(
                horizontal: AfSpacing.s16,
                vertical: AfSpacing.s8,
              ),
              children: _buildSections(),
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: _scrollCtrl,
            builder: (_, active, _) => active
                ? const Positioned.fill(
                    child: AbsorbPointer(child: SizedBox.expand()),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  // ── Sections ─────────────────────────────────────────────────────────────

  List<Widget> _buildSections() {
    final sections = <Widget>[
      // EQ Presets
      eqSectionLabel('EQ Presets'),
      eqCard([_buildPresetChips()]),
      const SizedBox(height: AfSpacing.s16),

      // Tone
      eqSectionLabel('Tone'),
      eqCard([
        eqSliderRow(
          'Bass',
          _bass,
          -12,
          12,
          24,
          (v) {
            setState(() {
              _bass = v;
              _activePreset = null;
            });
          },
          _apply,
          suffix: 'dB',
        ),
        eqSliderRow(
          'Treble',
          _treble,
          -12,
          12,
          24,
          (v) {
            setState(() {
              _treble = v;
              _activePreset = null;
            });
          },
          _apply,
          suffix: 'dB',
        ),
      ]),
      const SizedBox(height: AfSpacing.s16),

      // 18-band EQ
      eqSectionLabel('18-band Equalizer'),
      eqCard([
        EqEffectToggle(
          title: 'Enable graphic EQ',
          subtitle: '18-band ISO frequency equalizer',
          value: _eqEnabled,
          onChanged: (v) {
            setState(() => _eqEnabled = v);
            unawaited(_apply());
          },
        ),
        EqExpandableContent(
          visible: _eqEnabled,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Visual EQ bars.
              SizedBox(
                height: 120,
                child: EqBandVisualization(
                  labels: kEqBands.values.toList(),
                  gains: kEqBands.keys.map((k) => _eqBands[k] ?? 1.0).toList(),
                  onGainChanged: (index, gain) {
                    final key = kEqBands.keys.elementAt(index);
                    setState(() {
                      _eqBands[key] = gain;
                      _activePreset = null;
                    });
                  },
                  onGainChangeEnd: _apply,
                ),
              ),
              const SizedBox(height: AfSpacing.s8),
              // Detailed sliders.
              ...kEqBands.entries.map((entry) {
                final gain = _eqBands[entry.key] ?? 1.0;
                return EqBandSlider(
                  bandKey: entry.key,
                  freq: entry.value,
                  gain: gain,
                  onChanged: (v) {
                    setState(() {
                      _eqBands[entry.key] = v;
                      _activePreset = null;
                    });
                  },
                  onChangeEnd: _apply,
                );
              }),
              // Action buttons.
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      setState(() {
                        for (final k in _eqBands.keys) {
                          _eqBands[k] = 1.0;
                        }
                        _activePreset = null;
                      });
                      unawaited(_apply());
                    },
                    child: Text(
                      'Flatten EQ',
                      style: AfTypography.bodySmall.copyWith(
                        color: AfColors.textTertiary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AfSpacing.s8),
                  TextButton.icon(
                    onPressed: _saveCurrentAsPreset,
                    icon: const Icon(Icons.save_outlined, size: 16),
                    label: Text(
                      'Save preset',
                      style: AfTypography.bodySmall.copyWith(
                        color: AfColors.indigo400,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ]),
      const SizedBox(height: AfSpacing.s16),

      // Dynamics
      ..._buildDynamicsSection(),

      // Echo / Delay
      ..._buildEchoSection(),

      // Pitch & Tempo
      ..._buildPitchTempoSection(),

      // Spatial
      ..._buildSpatialSection(),

      // Modulation
      ..._buildModulationSection(),

      // Creative
      ..._buildCreativeSection(),

      const SizedBox(height: AfSpacing.s24),
    ];

    // Wrap each section in opacity + AbsorbPointer when master is off.
    return sections
        .map(
          (child) => Opacity(
            opacity: _masterEnabled ? 1.0 : 0.4,
            child: AbsorbPointer(absorbing: !_masterEnabled, child: child),
          ),
        )
        .toList();
  }

  // ── Dynamics ─────────────────────────────────────────────────────────────

  List<Widget> _buildDynamicsSection() => [
    eqSectionLabel('Dynamics'),
    eqCard([
      eqToggleTile('Loudness normalization', 'EBU R128 (-16 LUFS)', _loudnorm, (
        v,
      ) {
        setState(() => _loudnorm = v);
        unawaited(_apply());
      }),
      EqEffectToggle(
        title: 'Dynamic compressor',
        subtitle: 'Reduces volume spikes',
        value: _compressor,
        onChanged: (v) {
          setState(() => _compressor = v);
          unawaited(_apply());
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
              (v) => setState(() => _compThreshold = v),
              _apply,
              precision: 3,
            ),
            eqSliderRow(
              'Ratio',
              _compRatio,
              1.0,
              20.0,
              38,
              (v) => setState(() => _compRatio = v),
              _apply,
              precision: 1,
              suffix: ':1',
            ),
            eqSliderRow(
              'Attack',
              _compAttack,
              0.01,
              200.0,
              100,
              (v) => setState(() => _compAttack = v),
              _apply,
              precision: 1,
              suffix: 'ms',
            ),
            eqSliderRow(
              'Release',
              _compRelease,
              5.0,
              2000.0,
              100,
              (v) => setState(() => _compRelease = v),
              _apply,
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
          unawaited(_apply());
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
              (v) => setState(() => _gateThreshold = v),
              _apply,
              precision: 3,
            ),
            eqSliderRow(
              'Ratio',
              _gateRatio,
              1.0,
              20.0,
              38,
              (v) => setState(() => _gateRatio = v),
              _apply,
              precision: 1,
              suffix: ':1',
            ),
            eqSliderRow(
              'Attack',
              _gateAttack,
              0.01,
              200.0,
              100,
              (v) => setState(() => _gateAttack = v),
              _apply,
              precision: 1,
              suffix: 'ms',
            ),
            eqSliderRow(
              'Release',
              _gateRelease,
              5.0,
              2000.0,
              100,
              (v) => setState(() => _gateRelease = v),
              _apply,
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
          unawaited(_apply());
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
              (v) => setState(() => _deesserIntensity = v),
              _apply,
              precision: 2,
            ),
            eqSliderRow(
              'Mix',
              _deesserMix,
              0.0,
              1.0,
              20,
              (v) => setState(() => _deesserMix = v),
              _apply,
              precision: 2,
            ),
            eqSliderRow(
              'Frequency keep',
              _deesserFreq,
              0.0,
              1.0,
              20,
              (v) => setState(() => _deesserFreq = v),
              _apply,
              precision: 2,
            ),
          ],
        ),
      ),
    ]),
    const SizedBox(height: AfSpacing.s16),
  ];

  // ── Echo / Delay ─────────────────────────────────────────────────────────

  List<Widget> _buildEchoSection() => [
    eqSectionLabel('Echo / Delay'),
    eqCard([
      EqEffectToggle(
        title: 'Echo',
        subtitle: 'Multi-tap delay effect',
        value: _echoEnabled,
        onChanged: (v) {
          setState(() => _echoEnabled = v);
          unawaited(_apply());
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
              (v) => setState(() => _echoInGain = v),
              _apply,
              precision: 2,
            ),
            eqSliderRow(
              'Out gain',
              _echoOutGain,
              0.0,
              1.0,
              20,
              (v) => setState(() => _echoOutGain = v),
              _apply,
              precision: 2,
            ),
            eqTextFieldRow(
              context,
              'Delays (ms)',
              _echoDelays,
              'e.g. 500|250',
              (v) {
                setState(() => _echoDelays = v);
                unawaited(_apply());
              },
            ),
            eqTextFieldRow(
              context,
              'Decays (0-1)',
              _echoDecays,
              'e.g. 0.5|0.3',
              (v) {
                setState(() => _echoDecays = v);
                unawaited(_apply());
              },
            ),
            Padding(
              padding: const EdgeInsets.only(
                top: AfSpacing.s4,
                bottom: AfSpacing.s8,
              ),
              child: Text(
                'Separate multiple taps with | (pipe)',
                style: AfTypography.caption.copyWith(
                  color: AfColors.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    ]),
    const SizedBox(height: AfSpacing.s16),
  ];

  // ── Pitch & Tempo ────────────────────────────────────────────────────────

  List<Widget> _buildPitchTempoSection() => [
    eqSectionLabel('Pitch & Tempo'),
    eqCard([
      EqEffectToggle(
        title: 'Enable pitch/tempo shift',
        subtitle: 'High-quality rubberband engine',
        value: _rubberbandEnabled,
        onChanged: (v) {
          setState(() => _rubberbandEnabled = v);
          unawaited(_apply());
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
              (v) => setState(() => _pitch = v),
              _apply,
              suffix: '×',
              precision: 2,
            ),
            eqSliderRow(
              'Tempo',
              _tempo,
              0.5,
              2.0,
              30,
              (v) => setState(() => _tempo = v),
              _apply,
              suffix: '×',
              precision: 2,
            ),
          ],
        ),
      ),
    ]),
    const SizedBox(height: AfSpacing.s16),
  ];

  // ── Spatial ──────────────────────────────────────────────────────────────

  List<Widget> _buildSpatialSection() => [
    eqSectionLabel('Spatial'),
    eqCard([
      EqEffectToggle(
        title: 'Crossfeed',
        subtitle: 'Headphone crossfeed for natural imaging',
        value: _crossfeed,
        onChanged: (v) {
          setState(() => _crossfeed = v);
          unawaited(_apply());
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
          (v) => setState(() => _crossfeedStrength = v),
          _apply,
          precision: 2,
        ),
      ),
      EqEffectToggle(
        title: 'Stereo widening',
        subtitle: 'Expands stereo image',
        value: _stereoWiden,
        onChanged: (v) {
          setState(() => _stereoWiden = v);
          unawaited(_apply());
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
          (v) => setState(() => _stereoWidenDelay = v),
          _apply,
          suffix: 'ms',
          precision: 0,
        ),
      ),
    ]),
    const SizedBox(height: AfSpacing.s16),
  ];

  // ── Modulation ───────────────────────────────────────────────────────────

  List<Widget> _buildModulationSection() => [
    eqSectionLabel('Modulation'),
    eqCard([
      EqEffectToggle(
        title: 'Phaser',
        subtitle: 'Phase-shifting sweep effect',
        value: _phaser,
        onChanged: (v) {
          setState(() => _phaser = v);
          unawaited(_apply());
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
              (v) => setState(() => _phaserInGain = v),
              _apply,
              precision: 2,
            ),
            eqSliderRow(
              'Out gain',
              _phaserOutGain,
              0.0,
              1.0,
              20,
              (v) => setState(() => _phaserOutGain = v),
              _apply,
              precision: 2,
            ),
            eqSliderRow(
              'Delay',
              _phaserDelay,
              0.0,
              5.0,
              50,
              (v) => setState(() => _phaserDelay = v),
              _apply,
              precision: 1,
              suffix: 'ms',
            ),
            eqSliderRow(
              'Decay',
              _phaserDecay,
              0.0,
              0.99,
              99,
              (v) => setState(() => _phaserDecay = v),
              _apply,
              precision: 2,
            ),
            eqSliderRow(
              'Speed',
              _phaserSpeed,
              0.1,
              2.0,
              19,
              (v) => setState(() => _phaserSpeed = v),
              _apply,
              precision: 2,
              suffix: 'Hz',
            ),
          ],
        ),
      ),
      EqEffectToggle(
        title: 'Flanger',
        subtitle: 'Flanging with feedback',
        value: _flanger,
        onChanged: (v) {
          setState(() => _flanger = v);
          unawaited(_apply());
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
              (v) => setState(() => _flangerDelay = v),
              _apply,
              precision: 1,
              suffix: 'ms',
            ),
            eqSliderRow(
              'Depth',
              _flangerDepth,
              0.0,
              10.0,
              20,
              (v) => setState(() => _flangerDepth = v),
              _apply,
              precision: 1,
            ),
            eqSliderRow(
              'Regen',
              _flangerRegen,
              -95.0,
              95.0,
              38,
              (v) => setState(() => _flangerRegen = v),
              _apply,
              precision: 0,
              suffix: '%',
            ),
            eqSliderRow(
              'Width',
              _flangerWidth,
              0.0,
              100.0,
              20,
              (v) => setState(() => _flangerWidth = v),
              _apply,
              precision: 0,
              suffix: '%',
            ),
            eqSliderRow(
              'Speed',
              _flangerSpeed,
              0.1,
              10.0,
              99,
              (v) => setState(() => _flangerSpeed = v),
              _apply,
              precision: 1,
              suffix: 'Hz',
            ),
          ],
        ),
      ),
      EqEffectToggle(
        title: 'Chorus',
        subtitle: 'Multi-voice chorus effect',
        value: _chorus,
        onChanged: (v) {
          setState(() => _chorus = v);
          unawaited(_apply());
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
              (v) => setState(() => _chorusInGain = v),
              _apply,
              precision: 2,
            ),
            eqSliderRow(
              'Out gain',
              _chorusOutGain,
              0.0,
              1.0,
              20,
              (v) => setState(() => _chorusOutGain = v),
              _apply,
              precision: 2,
            ),
            eqTextFieldRow(
              context,
              'Delays (ms)',
              _chorusDelays,
              'e.g. 40|60',
              (v) {
                setState(() => _chorusDelays = v);
                unawaited(_apply());
              },
            ),
            eqTextFieldRow(context, 'Decays', _chorusDecays, 'e.g. 0.4|0.32', (
              v,
            ) {
              setState(() => _chorusDecays = v);
              unawaited(_apply());
            }),
            eqTextFieldRow(
              context,
              'Speeds (Hz)',
              _chorusSpeeds,
              'e.g. 0.25|0.4',
              (v) {
                setState(() => _chorusSpeeds = v);
                unawaited(_apply());
              },
            ),
            eqTextFieldRow(context, 'Depths', _chorusDepths, 'e.g. 2|3', (v) {
              setState(() => _chorusDepths = v);
              unawaited(_apply());
            }),
            Padding(
              padding: const EdgeInsets.only(
                top: AfSpacing.s4,
                bottom: AfSpacing.s8,
              ),
              child: Text(
                'Separate multiple voices with | (pipe)',
                style: AfTypography.caption.copyWith(
                  color: AfColors.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
      EqEffectToggle(
        title: 'Tremolo',
        subtitle: 'Amplitude modulation',
        value: _tremolo,
        onChanged: (v) {
          setState(() => _tremolo = v);
          unawaited(_apply());
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
              (v) => setState(() => _tremoloFreq = v),
              _apply,
              precision: 1,
              suffix: 'Hz',
            ),
            eqSliderRow(
              'Depth',
              _tremoloDepth,
              0.0,
              1.0,
              20,
              (v) => setState(() => _tremoloDepth = v),
              _apply,
              precision: 2,
            ),
          ],
        ),
      ),
      EqEffectToggle(
        title: 'Vibrato',
        subtitle: 'Pitch modulation',
        value: _vibrato,
        onChanged: (v) {
          setState(() => _vibrato = v);
          unawaited(_apply());
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
              (v) => setState(() => _vibratoFreq = v),
              _apply,
              precision: 1,
              suffix: 'Hz',
            ),
            eqSliderRow(
              'Depth',
              _vibratoDepth,
              0.0,
              1.0,
              20,
              (v) => setState(() => _vibratoDepth = v),
              _apply,
              precision: 2,
            ),
          ],
        ),
      ),
    ]),
    const SizedBox(height: AfSpacing.s16),
  ];

  // ── Creative ─────────────────────────────────────────────────────────────

  List<Widget> _buildCreativeSection() => [
    eqSectionLabel('Creative'),
    eqCard([
      EqEffectToggle(
        title: 'Harmonic exciter',
        subtitle: 'Adds harmonic overtones',
        value: _exciter,
        onChanged: (v) {
          setState(() => _exciter = v);
          unawaited(_apply());
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
          (v) => setState(() => _exciterAmount = v),
          _apply,
          precision: 1,
        ),
      ),
      EqEffectToggle(
        title: 'Crystalizer',
        subtitle: 'Audio sharpener / brightener',
        value: _crystalizer,
        onChanged: (v) {
          setState(() => _crystalizer = v);
          unawaited(_apply());
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
          (v) => setState(() => _crystalizerIntensity = v),
          _apply,
          precision: 1,
        ),
      ),
      EqEffectToggle(
        title: 'Virtual bass',
        subtitle: 'Psychoacoustic bass enhancement',
        value: _virtualBass,
        onChanged: (v) {
          setState(() => _virtualBass = v);
          unawaited(_apply());
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
          (v) => setState(() => _virtualBassCutoff = v),
          _apply,
          suffix: 'Hz',
          precision: 0,
        ),
      ),
      EqEffectToggle(
        title: 'Bit-crusher',
        subtitle: 'Lo-fi resolution and rate reduction',
        value: _crusher,
        onChanged: (v) {
          setState(() => _crusher = v);
          unawaited(_apply());
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
              (v) => setState(() => _crusherBits = v),
              _apply,
              precision: 0,
            ),
            eqSliderRow(
              'Mix',
              _crusherMix,
              0.0,
              1.0,
              20,
              (v) => setState(() => _crusherMix = v),
              _apply,
              precision: 2,
            ),
            eqSliderRow(
              'Samples',
              _crusherSamples,
              1.0,
              250.0,
              50,
              (v) => setState(() => _crusherSamples = v),
              _apply,
              precision: 0,
            ),
          ],
        ),
      ),
    ]),
  ];

  // ── Presets ──────────────────────────────────────────────────────────────

  Widget _buildPresetChips() {
    final allPresets = <String, EqPreset>{...kBuiltInPresets, ..._userPresets};
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: allPresets.entries.map((entry) {
        final isActive = _activePreset == entry.key;
        final isUserPreset = _userPresets.containsKey(entry.key);
        return GestureDetector(
          onLongPress: isUserPreset
              ? () => _showDeletePresetDialog(entry.key)
              : null,
          child: ChoiceChip(
            label: Text(entry.key),
            selected: isActive,
            onSelected: (_) => _applyPreset(entry.key, entry.value),
            selectedColor: AfColors.indigo500.withValues(alpha: 0.3),
            backgroundColor: AfColors.surfaceHigh,
            labelStyle: AfTypography.bodySmall.copyWith(
              color: isActive ? AfColors.indigo400 : AfColors.textSecondary,
            ),
            side: isActive
                ? const BorderSide(color: AfColors.indigo500, width: 1.5)
                : BorderSide.none,
          ),
        );
      }).toList(),
    );
  }

  void _showDeletePresetDialog(String name) {
    showBlurDialog<void>(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Delete "$name"?', style: AfTypography.titleMedium),
          const SizedBox(height: AfSpacing.s12),
          Text(
            'This preset will be permanently removed.',
            style: AfTypography.bodyMedium,
          ),
          const SizedBox(height: AfSpacing.s24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _deletePreset(name);
                },
                child: Text(
                  'Delete',
                  style: AfTypography.bodyMedium.copyWith(
                    color: AfColors.semanticError,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
