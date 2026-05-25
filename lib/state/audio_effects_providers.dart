import 'dart:async';

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
import 'package:shared_preferences/shared_preferences.dart';

import '../core/audio/player_settings_store.dart';
import '../utils/log.dart';
import 'player_providers.dart';

const _kDebounceMs = 150;

// ── State ───────────────────────────────────────────────────────────────────

class AudioEffectsState {
  const AudioEffectsState({
    required this.masterEnabled,
    required this.bass,
    required this.treble,
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
    required this.eqEnabled,
    required this.eqBands,
    required this.rubberbandEnabled,
    required this.pitch,
    required this.tempo,
    required this.crossfeed,
    required this.crossfeedStrength,
    required this.stereoWiden,
    required this.stereoWidenDelay,
    required this.exciter,
    required this.exciterAmount,
    required this.crystalizer,
    required this.crystalizerIntensity,
    required this.virtualBass,
    required this.virtualBassCutoff,
    required this.echoEnabled,
    required this.echoInGain,
    required this.echoOutGain,
    required this.echoDelays,
    required this.echoDecays,
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
    required this.crusher,
    required this.crusherBits,
    required this.crusherMix,
    required this.crusherSamples,
    required this.activePreset,
  });

  factory AudioEffectsState.initial() => const AudioEffectsState(
    masterEnabled: true,
    bass: 0,
    treble: 0,
    loudnorm: false,
    compressor: false,
    compThreshold: 0.1,
    compRatio: 4,
    compAttack: 20,
    compRelease: 250,
    gate: false,
    gateThreshold: 0.01,
    gateRatio: 2,
    gateAttack: 20,
    gateRelease: 250,
    deesser: false,
    deesserIntensity: 0,
    deesserMix: 0.5,
    deesserFreq: 0.5,
    eqEnabled: false,
    eqBands: {},
    rubberbandEnabled: false,
    pitch: 1,
    tempo: 1,
    crossfeed: false,
    crossfeedStrength: 0.2,
    stereoWiden: false,
    stereoWidenDelay: 20,
    exciter: false,
    exciterAmount: 1,
    crystalizer: false,
    crystalizerIntensity: 2,
    virtualBass: false,
    virtualBassCutoff: 250,
    echoEnabled: false,
    echoInGain: 0.6,
    echoOutGain: 0.3,
    echoDelays: '500',
    echoDecays: '0.5',
    phaser: false,
    phaserInGain: 0.4,
    phaserOutGain: 0.74,
    phaserDelay: 3,
    phaserDecay: 0.4,
    phaserSpeed: 0.5,
    flanger: false,
    flangerDelay: 0,
    flangerDepth: 2,
    flangerRegen: 0,
    flangerWidth: 71,
    flangerSpeed: 0.5,
    chorus: false,
    chorusInGain: 0.4,
    chorusOutGain: 0.4,
    chorusDelays: '40|60',
    chorusDecays: '0.4|0.32',
    chorusSpeeds: '0.25|0.4',
    chorusDepths: '2|3',
    tremolo: false,
    tremoloFreq: 5,
    tremoloDepth: 0.5,
    vibrato: false,
    vibratoFreq: 5,
    vibratoDepth: 0.5,
    crusher: false,
    crusherBits: 8,
    crusherMix: 0.5,
    crusherSamples: 1,
    activePreset: null,
  );

  final bool masterEnabled;
  final double bass;
  final double treble;
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
  final bool eqEnabled;
  final Map<String, double> eqBands;
  final bool rubberbandEnabled;
  final double pitch;
  final double tempo;
  final bool crossfeed;
  final double crossfeedStrength;
  final bool stereoWiden;
  final double stereoWidenDelay;
  final bool exciter;
  final double exciterAmount;
  final bool crystalizer;
  final double crystalizerIntensity;
  final bool virtualBass;
  final double virtualBassCutoff;
  final bool echoEnabled;
  final double echoInGain;
  final double echoOutGain;
  final String echoDelays;
  final String echoDecays;
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
  final bool crusher;
  final double crusherBits;
  final double crusherMix;
  final double crusherSamples;
  final String? activePreset;

  bool get anyActive =>
      bass != 0 ||
      treble != 0 ||
      loudnorm ||
      compressor ||
      gate ||
      deesser ||
      eqEnabled ||
      rubberbandEnabled ||
      crossfeed ||
      stereoWiden ||
      exciter ||
      crystalizer ||
      virtualBass ||
      echoEnabled ||
      phaser ||
      flanger ||
      chorus ||
      tremolo ||
      vibrato ||
      crusher;

  AudioEffects buildEffects() => AudioEffects(
    bass: BassSettings(enabled: bass != 0, g: bass),
    treble: TrebleSettings(enabled: treble != 0, g: treble),
    loudnorm: LoudnormSettings(enabled: loudnorm),
    acompressor: AcompressorSettings(
      enabled: compressor,
      threshold: compThreshold,
      ratio: compRatio,
      attack: compAttack,
      release: compRelease,
    ),
    superequalizer: SuperequalizerSettings(
      enabled: eqEnabled,
      params: _buildEqParams(),
    ),
    rubberband: RubberbandSettings(
      enabled: rubberbandEnabled,
      pitch: pitch,
      tempo: tempo,
    ),
    crossfeed: CrossfeedSettings(
      enabled: crossfeed,
      strength: crossfeedStrength,
    ),
    stereowiden: StereowidenSettings(
      enabled: stereoWiden,
      delay: stereoWidenDelay,
    ),
    aexciter: AexciterSettings(enabled: exciter, amount: exciterAmount),
    crystalizer: CrystalizerSettings(
      enabled: crystalizer,
      i: crystalizerIntensity,
    ),
    virtualbass: VirtualbassSettings(
      enabled: virtualBass,
      cutoff: virtualBassCutoff,
    ),
    agate: AgateSettings(
      enabled: gate,
      threshold: gateThreshold,
      ratio: gateRatio,
      attack: gateAttack,
      release: gateRelease,
    ),
    deesser: DeesserSettings(
      enabled: deesser,
      i: deesserIntensity,
      m: deesserMix,
      f: deesserFreq,
    ),
    aecho: AechoSettings(
      enabled: echoEnabled,
      in_gain: echoInGain,
      out_gain: echoOutGain,
      delays: echoDelays,
      decays: echoDecays,
    ),
    aphaser: AphaserSettings(
      enabled: phaser,
      in_gain: phaserInGain,
      out_gain: phaserOutGain,
      delay: phaserDelay,
      decay: phaserDecay,
      speed: phaserSpeed,
    ),
    flanger: FlangerSettings(
      enabled: flanger,
      delay: flangerDelay,
      depth: flangerDepth,
      regen: flangerRegen,
      width: flangerWidth,
      speed: flangerSpeed,
    ),
    chorus: ChorusSettings(
      enabled: chorus,
      in_gain: chorusInGain,
      out_gain: chorusOutGain,
      delays: chorusDelays,
      decays: chorusDecays,
      speeds: chorusSpeeds,
      depths: chorusDepths,
    ),
    tremolo: TremoloSettings(enabled: tremolo, f: tremoloFreq, d: tremoloDepth),
    vibrato: VibratoSettings(enabled: vibrato, f: vibratoFreq, d: vibratoDepth),
    acrusher: AcrusherSettings(
      enabled: crusher,
      bits: crusherBits,
      mix: crusherMix,
      samples: crusherSamples,
    ),
  );

  Map<String, double> _buildEqParams() {
    final params = <String, double>{};
    for (final entry in eqBands.entries) {
      if (entry.value != 1.0) params[entry.key] = entry.value;
    }
    return params;
  }
}

// ── Notifier ────────────────────────────────────────────────────────────────

class AudioEffectsNotifier extends StateNotifier<AudioEffectsState> {
  AudioEffectsNotifier(this._ref) : super(AudioEffectsState.initial()) {
    _init();
  }

  final Ref _ref;
  Timer? _debounce;
  bool _loading = false;

  Future<void> _init() async {
    _loading = true;
    try {
      final svc = _ref.read(playerServiceProvider);
      final fx = svc.audioEffects;
      final p = await SharedPreferences.getInstance();
      final master =
          p.getBool(PlayerSettingsStore.kDspMasterEnabled.key) ?? true;
      final preset = p.getString(PlayerSettingsStore.kActivePreset);

      state = AudioEffectsState(
        masterEnabled: master,
        bass: fx.bass.g,
        treble: fx.treble.g,
        loudnorm: fx.loudnorm.enabled,
        compressor: fx.acompressor.enabled,
        compThreshold: fx.acompressor.threshold,
        compRatio: fx.acompressor.ratio,
        compAttack: fx.acompressor.attack,
        compRelease: fx.acompressor.release,
        gate: fx.agate.enabled,
        gateThreshold: fx.agate.threshold,
        gateRatio: fx.agate.ratio,
        gateAttack: fx.agate.attack,
        gateRelease: fx.agate.release,
        deesser: fx.deesser.enabled,
        deesserIntensity: fx.deesser.i.clamp(0, 1),
        deesserMix: fx.deesser.m.clamp(0, 1),
        deesserFreq: fx.deesser.f.clamp(0, 1),
        eqEnabled: fx.superequalizer.enabled,
        eqBands: _initBands(fx.superequalizer.params),
        rubberbandEnabled: fx.rubberband.enabled,
        pitch: fx.rubberband.pitch,
        tempo: fx.rubberband.tempo,
        crossfeed: fx.crossfeed.enabled,
        crossfeedStrength: fx.crossfeed.strength,
        stereoWiden: fx.stereowiden.enabled,
        stereoWidenDelay: fx.stereowiden.delay,
        exciter: fx.aexciter.enabled,
        exciterAmount: fx.aexciter.amount,
        crystalizer: fx.crystalizer.enabled,
        crystalizerIntensity: fx.crystalizer.i.clamp(-10, 10),
        virtualBass: fx.virtualbass.enabled,
        virtualBassCutoff: fx.virtualbass.cutoff,
        echoEnabled: fx.aecho.enabled,
        echoInGain: fx.aecho.in_gain,
        echoOutGain: fx.aecho.out_gain,
        echoDelays: fx.aecho.delays,
        echoDecays: fx.aecho.decays,
        phaser: fx.aphaser.enabled,
        phaserInGain: fx.aphaser.in_gain,
        phaserOutGain: fx.aphaser.out_gain,
        phaserDelay: fx.aphaser.delay,
        phaserDecay: fx.aphaser.decay,
        phaserSpeed: fx.aphaser.speed,
        flanger: fx.flanger.enabled,
        flangerDelay: fx.flanger.delay,
        flangerDepth: fx.flanger.depth,
        flangerRegen: fx.flanger.regen,
        flangerWidth: fx.flanger.width,
        flangerSpeed: fx.flanger.speed,
        chorus: fx.chorus.enabled,
        chorusInGain: fx.chorus.in_gain,
        chorusOutGain: fx.chorus.out_gain,
        chorusDelays: fx.chorus.delays ?? '40|60',
        chorusDecays: fx.chorus.decays ?? '0.4|0.32',
        chorusSpeeds: fx.chorus.speeds ?? '0.25|0.4',
        chorusDepths: fx.chorus.depths ?? '2|3',
        tremolo: fx.tremolo.enabled,
        tremoloFreq: fx.tremolo.f,
        tremoloDepth: fx.tremolo.d,
        vibrato: fx.vibrato.enabled,
        vibratoFreq: fx.vibrato.f,
        vibratoDepth: fx.vibrato.d,
        crusher: fx.acrusher.enabled,
        crusherBits: fx.acrusher.bits,
        crusherMix: fx.acrusher.mix,
        crusherSamples: fx.acrusher.samples,
        activePreset: preset,
      );
    } catch (e, stack) {
      afLog('error', 'AudioEffectsNotifier._init', error: e, stackTrace: stack);
    } finally {
      _loading = false;
    }
  }

  Map<String, double> _initBands(Map<String, double> params) {
    const keys = [
      '1b',
      '2b',
      '3b',
      '4b',
      '5b',
      '6b',
      '7b',
      '8b',
      '9b',
      '10b',
      '11b',
      '12b',
      '13b',
      '14b',
      '15b',
      '16b',
      '17b',
      '18b',
    ];
    final bands = <String, double>{};
    for (final k in keys) {
      bands[k] = params[k] ?? 1.0;
    }
    return bands;
  }

  // ── Apply ──

  Future<void> _apply() async {
    if (!state.masterEnabled || _loading) return;
    try {
      final svc = _ref.read(playerServiceProvider);
      final effects = state.buildEffects();
      await svc.setAudioEffects(effects);
    } catch (e) {
      afLog('error', 'AudioEffectsNotifier._apply', error: e);
    }
  }

  void _scheduleApply() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: _kDebounceMs), _apply);
  }

  Future<void> applyNow() async {
    _debounce?.cancel();
    await _apply();
  }

  Future<void> persistEffects() async {
    try {
      await PlayerSettingsStore.saveAudioEffects(state.buildEffects());
    } catch (e) {
      afLog('error', 'AudioEffectsNotifier.persistEffects', error: e);
    }
  }

  // ── Mutators ──

  void setMasterEnabled(bool v) {
    state = AudioEffectsState(
      masterEnabled: v,
      bass: state.bass,
      treble: state.treble,
      loudnorm: state.loudnorm,
      compressor: state.compressor,
      compThreshold: state.compThreshold,
      compRatio: state.compRatio,
      compAttack: state.compAttack,
      compRelease: state.compRelease,
      gate: state.gate,
      gateThreshold: state.gateThreshold,
      gateRatio: state.gateRatio,
      gateAttack: state.gateAttack,
      gateRelease: state.gateRelease,
      deesser: state.deesser,
      deesserIntensity: state.deesserIntensity,
      deesserMix: state.deesserMix,
      deesserFreq: state.deesserFreq,
      eqEnabled: state.eqEnabled,
      eqBands: state.eqBands,
      rubberbandEnabled: state.rubberbandEnabled,
      pitch: state.pitch,
      tempo: state.tempo,
      crossfeed: state.crossfeed,
      crossfeedStrength: state.crossfeedStrength,
      stereoWiden: state.stereoWiden,
      stereoWidenDelay: state.stereoWidenDelay,
      exciter: state.exciter,
      exciterAmount: state.exciterAmount,
      crystalizer: state.crystalizer,
      crystalizerIntensity: state.crystalizerIntensity,
      virtualBass: state.virtualBass,
      virtualBassCutoff: state.virtualBassCutoff,
      echoEnabled: state.echoEnabled,
      echoInGain: state.echoInGain,
      echoOutGain: state.echoOutGain,
      echoDelays: state.echoDelays,
      echoDecays: state.echoDecays,
      phaser: state.phaser,
      phaserInGain: state.phaserInGain,
      phaserOutGain: state.phaserOutGain,
      phaserDelay: state.phaserDelay,
      phaserDecay: state.phaserDecay,
      phaserSpeed: state.phaserSpeed,
      flanger: state.flanger,
      flangerDelay: state.flangerDelay,
      flangerDepth: state.flangerDepth,
      flangerRegen: state.flangerRegen,
      flangerWidth: state.flangerWidth,
      flangerSpeed: state.flangerSpeed,
      chorus: state.chorus,
      chorusInGain: state.chorusInGain,
      chorusOutGain: state.chorusOutGain,
      chorusDelays: state.chorusDelays,
      chorusDecays: state.chorusDecays,
      chorusSpeeds: state.chorusSpeeds,
      chorusDepths: state.chorusDepths,
      tremolo: state.tremolo,
      tremoloFreq: state.tremoloFreq,
      tremoloDepth: state.tremoloDepth,
      vibrato: state.vibrato,
      vibratoFreq: state.vibratoFreq,
      vibratoDepth: state.vibratoDepth,
      crusher: state.crusher,
      crusherBits: state.crusherBits,
      crusherMix: state.crusherMix,
      crusherSamples: state.crusherSamples,
      activePreset: state.activePreset,
    );
    if (v) {
      _scheduleApply();
    } else {
      _debounce?.cancel();
      unawaited(
        _ref.read(playerServiceProvider).setAudioEffects(const AudioEffects()),
      );
    }
    unawaited(PlayerSettingsStore.saveDspMasterEnabled(v));
  }

  void setBass(double v) {
    state = state.copyWith(bass: v, activePreset: null);
    _scheduleApply();
  }

  void setTreble(double v) {
    state = state.copyWith(treble: v, activePreset: null);
    _scheduleApply();
  }

  void setLoudnorm(bool v) {
    state = state.copyWith(loudnorm: v);
    _scheduleApply();
  }

  void setCompressor(bool v) => _set('compressor', v);
  void setCompThreshold(double v) => _set('compThreshold', v);
  void setCompRatio(double v) => _set('compRatio', v);
  void setCompAttack(double v) => _set('compAttack', v);
  void setCompRelease(double v) => _set('compRelease', v);

  void setGate(bool v) => _set('gate', v);
  void setGateThreshold(double v) => _set('gateThreshold', v);
  void setGateRatio(double v) => _set('gateRatio', v);
  void setGateAttack(double v) => _set('gateAttack', v);
  void setGateRelease(double v) => _set('gateRelease', v);

  void setDeesser(bool v) => _set('deesser', v);
  void setDeesserIntensity(double v) => _set('deesserIntensity', v);
  void setDeesserMix(double v) => _set('deesserMix', v);
  void setDeesserFreq(double v) => _set('deesserFreq', v);

  void setEqEnabled(bool v) {
    state = state.copyWith(eqEnabled: v);
    _scheduleApply();
  }

  void setEqBand(String key, double value) {
    final bands = Map<String, double>.from(state.eqBands);
    bands[key] = value;
    state = state.copyWith(eqBands: bands, activePreset: null);
    _scheduleApply();
  }

  void flattenEq() {
    final bands = <String, double>{};
    for (final k in state.eqBands.keys) {
      bands[k] = 1.0;
    }
    state = state.copyWith(eqBands: bands, activePreset: null);
    _scheduleApply();
  }

  void applyPreset(
    String name,
    Map<String, double> bands,
    double bass,
    double treble,
  ) {
    final b = <String, double>{};
    for (final k in state.eqBands.keys) {
      b[k] = bands[k] ?? 1.0;
    }
    state = state.copyWith(
      activePreset: name,
      eqEnabled: bands.isNotEmpty,
      eqBands: b,
      bass: bass,
      treble: treble,
    );
    unawaited(PlayerSettingsStore.saveActivePreset(name));
    _scheduleApply();
  }

  void clearActivePreset() {
    state = state.copyWith(activePreset: null);
    unawaited(PlayerSettingsStore.saveActivePreset(null));
  }

  void setRubberbandEnabled(bool v) => _set('rubberbandEnabled', v);
  void setPitch(double v) => _set('pitch', v);
  void setTempo(double v) => _set('tempo', v);
  void setCrossfeed(bool v) => _set('crossfeed', v);
  void setCrossfeedStrength(double v) => _set('crossfeedStrength', v);
  void setStereoWiden(bool v) => _set('stereoWiden', v);
  void setStereoWidenDelay(double v) => _set('stereoWidenDelay', v);
  void setExciter(bool v) => _set('exciter', v);
  void setExciterAmount(double v) => _set('exciterAmount', v);
  void setCrystalizer(bool v) => _set('crystalizer', v);
  void setCrystalizerIntensity(double v) => _set('crystalizerIntensity', v);
  void setVirtualBass(bool v) => _set('virtualBass', v);
  void setVirtualBassCutoff(double v) => _set('virtualBassCutoff', v);
  void setEchoEnabled(bool v) => _set('echoEnabled', v);
  void setEchoInGain(double v) => _set('echoInGain', v);
  void setEchoOutGain(double v) => _set('echoOutGain', v);
  void setEchoDelays(String v) => _setStr('echoDelays', v);
  void setEchoDecays(String v) => _setStr('echoDecays', v);
  void setPhaser(bool v) => _set('phaser', v);
  void setPhaserInGain(double v) => _set('phaserInGain', v);
  void setPhaserOutGain(double v) => _set('phaserOutGain', v);
  void setPhaserDelay(double v) => _set('phaserDelay', v);
  void setPhaserDecay(double v) => _set('phaserDecay', v);
  void setPhaserSpeed(double v) => _set('phaserSpeed', v);
  void setFlanger(bool v) => _set('flanger', v);
  void setFlangerDelay(double v) => _set('flangerDelay', v);
  void setFlangerDepth(double v) => _set('flangerDepth', v);
  void setFlangerRegen(double v) => _set('flangerRegen', v);
  void setFlangerWidth(double v) => _set('flangerWidth', v);
  void setFlangerSpeed(double v) => _set('flangerSpeed', v);
  void setChorus(bool v) => _set('chorus', v);
  void setChorusInGain(double v) => _set('chorusInGain', v);
  void setChorusOutGain(double v) => _set('chorusOutGain', v);
  void setChorusDelays(String v) => _setStr('chorusDelays', v);
  void setChorusDecays(String v) => _setStr('chorusDecays', v);
  void setChorusSpeeds(String v) => _setStr('chorusSpeeds', v);
  void setChorusDepths(String v) => _setStr('chorusDepths', v);
  void setTremolo(bool v) => _set('tremolo', v);
  void setTremoloFreq(double v) => _set('tremoloFreq', v);
  void setTremoloDepth(double v) => _set('tremoloDepth', v);
  void setVibrato(bool v) => _set('vibrato', v);
  void setVibratoFreq(double v) => _set('vibratoFreq', v);
  void setVibratoDepth(double v) => _set('vibratoDepth', v);
  void setCrusher(bool v) => _set('crusher', v);
  void setCrusherBits(double v) => _set('crusherBits', v);
  void setCrusherMix(double v) => _set('crusherMix', v);
  void setCrusherSamples(double v) => _set('crusherSamples', v);

  void resetAll() {
    state = AudioEffectsState.initial().copyWith(masterEnabled: true);
    _debounce?.cancel();
    unawaited(
      _ref.read(playerServiceProvider).setAudioEffects(const AudioEffects()),
    );
    unawaited(PlayerSettingsStore.saveActivePreset(null));
    unawaited(PlayerSettingsStore.saveAudioEffects(const AudioEffects()));
  }

  void _set(String field, dynamic value) {
    state = state.copyWithField(field, value);
    _scheduleApply();
  }

  void _setStr(String field, String value) {
    state = state.copyWithField(field, value);
    _scheduleApply();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

// ── Extension for field-based copyWith ──────────────────────────────────────

extension AudioEffectsStateCopy on AudioEffectsState {
  AudioEffectsState copyWith({
    bool? masterEnabled,
    double? bass,
    double? treble,
    bool? loudnorm,
    bool? compressor,
    double? compThreshold,
    double? compRatio,
    double? compAttack,
    double? compRelease,
    bool? gate,
    double? gateThreshold,
    double? gateRatio,
    double? gateAttack,
    double? gateRelease,
    bool? deesser,
    double? deesserIntensity,
    double? deesserMix,
    double? deesserFreq,
    bool? eqEnabled,
    Map<String, double>? eqBands,
    bool? rubberbandEnabled,
    double? pitch,
    double? tempo,
    bool? crossfeed,
    double? crossfeedStrength,
    bool? stereoWiden,
    double? stereoWidenDelay,
    bool? exciter,
    double? exciterAmount,
    bool? crystalizer,
    double? crystalizerIntensity,
    bool? virtualBass,
    double? virtualBassCutoff,
    bool? echoEnabled,
    double? echoInGain,
    double? echoOutGain,
    String? echoDelays,
    String? echoDecays,
    bool? phaser,
    double? phaserInGain,
    double? phaserOutGain,
    double? phaserDelay,
    double? phaserDecay,
    double? phaserSpeed,
    bool? flanger,
    double? flangerDelay,
    double? flangerDepth,
    double? flangerRegen,
    double? flangerWidth,
    double? flangerSpeed,
    bool? chorus,
    double? chorusInGain,
    double? chorusOutGain,
    String? chorusDelays,
    String? chorusDecays,
    String? chorusSpeeds,
    String? chorusDepths,
    bool? tremolo,
    double? tremoloFreq,
    double? tremoloDepth,
    bool? vibrato,
    double? vibratoFreq,
    double? vibratoDepth,
    bool? crusher,
    double? crusherBits,
    double? crusherMix,
    double? crusherSamples,
    String? activePreset,
  }) => AudioEffectsState(
    masterEnabled: masterEnabled ?? this.masterEnabled,
    bass: bass ?? this.bass,
    treble: treble ?? this.treble,
    loudnorm: loudnorm ?? this.loudnorm,
    compressor: compressor ?? this.compressor,
    compThreshold: compThreshold ?? this.compThreshold,
    compRatio: compRatio ?? this.compRatio,
    compAttack: compAttack ?? this.compAttack,
    compRelease: compRelease ?? this.compRelease,
    gate: gate ?? this.gate,
    gateThreshold: gateThreshold ?? this.gateThreshold,
    gateRatio: gateRatio ?? this.gateRatio,
    gateAttack: gateAttack ?? this.gateAttack,
    gateRelease: gateRelease ?? this.gateRelease,
    deesser: deesser ?? this.deesser,
    deesserIntensity: deesserIntensity ?? this.deesserIntensity,
    deesserMix: deesserMix ?? this.deesserMix,
    deesserFreq: deesserFreq ?? this.deesserFreq,
    eqEnabled: eqEnabled ?? this.eqEnabled,
    eqBands: eqBands ?? this.eqBands,
    rubberbandEnabled: rubberbandEnabled ?? this.rubberbandEnabled,
    pitch: pitch ?? this.pitch,
    tempo: tempo ?? this.tempo,
    crossfeed: crossfeed ?? this.crossfeed,
    crossfeedStrength: crossfeedStrength ?? this.crossfeedStrength,
    stereoWiden: stereoWiden ?? this.stereoWiden,
    stereoWidenDelay: stereoWidenDelay ?? this.stereoWidenDelay,
    exciter: exciter ?? this.exciter,
    exciterAmount: exciterAmount ?? this.exciterAmount,
    crystalizer: crystalizer ?? this.crystalizer,
    crystalizerIntensity: crystalizerIntensity ?? this.crystalizerIntensity,
    virtualBass: virtualBass ?? this.virtualBass,
    virtualBassCutoff: virtualBassCutoff ?? this.virtualBassCutoff,
    echoEnabled: echoEnabled ?? this.echoEnabled,
    echoInGain: echoInGain ?? this.echoInGain,
    echoOutGain: echoOutGain ?? this.echoOutGain,
    echoDelays: echoDelays ?? this.echoDelays,
    echoDecays: echoDecays ?? this.echoDecays,
    phaser: phaser ?? this.phaser,
    phaserInGain: phaserInGain ?? this.phaserInGain,
    phaserOutGain: phaserOutGain ?? this.phaserOutGain,
    phaserDelay: phaserDelay ?? this.phaserDelay,
    phaserDecay: phaserDecay ?? this.phaserDecay,
    phaserSpeed: phaserSpeed ?? this.phaserSpeed,
    flanger: flanger ?? this.flanger,
    flangerDelay: flangerDelay ?? this.flangerDelay,
    flangerDepth: flangerDepth ?? this.flangerDepth,
    flangerRegen: flangerRegen ?? this.flangerRegen,
    flangerWidth: flangerWidth ?? this.flangerWidth,
    flangerSpeed: flangerSpeed ?? this.flangerSpeed,
    chorus: chorus ?? this.chorus,
    chorusInGain: chorusInGain ?? this.chorusInGain,
    chorusOutGain: chorusOutGain ?? this.chorusOutGain,
    chorusDelays: chorusDelays ?? this.chorusDelays,
    chorusDecays: chorusDecays ?? this.chorusDecays,
    chorusSpeeds: chorusSpeeds ?? this.chorusSpeeds,
    chorusDepths: chorusDepths ?? this.chorusDepths,
    tremolo: tremolo ?? this.tremolo,
    tremoloFreq: tremoloFreq ?? this.tremoloFreq,
    tremoloDepth: tremoloDepth ?? this.tremoloDepth,
    vibrato: vibrato ?? this.vibrato,
    vibratoFreq: vibratoFreq ?? this.vibratoFreq,
    vibratoDepth: vibratoDepth ?? this.vibratoDepth,
    crusher: crusher ?? this.crusher,
    crusherBits: crusherBits ?? this.crusherBits,
    crusherMix: crusherMix ?? this.crusherMix,
    crusherSamples: crusherSamples ?? this.crusherSamples,
    activePreset: activePreset ?? this.activePreset,
  );

  AudioEffectsState copyWithField(String field, dynamic value) {
    switch (field) {
      case 'compressor':
        return copyWith(compressor: value as bool);
      case 'compThreshold':
        return copyWith(compThreshold: value as double);
      case 'compRatio':
        return copyWith(compRatio: value as double);
      case 'compAttack':
        return copyWith(compAttack: value as double);
      case 'compRelease':
        return copyWith(compRelease: value as double);
      case 'gate':
        return copyWith(gate: value as bool);
      case 'gateThreshold':
        return copyWith(gateThreshold: value as double);
      case 'gateRatio':
        return copyWith(gateRatio: value as double);
      case 'gateAttack':
        return copyWith(gateAttack: value as double);
      case 'gateRelease':
        return copyWith(gateRelease: value as double);
      case 'deesser':
        return copyWith(deesser: value as bool);
      case 'deesserIntensity':
        return copyWith(deesserIntensity: value as double);
      case 'deesserMix':
        return copyWith(deesserMix: value as double);
      case 'deesserFreq':
        return copyWith(deesserFreq: value as double);
      case 'rubberbandEnabled':
        return copyWith(rubberbandEnabled: value as bool);
      case 'pitch':
        return copyWith(pitch: value as double);
      case 'tempo':
        return copyWith(tempo: value as double);
      case 'crossfeed':
        return copyWith(crossfeed: value as bool);
      case 'crossfeedStrength':
        return copyWith(crossfeedStrength: value as double);
      case 'stereoWiden':
        return copyWith(stereoWiden: value as bool);
      case 'stereoWidenDelay':
        return copyWith(stereoWidenDelay: value as double);
      case 'exciter':
        return copyWith(exciter: value as bool);
      case 'exciterAmount':
        return copyWith(exciterAmount: value as double);
      case 'crystalizer':
        return copyWith(crystalizer: value as bool);
      case 'crystalizerIntensity':
        return copyWith(crystalizerIntensity: value as double);
      case 'virtualBass':
        return copyWith(virtualBass: value as bool);
      case 'virtualBassCutoff':
        return copyWith(virtualBassCutoff: value as double);
      case 'echoEnabled':
        return copyWith(echoEnabled: value as bool);
      case 'echoInGain':
        return copyWith(echoInGain: value as double);
      case 'echoOutGain':
        return copyWith(echoOutGain: value as double);
      case 'echoDelays':
        return copyWith(echoDelays: value as String);
      case 'echoDecays':
        return copyWith(echoDecays: value as String);
      case 'phaser':
        return copyWith(phaser: value as bool);
      case 'phaserInGain':
        return copyWith(phaserInGain: value as double);
      case 'phaserOutGain':
        return copyWith(phaserOutGain: value as double);
      case 'phaserDelay':
        return copyWith(phaserDelay: value as double);
      case 'phaserDecay':
        return copyWith(phaserDecay: value as double);
      case 'phaserSpeed':
        return copyWith(phaserSpeed: value as double);
      case 'flanger':
        return copyWith(flanger: value as bool);
      case 'flangerDelay':
        return copyWith(flangerDelay: value as double);
      case 'flangerDepth':
        return copyWith(flangerDepth: value as double);
      case 'flangerRegen':
        return copyWith(flangerRegen: value as double);
      case 'flangerWidth':
        return copyWith(flangerWidth: value as double);
      case 'flangerSpeed':
        return copyWith(flangerSpeed: value as double);
      case 'chorus':
        return copyWith(chorus: value as bool);
      case 'chorusInGain':
        return copyWith(chorusInGain: value as double);
      case 'chorusOutGain':
        return copyWith(chorusOutGain: value as double);
      case 'chorusDelays':
        return copyWith(chorusDelays: value as String);
      case 'chorusDecays':
        return copyWith(chorusDecays: value as String);
      case 'chorusSpeeds':
        return copyWith(chorusSpeeds: value as String);
      case 'chorusDepths':
        return copyWith(chorusDepths: value as String);
      case 'tremolo':
        return copyWith(tremolo: value as bool);
      case 'tremoloFreq':
        return copyWith(tremoloFreq: value as double);
      case 'tremoloDepth':
        return copyWith(tremoloDepth: value as double);
      case 'vibrato':
        return copyWith(vibrato: value as bool);
      case 'vibratoFreq':
        return copyWith(vibratoFreq: value as double);
      case 'vibratoDepth':
        return copyWith(vibratoDepth: value as double);
      case 'crusher':
        return copyWith(crusher: value as bool);
      case 'crusherBits':
        return copyWith(crusherBits: value as double);
      case 'crusherMix':
        return copyWith(crusherMix: value as double);
      case 'crusherSamples':
        return copyWith(crusherSamples: value as double);
      default:
        return this;
    }
  }
}

// ── Provider ────────────────────────────────────────────────────────────────

final audioEffectsProvider =
    StateNotifierProvider<AudioEffectsNotifier, AudioEffectsState>((ref) {
      return AudioEffectsNotifier(ref);
    });
