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
import '../../state/providers.dart';

/// ISO 18-band center frequencies for the superequalizer.
const kEqBands = <String, String>{
  '1b': '65 Hz',
  '2b': '92 Hz',
  '3b': '131 Hz',
  '4b': '185 Hz',
  '5b': '262 Hz',
  '6b': '370 Hz',
  '7b': '523 Hz',
  '8b': '740 Hz',
  '9b': '1.0 kHz',
  '10b': '1.5 kHz',
  '11b': '2.1 kHz',
  '12b': '2.9 kHz',
  '13b': '4.2 kHz',
  '14b': '5.9 kHz',
  '15b': '8.3 kHz',
  '16b': '11.8 kHz',
  '17b': '16.7 kHz',
  '18b': '20 kHz',
};

/// Built-in EQ presets.
const kBuiltInPresets = <String, EqPreset>{
  'Flat': EqPreset(bands: {}, bass: 0, treble: 0),
  'Rock': EqPreset(
    bands: {'1b': 1.6, '2b': 1.4, '3b': 1.2, '4b': 1.0, '5b': 0.9,
             '6b': 0.8, '7b': 0.9, '8b': 1.1, '9b': 1.3, '10b': 1.5,
             '11b': 1.6, '12b': 1.5, '13b': 1.4, '14b': 1.3, '15b': 1.2,
             '16b': 1.1, '17b': 1.0, '18b': 1.0},
    bass: 3, treble: 1,
  ),
  'Jazz': EqPreset(
    bands: {'1b': 1.1, '2b': 1.1, '3b': 1.0, '4b': 1.2, '5b': 1.3,
             '6b': 1.3, '7b': 1.0, '8b': 1.1, '9b': 1.3, '10b': 1.4,
             '11b': 1.3, '12b': 1.2, '13b': 1.4, '14b': 1.3, '15b': 1.2,
             '16b': 1.1, '17b': 1.0, '18b': 1.0},
    bass: 2, treble: -1,
  ),
  'Classical': EqPreset(
    bands: {'1b': 1.0, '2b': 1.0, '3b': 1.0, '4b': 1.0, '5b': 1.0,
             '6b': 1.0, '7b': 1.0, '8b': 1.0, '9b': 1.1, '10b': 1.2,
             '11b': 1.3, '12b': 1.4, '13b': 1.3, '14b': 1.2, '15b': 1.1,
             '16b': 1.0, '17b': 1.0, '18b': 1.0},
    bass: 0, treble: 2,
  ),
  'Hip-Hop': EqPreset(
    bands: {'1b': 1.8, '2b': 1.7, '3b': 1.5, '4b': 1.3, '5b': 1.1,
             '6b': 1.0, '7b': 0.9, '8b': 0.9, '9b': 1.0, '10b': 1.0,
             '11b': 1.1, '12b': 1.2, '13b': 1.3, '14b': 1.2, '15b': 1.1,
             '16b': 1.0, '17b': 1.0, '18b': 1.0},
    bass: 5, treble: -1,
  ),
  'Electronic': EqPreset(
    bands: {'1b': 1.6, '2b': 1.5, '3b': 1.3, '4b': 1.1, '5b': 1.0,
             '6b': 0.9, '7b': 1.0, '8b': 1.2, '9b': 1.4, '10b': 1.5,
             '11b': 1.5, '12b': 1.4, '13b': 1.5, '14b': 1.6, '15b': 1.5,
             '16b': 1.4, '17b': 1.3, '18b': 1.2},
    bass: 4, treble: 3,
  ),
  'Vocal': EqPreset(
    bands: {'1b': 0.8, '2b': 0.9, '3b': 0.9, '4b': 1.0, '5b': 1.1,
             '6b': 1.3, '7b': 1.5, '8b': 1.6, '9b': 1.6, '10b': 1.5,
             '11b': 1.4, '12b': 1.3, '13b': 1.2, '14b': 1.1, '15b': 1.0,
             '16b': 0.9, '17b': 0.9, '18b': 0.9},
    bass: -2, treble: 1,
  ),
  'Bass Boost': EqPreset(
    bands: {'1b': 2.2, '2b': 2.0, '3b': 1.8, '4b': 1.5, '5b': 1.2,
             '6b': 1.0, '7b': 1.0, '8b': 1.0, '9b': 1.0, '10b': 1.0,
             '11b': 1.0, '12b': 1.0, '13b': 1.0, '14b': 1.0, '15b': 1.0,
             '16b': 1.0, '17b': 1.0, '18b': 1.0},
    bass: 6, treble: 0,
  ),
  'Treble Boost': EqPreset(
    bands: {'1b': 1.0, '2b': 1.0, '3b': 1.0, '4b': 1.0, '5b': 1.0,
             '6b': 1.0, '7b': 1.0, '8b': 1.0, '9b': 1.0, '10b': 1.0,
             '11b': 1.1, '12b': 1.2, '13b': 1.4, '14b': 1.6, '15b': 1.8,
             '16b': 2.0, '17b': 2.0, '18b': 1.8},
    bass: 0, treble: 5,
  ),
};

class EqDspScreen extends ConsumerStatefulWidget {
  const EqDspScreen({super.key});

  @override
  ConsumerState<EqDspScreen> createState() => _EqDspScreenState();
}

class _EqDspScreenState extends ConsumerState<EqDspScreen> {
  // ── Master toggle ──
  bool _masterEnabled = true;

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

  // ── Gate (fine-tuning) ──
  bool _gate = false;
  double _gateThreshold = 0.01;
  double _gateRatio = 2.0;
  double _gateAttack = 20.0;
  double _gateRelease = 250.0;

  // ── De-esser (fine-tuning) ──
  bool _deesser = false;
  double _deesserIntensity = 0.0;
  double _deesserMix = 0.5;
  double _deesserFreq = 5500.0;

  // ── 18-band EQ (linear gain; 1.0 = flat, range 0–4) ──
  bool _eqEnabled = false;
  final Map<String, double> _eqBands = {
    for (final k in kEqBands.keys) k: 1.0,
  };

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
    _deesserIntensity = fx.deesser.i;
    _deesserMix = fx.deesser.m;
    _deesserFreq = fx.deesser.f;
    // Echo
    _echoEnabled = fx.aecho.enabled;
    _echoInGain = fx.aecho.in_gain;
    _echoOutGain = fx.aecho.out_gain;
    _echoDelays = fx.aecho.delays;
    _echoDecays = fx.aecho.decays;
    // Modulation
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
    // Master toggle — on if any effect is active
    _masterEnabled = _bass != 0 || _treble != 0 || _loudnorm || _compressor ||
        _eqEnabled || _rubberbandEnabled || _crossfeed || _stereoWiden ||
        _exciter || _crystalizer || _virtualBass || _gate || _deesser ||
        _echoEnabled || _phaser || _flanger || _chorus || _tremolo ||
        _vibrato || _crusher;
    // Load presets
    _loadPresets();
  }

  Future<void> _loadPresets() async {
    final presets = await PlayerSettingsStore.loadEqPresetsAsync();
    if (mounted) {
      setState(() => _userPresets = presets);
    }
  }

  void _apply() {
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
      aexciter: AexciterSettings(
        enabled: _exciter,
        amount: _exciterAmount,
      ),
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
    unawaited(svc.setAudioEffects(effects));
    unawaited(PlayerSettingsStore.saveAudioEffects(effects));
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
      _deesserFreq = 5500.0;
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
    unawaited(ref
        .read(playerServiceProvider)
        .setAudioEffects(const AudioEffects()));
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
    _apply();
    unawaited(PlayerSettingsStore.saveActivePreset(name));
  }

  Future<void> _saveCurrentAsPreset() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AfColors.surfaceBase,
        title: const Text('Save EQ Preset'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Preset name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final preset = EqPreset(
      bands: Map.of(_eqBands),
      bass: _bass,
      treble: _treble,
    );
    await PlayerSettingsStore.saveEqPreset(name, preset);
    setState(() {
      _userPresets[name] = preset;
      _activePreset = name;
    });
  }

  Future<void> _deletePreset(String name) async {
    await PlayerSettingsStore.deleteEqPreset(name);
    setState(() {
      _userPresets.remove(name);
      if (_activePreset == name) _activePreset = null;
    });
  }

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
              if (v) {
                _apply();
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
              style: AfTypography.bodySmall
                  .copyWith(color: AfColors.semanticError),
            ),
          ),
        ],
      ),
      body: AnimatedOpacity(
          opacity: _masterEnabled ? 1.0 : 0.4,
          duration: const Duration(milliseconds: 200),
          child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16, vertical: AfSpacing.s8),
        children: [
          IgnorePointer(
            ignoring: !_masterEnabled,
            child: Container(
              decoration: BoxDecoration(
                color: AfColors.surfaceBase,
                borderRadius: AfRadii.borderLg,
              ),
              padding: const EdgeInsets.all(AfSpacing.s16),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
          // ── EQ Presets ─────────────────────────────────────────────────
          _sectionHeader('EQ Presets'),
          _buildPresetChips(),
          const SizedBox(height: AfSpacing.s8),

        _divider(),

        // ── Tone shelves ───────────────────────────────────────────────
        _sectionHeader('Tone'),
        _sliderRow('Bass', _bass, -12, 12, 24, (v) {
          setState(() {
            _bass = v;
            _activePreset = null;
          });
        }, _apply, suffix: 'dB'),
        _sliderRow('Treble', _treble, -12, 12, 24, (v) {
          setState(() {
            _treble = v;
            _activePreset = null;
          });
        }, _apply, suffix: 'dB'),

        _divider(),

        // ── 18-band graphic EQ ─────────────────────────────────────────
        _sectionHeader('18-band Equalizer'),
        SwitchListTile.adaptive(
          value: _eqEnabled,
          onChanged: (v) {
            setState(() => _eqEnabled = v);
            _apply();
          },
          title: Text('Enable graphic EQ', style: AfTypography.bodyMedium),
          activeThumbColor: AfColors.indigo500,
          contentPadding: EdgeInsets.zero,
        ),
        if (_eqEnabled) ..._buildEqBands(),
        if (_eqEnabled)
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
                  _apply();
                },
                child: Text(
                  'Flatten EQ',
                  style: AfTypography.bodySmall
                      .copyWith(color: AfColors.textTertiary),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _saveCurrentAsPreset,
                icon: const Icon(Icons.save_outlined, size: 16),
                label: Text(
                  'Save preset',
                  style: AfTypography.bodySmall
                      .copyWith(color: AfColors.indigo400),
                ),
              ),
            ],
          ),

        _divider(),

        // ── Dynamics ───────────────────────────────────────────────────
        _sectionHeader('Dynamics'),
        _toggleTile('Loudness normalization', 'EBU R128 (-16 LUFS)',
            _loudnorm, (v) {
          setState(() => _loudnorm = v);
          _apply();
        }),
        // Compressor with fine-tuning
        SwitchListTile.adaptive(
          value: _compressor,
          onChanged: (v) {
            setState(() => _compressor = v);
            _apply();
          },
          title: Text('Dynamic compressor', style: AfTypography.bodyMedium),
          subtitle: Text(
            'Reduces volume spikes',
            style: AfTypography.bodySmall
                .copyWith(color: AfColors.textTertiary),
          ),
          activeThumbColor: AfColors.indigo500,
          contentPadding: EdgeInsets.zero,
        ),
        if (_compressor) ...[
          _sliderRow('Threshold', _compThreshold, 0.001, 1.0, 100, (v) {
            setState(() => _compThreshold = v);
          }, _apply, precision: 3),
          _sliderRow('Ratio', _compRatio, 1.0, 20.0, 38, (v) {
            setState(() => _compRatio = v);
          }, _apply, precision: 1, suffix: ':1'),
          _sliderRow('Attack', _compAttack, 0.01, 200.0, 100, (v) {
            setState(() => _compAttack = v);
          }, _apply, precision: 1, suffix: 'ms'),
          _sliderRow('Release', _compRelease, 5.0, 2000.0, 100, (v) {
            setState(() => _compRelease = v);
          }, _apply, precision: 0, suffix: 'ms'),
        ],
        // Gate with fine-tuning
        SwitchListTile.adaptive(
          value: _gate,
          onChanged: (v) {
            setState(() => _gate = v);
            _apply();
          },
          title: Text('Noise gate', style: AfTypography.bodyMedium),
          subtitle: Text(
            'Silences signal below threshold',
            style: AfTypography.bodySmall
                .copyWith(color: AfColors.textTertiary),
          ),
          activeThumbColor: AfColors.indigo500,
          contentPadding: EdgeInsets.zero,
        ),
        if (_gate) ...[
          _sliderRow('Threshold', _gateThreshold, 0.001, 1.0, 100, (v) {
            setState(() => _gateThreshold = v);
          }, _apply, precision: 3),
          _sliderRow('Ratio', _gateRatio, 1.0, 20.0, 38, (v) {
            setState(() => _gateRatio = v);
          }, _apply, precision: 1, suffix: ':1'),
          _sliderRow('Attack', _gateAttack, 0.01, 200.0, 100, (v) {
            setState(() => _gateAttack = v);
          }, _apply, precision: 1, suffix: 'ms'),
          _sliderRow('Release', _gateRelease, 5.0, 2000.0, 100, (v) {
            setState(() => _gateRelease = v);
          }, _apply, precision: 0, suffix: 'ms'),
        ],
        // De-esser with fine-tuning
        SwitchListTile.adaptive(
          value: _deesser,
          onChanged: (v) {
            setState(() => _deesser = v);
            _apply();
          },
          title: Text('De-esser', style: AfTypography.bodyMedium),
          subtitle: Text(
            'Reduces sibilance',
            style: AfTypography.bodySmall
                .copyWith(color: AfColors.textTertiary),
          ),
          activeThumbColor: AfColors.indigo500,
          contentPadding: EdgeInsets.zero,
        ),
        if (_deesser) ...[
          _sliderRow('Intensity', _deesserIntensity, 0.0, 1.0, 20, (v) {
            setState(() => _deesserIntensity = v);
          }, _apply, precision: 2),
          _sliderRow('Mix', _deesserMix, 0.0, 1.0, 20, (v) {
            setState(() => _deesserMix = v);
          }, _apply, precision: 2),
          _sliderRow('Frequency', _deesserFreq, 2000.0, 12000.0, 100, (v) {
            setState(() => _deesserFreq = v);
          }, _apply, precision: 0, suffix: 'Hz'),
        ],

        _divider(),

        // ── Echo / Delay ───────────────────────────────────────────────
        _sectionHeader('Echo / Delay'),
        SwitchListTile.adaptive(
          value: _echoEnabled,
          onChanged: (v) {
            setState(() => _echoEnabled = v);
            _apply();
          },
          title: Text('Echo', style: AfTypography.bodyMedium),
          subtitle: Text(
            'Multi-tap delay effect',
            style: AfTypography.bodySmall
                .copyWith(color: AfColors.textTertiary),
          ),
          activeThumbColor: AfColors.indigo500,
          contentPadding: EdgeInsets.zero,
        ),
        if (_echoEnabled) ...[
          _sliderRow('In gain', _echoInGain, 0.0, 1.0, 20, (v) {
            setState(() => _echoInGain = v);
          }, _apply, precision: 2),
          _sliderRow('Out gain', _echoOutGain, 0.0, 1.0, 20, (v) {
            setState(() => _echoOutGain = v);
          }, _apply, precision: 2),
          _textFieldRow('Delays (ms)', _echoDelays, 'e.g. 500|250', (v) {
            setState(() => _echoDelays = v);
            _apply();
          }),
          _textFieldRow('Decays (0-1)', _echoDecays, 'e.g. 0.5|0.3', (v) {
            setState(() => _echoDecays = v);
            _apply();
          }),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              'Separate multiple taps with | (pipe)',
              style: AfTypography.bodySmall
                  .copyWith(color: AfColors.textTertiary, fontSize: 11),
            ),
          ),
        ],

        _divider(),

        // ── Pitch & tempo ──────────────────────────────────────────────
        _sectionHeader('Pitch & Tempo'),
        SwitchListTile.adaptive(
          value: _rubberbandEnabled,
          onChanged: (v) {
            setState(() => _rubberbandEnabled = v);
            _apply();
          },
          title:
              Text('Enable pitch/tempo shift', style: AfTypography.bodyMedium),
          subtitle: Text(
            'High-quality rubberband engine',
            style: AfTypography.bodySmall
                .copyWith(color: AfColors.textTertiary),
          ),
          activeThumbColor: AfColors.indigo500,
          contentPadding: EdgeInsets.zero,
        ),
        if (_rubberbandEnabled) ...[
          _sliderRow(
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
          _sliderRow(
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

        _divider(),

        // ── Spatial ────────────────────────────────────────────────────
        _sectionHeader('Spatial'),
        SwitchListTile.adaptive(
          value: _crossfeed,
          onChanged: (v) {
            setState(() => _crossfeed = v);
            _apply();
          },
          title: Text('Crossfeed', style: AfTypography.bodyMedium),
          subtitle: Text(
            'Headphone crossfeed for natural imaging',
            style: AfTypography.bodySmall
                .copyWith(color: AfColors.textTertiary),
          ),
          activeThumbColor: AfColors.indigo500,
          contentPadding: EdgeInsets.zero,
        ),
        if (_crossfeed)
          _sliderRow(
            'Strength',
            _crossfeedStrength,
            0.0,
            1.0,
            20,
            (v) => setState(() => _crossfeedStrength = v),
            _apply,
            precision: 2,
          ),
        SwitchListTile.adaptive(
          value: _stereoWiden,
          onChanged: (v) {
            setState(() => _stereoWiden = v);
            _apply();
          },
          title: Text('Stereo widening', style: AfTypography.bodyMedium),
          subtitle: Text(
            'Expands stereo image',
            style: AfTypography.bodySmall
                .copyWith(color: AfColors.textTertiary),
          ),
          activeThumbColor: AfColors.indigo500,
          contentPadding: EdgeInsets.zero,
        ),
        if (_stereoWiden)
          _sliderRow(
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

        _divider(),

        // ── Modulation ─────────────────────────────────────────────────
        _sectionHeader('Modulation'),
        // Phaser
        SwitchListTile.adaptive(
          value: _phaser,
          onChanged: (v) {
            setState(() => _phaser = v);
            _apply();
          },
          title: Text('Phaser', style: AfTypography.bodyMedium),
          subtitle: Text(
            'Phase-shifting sweep effect',
            style: AfTypography.bodySmall
                .copyWith(color: AfColors.textTertiary),
          ),
          activeThumbColor: AfColors.indigo500,
          contentPadding: EdgeInsets.zero,
        ),
        if (_phaser) ...[
          _sliderRow('In gain', _phaserInGain, 0.0, 1.0, 20, (v) {
            setState(() => _phaserInGain = v);
          }, _apply, precision: 2),
          _sliderRow('Out gain', _phaserOutGain, 0.0, 1.0, 20, (v) {
            setState(() => _phaserOutGain = v);
          }, _apply, precision: 2),
          _sliderRow('Delay', _phaserDelay, 0.0, 5.0, 50, (v) {
            setState(() => _phaserDelay = v);
          }, _apply, precision: 1, suffix: 'ms'),
          _sliderRow('Decay', _phaserDecay, 0.0, 0.99, 99, (v) {
            setState(() => _phaserDecay = v);
          }, _apply, precision: 2),
          _sliderRow('Speed', _phaserSpeed, 0.1, 2.0, 19, (v) {
            setState(() => _phaserSpeed = v);
          }, _apply, precision: 2, suffix: 'Hz'),
        ],
        // Flanger
        SwitchListTile.adaptive(
          value: _flanger,
          onChanged: (v) {
            setState(() => _flanger = v);
            _apply();
          },
          title: Text('Flanger', style: AfTypography.bodyMedium),
          subtitle: Text(
            'Flanging with feedback',
            style: AfTypography.bodySmall
                .copyWith(color: AfColors.textTertiary),
          ),
          activeThumbColor: AfColors.indigo500,
          contentPadding: EdgeInsets.zero,
        ),
        if (_flanger) ...[
          _sliderRow('Delay', _flangerDelay, 0.0, 30.0, 60, (v) {
            setState(() => _flangerDelay = v);
          }, _apply, precision: 1, suffix: 'ms'),
          _sliderRow('Depth', _flangerDepth, 0.0, 10.0, 20, (v) {
            setState(() => _flangerDepth = v);
          }, _apply, precision: 1),
          _sliderRow('Regen', _flangerRegen, -95.0, 95.0, 38, (v) {
            setState(() => _flangerRegen = v);
          }, _apply, precision: 0, suffix: '%'),
          _sliderRow('Width', _flangerWidth, 0.0, 100.0, 20, (v) {
            setState(() => _flangerWidth = v);
          }, _apply, precision: 0, suffix: '%'),
          _sliderRow('Speed', _flangerSpeed, 0.1, 10.0, 99, (v) {
            setState(() => _flangerSpeed = v);
          }, _apply, precision: 1, suffix: 'Hz'),
        ],
        // Chorus
        SwitchListTile.adaptive(
          value: _chorus,
          onChanged: (v) {
            setState(() => _chorus = v);
            _apply();
          },
          title: Text('Chorus', style: AfTypography.bodyMedium),
          subtitle: Text(
            'Multi-voice chorus effect',
            style: AfTypography.bodySmall
                .copyWith(color: AfColors.textTertiary),
          ),
          activeThumbColor: AfColors.indigo500,
          contentPadding: EdgeInsets.zero,
        ),
        if (_chorus) ...[
          _sliderRow('In gain', _chorusInGain, 0.0, 1.0, 20, (v) {
            setState(() => _chorusInGain = v);
          }, _apply, precision: 2),
          _sliderRow('Out gain', _chorusOutGain, 0.0, 1.0, 20, (v) {
            setState(() => _chorusOutGain = v);
          }, _apply, precision: 2),
          _textFieldRow('Delays (ms)', _chorusDelays, 'e.g. 40|60', (v) {
            setState(() => _chorusDelays = v);
            _apply();
          }),
          _textFieldRow('Decays', _chorusDecays, 'e.g. 0.4|0.32', (v) {
            setState(() => _chorusDecays = v);
            _apply();
          }),
          _textFieldRow('Speeds (Hz)', _chorusSpeeds, 'e.g. 0.25|0.4', (v) {
            setState(() => _chorusSpeeds = v);
            _apply();
          }),
          _textFieldRow('Depths', _chorusDepths, 'e.g. 2|3', (v) {
            setState(() => _chorusDepths = v);
            _apply();
          }),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              'Separate multiple voices with | (pipe)',
              style: AfTypography.bodySmall
                  .copyWith(color: AfColors.textTertiary, fontSize: 11),
            ),
          ),
        ],
        // Tremolo
        SwitchListTile.adaptive(
          value: _tremolo,
          onChanged: (v) {
            setState(() => _tremolo = v);
            _apply();
          },
          title: Text('Tremolo', style: AfTypography.bodyMedium),
          subtitle: Text(
            'Amplitude modulation',
            style: AfTypography.bodySmall
                .copyWith(color: AfColors.textTertiary),
          ),
          activeThumbColor: AfColors.indigo500,
          contentPadding: EdgeInsets.zero,
        ),
        if (_tremolo) ...[
          _sliderRow('Frequency', _tremoloFreq, 0.1, 20.0, 40, (v) {
            setState(() => _tremoloFreq = v);
          }, _apply, precision: 1, suffix: 'Hz'),
          _sliderRow('Depth', _tremoloDepth, 0.0, 1.0, 20, (v) {
            setState(() => _tremoloDepth = v);
          }, _apply, precision: 2),
        ],
        // Vibrato
        SwitchListTile.adaptive(
          value: _vibrato,
          onChanged: (v) {
            setState(() => _vibrato = v);
            _apply();
          },
          title: Text('Vibrato', style: AfTypography.bodyMedium),
          subtitle: Text(
            'Pitch modulation',
            style: AfTypography.bodySmall
                .copyWith(color: AfColors.textTertiary),
          ),
          activeThumbColor: AfColors.indigo500,
          contentPadding: EdgeInsets.zero,
        ),
        if (_vibrato) ...[
          _sliderRow('Frequency', _vibratoFreq, 0.1, 20.0, 40, (v) {
            setState(() => _vibratoFreq = v);
          }, _apply, precision: 1, suffix: 'Hz'),
          _sliderRow('Depth', _vibratoDepth, 0.0, 1.0, 20, (v) {
            setState(() => _vibratoDepth = v);
          }, _apply, precision: 2),
        ],

        _divider(),

        // ── Creative ───────────────────────────────────────────────────
        _sectionHeader('Creative'),
        SwitchListTile.adaptive(
          value: _exciter,
          onChanged: (v) {
            setState(() => _exciter = v);
            _apply();
          },
          title: Text('Harmonic exciter', style: AfTypography.bodyMedium),
          subtitle: Text(
            'Adds harmonic overtones',
            style: AfTypography.bodySmall
                .copyWith(color: AfColors.textTertiary),
          ),
          activeThumbColor: AfColors.indigo500,
          contentPadding: EdgeInsets.zero,
        ),
        if (_exciter)
          _sliderRow(
            'Amount',
            _exciterAmount,
            0.0,
            10.0,
            20,
            (v) => setState(() => _exciterAmount = v),
            _apply,
            precision: 1,
          ),
        SwitchListTile.adaptive(
          value: _crystalizer,
          onChanged: (v) {
            setState(() => _crystalizer = v);
            _apply();
          },
          title: Text('Crystalizer', style: AfTypography.bodyMedium),
          subtitle: Text(
            'Audio sharpener / brightener',
            style: AfTypography.bodySmall
                .copyWith(color: AfColors.textTertiary),
          ),
          activeThumbColor: AfColors.indigo500,
          contentPadding: EdgeInsets.zero,
        ),
        if (_crystalizer)
          _sliderRow(
            'Intensity',
            _crystalizerIntensity,
            -10.0,
            10.0,
            40,
            (v) => setState(() => _crystalizerIntensity = v),
            _apply,
            precision: 1,
          ),
        SwitchListTile.adaptive(
          value: _virtualBass,
          onChanged: (v) {
            setState(() => _virtualBass = v);
            _apply();
          },
          title: Text('Virtual bass', style: AfTypography.bodyMedium),
          subtitle: Text(
            'Psychoacoustic bass enhancement',
            style: AfTypography.bodySmall
                .copyWith(color: AfColors.textTertiary),
          ),
          activeThumbColor: AfColors.indigo500,
          contentPadding: EdgeInsets.zero,
        ),
        if (_virtualBass)
          _sliderRow(
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
        // Bit-crusher
        SwitchListTile.adaptive(
          value: _crusher,
          onChanged: (v) {
            setState(() => _crusher = v);
            _apply();
          },
          title: Text('Bit-crusher', style: AfTypography.bodyMedium),
          subtitle: Text(
            'Lo-fi resolution and rate reduction',
            style: AfTypography.bodySmall
                .copyWith(color: AfColors.textTertiary),
          ),
          activeThumbColor: AfColors.indigo500,
          contentPadding: EdgeInsets.zero,
        ),
        if (_crusher) ...[
          _sliderRow('Bits', _crusherBits, 1.0, 16.0, 15, (v) {
            setState(() => _crusherBits = v);
          }, _apply, precision: 0),
          _sliderRow('Mix', _crusherMix, 0.0, 1.0, 20, (v) {
            setState(() => _crusherMix = v);
          }, _apply, precision: 2),
          _sliderRow('Samples', _crusherSamples, 1.0, 250.0, 50, (v) {
            setState(() => _crusherSamples = v);
          }, _apply, precision: 0),
        ],

        const SizedBox(height: AfSpacing.s24),
              ],
            ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Widget _buildPresetChips() {
    final allPresets = <String, EqPreset>{
      ...kBuiltInPresets,
      ..._userPresets,
    };
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
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AfColors.surfaceBase,
        title: Text('Delete "$name"?'),
        content: const Text('This preset will be permanently removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deletePreset(name);
            },
            child: Text(
              'Delete',
              style: TextStyle(color: AfColors.semanticError),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.only(top: AfSpacing.s16, bottom: AfSpacing.s8),
        child: Text(title,
            style: AfTypography.bodySmall.copyWith(
              color: AfColors.textTertiary,
              fontWeight: FontWeight.w600,
            )),
      );

  Widget _divider() => const Padding(
        padding: EdgeInsets.symmetric(vertical: AfSpacing.s12),
        child: Divider(height: 0, thickness: 0.5, color: AfColors.surfaceHigh),
      );

  Widget _toggleTile(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return SwitchListTile.adaptive(
      value: value,
      onChanged: onChanged,
      title: Text(title, style: AfTypography.bodyMedium),
      subtitle: Text(
        subtitle,
        style:
            AfTypography.bodySmall.copyWith(color: AfColors.textTertiary),
      ),
      activeThumbColor: AfColors.indigo500,
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _sliderRow(
    String label,
    double value,
    double min,
    double max,
    int divisions,
    ValueChanged<double> onChanged,
    VoidCallback onChangeEnd, {
    String? suffix,
    int precision = 0,
  }) {
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
              style:
                  AfTypography.mono.copyWith(color: AfColors.textTertiary),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          activeColor: AfColors.indigo400,
          onChanged: onChanged,
          onChangeEnd: (_) => onChangeEnd(),
        ),
      ],
    );
  }

  Widget _textFieldRow(
    String label,
    String value,
    String hint,
    ValueChanged<String> onSubmitted,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: AfTypography.bodySmall),
          ),
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
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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

  /// Only include bands that differ from the flat default (1.0).
  Map<String, double> _buildEqParams() {
    final params = <String, double>{};
    for (final entry in _eqBands.entries) {
      if (entry.value != 1.0) params[entry.key] = entry.value;
    }
    return params;
  }

  List<Widget> _buildEqBands() {
    return kEqBands.entries.map((entry) {
      final bandKey = entry.key;
      final freq = entry.value;
      final gain = _eqBands[bandKey] ?? 1.0;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 58,
              child: Text(
                freq,
                style: AfTypography.mono.copyWith(
                  fontSize: 11,
                  color: AfColors.textTertiary,
                ),
              ),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 12),
                ),
                child: Slider(
                  value: gain.clamp(0.0, 4.0),
                  min: 0,
                  max: 4,
                  divisions: 40,
                  activeColor: AfColors.indigo400,
                  onChanged: (v) {
                    setState(() {
                      _eqBands[bandKey] = v;
                      _activePreset = null;
                    });
                  },
                  onChangeEnd: (_) => _apply(),
                ),
              ),
            ),
            SizedBox(
              width: 36,
              child: Text(
                gain.toStringAsFixed(1),
                textAlign: TextAlign.right,
                style: AfTypography.mono.copyWith(
                  fontSize: 11,
                  color: AfColors.textTertiary,
                ),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }
}
