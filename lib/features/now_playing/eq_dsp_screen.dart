import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
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
import 'eq_dsp_sections.dart';
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

  // ── Accordion state ──
  int? _openSection;

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
    _chorusDelays = fx.chorus.delays;
    _chorusDecays = fx.chorus.decays;
    _chorusSpeeds = fx.chorus.speeds;
    _chorusDepths = fx.chorus.depths;
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
      _openSection = null;
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

  // ── Badge counts ─────────────────────────────────────────────────────────

  int get _dynamicsCount =>
      (_loudnorm ? 1 : 0) +
      (_compressor ? 1 : 0) +
      (_gate ? 1 : 0) +
      (_deesser ? 1 : 0);

  int get _modulationCount =>
      (_phaser ? 1 : 0) +
      (_flanger ? 1 : 0) +
      (_chorus ? 1 : 0) +
      (_tremolo ? 1 : 0) +
      (_vibrato ? 1 : 0);

  int get _creativeCount =>
      (_exciter ? 1 : 0) +
      (_crystalizer ? 1 : 0) +
      (_virtualBass ? 1 : 0) +
      (_crusher ? 1 : 0);

  // ── Master toggle handler ────────────────────────────────────────────────

  void _onMasterChanged(bool v) {
    setState(() => _masterEnabled = v);
    unawaited(PlayerSettingsStore.saveDspMasterEnabled(v));
    if (v) {
      unawaited(_apply());
    } else {
      final svc = ref.read(playerServiceProvider);
      unawaited(svc.setAudioEffects(const AudioEffects()));
    }
  }

  // ── Section field change handler ─────────────────────────────────────────

  /// Updates a single effect field without triggering a parent rebuild.
  ///
  /// The parent state variables are updated silently so that [_apply]
  /// (called on drag-end / toggle / preset) reads the correct values.
  /// Each section's own [setState] handles its local UI rebuild — the
  /// parent tree is NOT rebuilt on every slider drag.
  void _onFieldChanged(String field, dynamic value) {
    switch (field) {
      case 'loudnorm':
        _loudnorm = value as bool;
      case 'compressor':
        _compressor = value as bool;
      case 'compThreshold':
        _compThreshold = value as double;
      case 'compRatio':
        _compRatio = value as double;
      case 'compAttack':
        _compAttack = value as double;
      case 'compRelease':
        _compRelease = value as double;
      case 'gate':
        _gate = value as bool;
      case 'gateThreshold':
        _gateThreshold = value as double;
      case 'gateRatio':
        _gateRatio = value as double;
      case 'gateAttack':
        _gateAttack = value as double;
      case 'gateRelease':
        _gateRelease = value as double;
      case 'deesser':
        _deesser = value as bool;
      case 'deesserIntensity':
        _deesserIntensity = value as double;
      case 'deesserMix':
        _deesserMix = value as double;
      case 'deesserFreq':
        _deesserFreq = value as double;
      case 'echoEnabled':
        _echoEnabled = value as bool;
      case 'echoInGain':
        _echoInGain = value as double;
      case 'echoOutGain':
        _echoOutGain = value as double;
      case 'echoDelays':
        _echoDelays = value as String;
      case 'echoDecays':
        _echoDecays = value as String;
      case 'rubberbandEnabled':
        _rubberbandEnabled = value as bool;
      case 'pitch':
        _pitch = value as double;
      case 'tempo':
        _tempo = value as double;
      case 'crossfeed':
        _crossfeed = value as bool;
      case 'crossfeedStrength':
        _crossfeedStrength = value as double;
      case 'stereoWiden':
        _stereoWiden = value as bool;
      case 'stereoWidenDelay':
        _stereoWidenDelay = value as double;
      case 'phaser':
        _phaser = value as bool;
      case 'phaserInGain':
        _phaserInGain = value as double;
      case 'phaserOutGain':
        _phaserOutGain = value as double;
      case 'phaserDelay':
        _phaserDelay = value as double;
      case 'phaserDecay':
        _phaserDecay = value as double;
      case 'phaserSpeed':
        _phaserSpeed = value as double;
      case 'flanger':
        _flanger = value as bool;
      case 'flangerDelay':
        _flangerDelay = value as double;
      case 'flangerDepth':
        _flangerDepth = value as double;
      case 'flangerRegen':
        _flangerRegen = value as double;
      case 'flangerWidth':
        _flangerWidth = value as double;
      case 'flangerSpeed':
        _flangerSpeed = value as double;
      case 'chorus':
        _chorus = value as bool;
      case 'chorusInGain':
        _chorusInGain = value as double;
      case 'chorusOutGain':
        _chorusOutGain = value as double;
      case 'chorusDelays':
        _chorusDelays = value as String;
      case 'chorusDecays':
        _chorusDecays = value as String;
      case 'chorusSpeeds':
        _chorusSpeeds = value as String;
      case 'chorusDepths':
        _chorusDepths = value as String;
      case 'tremolo':
        _tremolo = value as bool;
      case 'tremoloFreq':
        _tremoloFreq = value as double;
      case 'tremoloDepth':
        _tremoloDepth = value as double;
      case 'vibrato':
        _vibrato = value as bool;
      case 'vibratoFreq':
        _vibratoFreq = value as double;
      case 'vibratoDepth':
        _vibratoDepth = value as double;
      case 'exciter':
        _exciter = value as bool;
      case 'exciterAmount':
        _exciterAmount = value as double;
      case 'crystalizer':
        _crystalizer = value as bool;
      case 'crystalizerIntensity':
        _crystalizerIntensity = value as double;
      case 'virtualBass':
        _virtualBass = value as bool;
      case 'virtualBassCutoff':
        _virtualBassCutoff = value as double;
      case 'crusher':
        _crusher = value as bool;
      case 'crusherBits':
        _crusherBits = value as double;
      case 'crusherMix':
        _crusherMix = value as double;
      case 'crusherSamples':
        _crusherSamples = value as double;
    }
    _activePreset = null;
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
              children: [
                // Master banner
                EqMasterBanner(
                  enabled: _masterEnabled,
                  onChanged: _onMasterChanged,
                ),
                const SizedBox(height: AfSpacing.s12),

                // EQ Presets
                eqSectionLabel('EQ Presets'),
                eqCard([_buildPresetChips()]),
                const SizedBox(height: AfSpacing.s16),

                // Accordion sections
                ..._buildAccordionSections(),

                const SizedBox(height: AfSpacing.s24),
              ],
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

  // ── Accordion Sections ──────────────────────────────────────────────────

  List<Widget> _buildAccordionSections() {
    final sections = [
      _buildAccordion(
        0,
        'Tone',
        null,
        EqToneSection(
          bass: _bass,
          treble: _treble,
          onBassChanged: (v) => setState(() {
            _bass = v;
            _activePreset = null;
          }),
          onTrebleChanged: (v) => setState(() {
            _treble = v;
            _activePreset = null;
          }),
          onApply: _apply,
        ),
      ),
      _buildAccordion(
        1,
        '18-Band Equalizer',
        _eqEnabled ? 18 : null,
        _buildEqContent(),
      ),
      _buildAccordion(
        2,
        'Dynamics',
        _dynamicsCount > 0 ? _dynamicsCount : null,
        EqDynamicsSection(
          loudnorm: _loudnorm,
          compressor: _compressor,
          compThreshold: _compThreshold,
          compRatio: _compRatio,
          compAttack: _compAttack,
          compRelease: _compRelease,
          gate: _gate,
          gateThreshold: _gateThreshold,
          gateRatio: _gateRatio,
          gateAttack: _gateAttack,
          gateRelease: _gateRelease,
          deesser: _deesser,
          deesserIntensity: _deesserIntensity,
          deesserMix: _deesserMix,
          deesserFreq: _deesserFreq,
          onChanged: _onFieldChanged,
          onApply: _apply,
        ),
      ),
      _buildAccordion(
        3,
        'Echo / Delay',
        _echoEnabled ? 1 : null,
        EqEchoSection(
          echoEnabled: _echoEnabled,
          echoInGain: _echoInGain,
          echoOutGain: _echoOutGain,
          echoDelays: _echoDelays,
          echoDecays: _echoDecays,
          onChanged: _onFieldChanged,
          onApply: _apply,
        ),
      ),
      _buildAccordion(
        4,
        'Pitch & Tempo',
        _rubberbandEnabled ? 1 : null,
        EqPitchSection(
          rubberbandEnabled: _rubberbandEnabled,
          pitch: _pitch,
          tempo: _tempo,
          onChanged: _onFieldChanged,
          onApply: _apply,
        ),
      ),
      _buildAccordion(
        5,
        'Spatial',
        (_crossfeed || _stereoWiden) ? 1 : null,
        EqSpatialSection(
          crossfeed: _crossfeed,
          crossfeedStrength: _crossfeedStrength,
          stereoWiden: _stereoWiden,
          stereoWidenDelay: _stereoWidenDelay,
          onChanged: _onFieldChanged,
          onApply: _apply,
        ),
      ),
      _buildAccordion(
        6,
        'Modulation',
        _modulationCount > 0 ? _modulationCount : null,
        EqModulationSection(
          phaser: _phaser,
          phaserInGain: _phaserInGain,
          phaserOutGain: _phaserOutGain,
          phaserDelay: _phaserDelay,
          phaserDecay: _phaserDecay,
          phaserSpeed: _phaserSpeed,
          flanger: _flanger,
          flangerDelay: _flangerDelay,
          flangerDepth: _flangerDepth,
          flangerRegen: _flangerRegen,
          flangerWidth: _flangerWidth,
          flangerSpeed: _flangerSpeed,
          chorus: _chorus,
          chorusInGain: _chorusInGain,
          chorusOutGain: _chorusOutGain,
          chorusDelays: _chorusDelays,
          chorusDecays: _chorusDecays,
          chorusSpeeds: _chorusSpeeds,
          chorusDepths: _chorusDepths,
          tremolo: _tremolo,
          tremoloFreq: _tremoloFreq,
          tremoloDepth: _tremoloDepth,
          vibrato: _vibrato,
          vibratoFreq: _vibratoFreq,
          vibratoDepth: _vibratoDepth,
          onChanged: _onFieldChanged,
          onApply: _apply,
        ),
      ),
      _buildAccordion(
        7,
        'Creative',
        _creativeCount > 0 ? _creativeCount : null,
        EqCreativeSection(
          exciter: _exciter,
          exciterAmount: _exciterAmount,
          crystalizer: _crystalizer,
          crystalizerIntensity: _crystalizerIntensity,
          virtualBass: _virtualBass,
          virtualBassCutoff: _virtualBassCutoff,
          crusher: _crusher,
          crusherBits: _crusherBits,
          crusherMix: _crusherMix,
          crusherSamples: _crusherSamples,
          onChanged: _onFieldChanged,
          onApply: _apply,
        ),
      ),
    ];

    return sections
        .map(
          (child) => RepaintBoundary(
            child: Opacity(
              opacity: _masterEnabled ? 1.0 : 0.4,
              child: AbsorbPointer(absorbing: !_masterEnabled, child: child),
            ),
          ),
        )
        .toList();
  }

  Widget _buildAccordion(int index, String label, int? badge, Widget content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AfSpacing.s12),
      child: EqAccordionSection(
        label: label,
        isOpen: _openSection == index,
        badgeCount: badge,
        onTap: () => setState(() {
          _openSection = _openSection == index ? null : index;
        }),
        child: content,
      ),
    );
  }

  // ── 18-Band EQ ──────────────────────────────────────────────────────────

  Widget _buildEqContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
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
                  accentColor: ref.watch(
                    currentSpectralProvider.select((s) => s.primary),
                  ),
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
                      'Save preset',
                      style: AfTypography.bodySmall.copyWith(
                        color: ref.watch(
                          currentSpectralProvider.select((s) => s.primary),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AfSpacing.s8),
                  TextButton.icon(
                    onPressed: _saveCurrentAsPreset,
                    icon: const Icon(LucideIcons.save, size: 16),
                    label: Text(
                      'Save preset',
                      style: AfTypography.bodySmall.copyWith(
                        color: ref.watch(
                          currentSpectralProvider.select((s) => s.primary),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Presets ─────────────────────────────────────────────────────────────

  Widget _buildPresetChips() {
    final allPresets = <String, EqPreset>{...kBuiltInPresets, ..._userPresets};
    final spectral = ref.watch(
      currentSpectralProvider.select(
        (s) => (primary: s.primary, secondary: s.secondary),
      ),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: allPresets.entries.map((entry) {
          final isActive = _activePreset == entry.key;
          final isUserPreset = _userPresets.containsKey(entry.key);
          return Padding(
            padding: const EdgeInsets.only(right: AfSpacing.s8),
            child: GestureDetector(
              onLongPress: isUserPreset
                  ? () => _showDeletePresetDialog(entry.key)
                  : null,
              child: ChoiceChip(
                label: Text(entry.key),
                selected: isActive,
                onSelected: (_) => _applyPreset(entry.key, entry.value),
                selectedColor: spectral.secondary.withValues(alpha: 0.3),
                backgroundColor: AfColors.surfaceBase,
                labelStyle: AfTypography.bodySmall.copyWith(
                  color: isActive ? spectral.primary : AfColors.textSecondary,
                ),
                side: isActive
                    ? BorderSide(color: spectral.primary, width: 1.5)
                    : const BorderSide(color: AfColors.surfaceHigh),
              ),
            ),
          );
        }).toList(),
      ),
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
