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

import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import 'eq_band_painter.dart';
import 'eq_dsp_widgets.dart';
import 'eq_preset.dart';

/// Mutable DSP state holding all equalizer and effects parameters.
///
/// Centralises the ~40 fields that were previously scattered across
/// [_EqDspScreenState] so the screen becomes a thin UI orchestrator.
class EqDspState {
  EqDspState()
    : masterEnabled = true,
      bass = 0,
      treble = 0,
      loudnorm = false,
      compressor = false,
      compThreshold = 0.1,
      compRatio = 4.0,
      compAttack = 20.0,
      compRelease = 250.0,
      eqEnabled = false,
      eqBands = {for (final k in kEqBands.keys) k: 1.0},
      rubberbandEnabled = false,
      pitch = 1.0,
      tempo = 1.0,
      crossfeed = false,
      crossfeedStrength = 0.2,
      stereoWiden = false,
      stereoWidenDelay = 20.0,
      exciter = false,
      exciterAmount = 1.0,
      crystalizer = false,
      crystalizerIntensity = 2.0,
      virtualBass = false,
      virtualBassCutoff = 250.0,
      gate = false,
      gateThreshold = 0.01,
      gateRatio = 2.0,
      gateAttack = 20.0,
      gateRelease = 250.0,
      deesser = false,
      deesserIntensity = 0,
      deesserMix = 0.5,
      deesserFreq = 0.5,
      echoEnabled = false,
      echoInGain = 0.6,
      echoOutGain = 0.3,
      echoDelays = '500',
      echoDecays = '0.5',
      phaser = false,
      phaserInGain = 0.4,
      phaserOutGain = 0.74,
      phaserDelay = 3.0,
      phaserDecay = 0.4,
      phaserSpeed = 0.5,
      flanger = false,
      flangerDelay = 0.0,
      flangerDepth = 2.0,
      flangerRegen = 0.0,
      flangerWidth = 71.0,
      flangerSpeed = 0.5,
      chorus = false,
      chorusInGain = 0.4,
      chorusOutGain = 0.4,
      chorusDelays = '40|60',
      chorusDecays = '0.4|0.32',
      chorusSpeeds = '0.25|0.4',
      chorusDepths = '2|3',
      tremolo = false,
      tremoloFreq = 5.0,
      tremoloDepth = 0.5,
      vibrato = false,
      vibratoFreq = 5.0,
      vibratoDepth = 0.5,
      crusher = false,
      crusherBits = 8.0,
      crusherMix = 0.5,
      crusherSamples = 1.0;

  // ── Master ──
  bool masterEnabled;

  // ── Tone ──
  double bass;
  double treble;

  // ── Dynamics ──
  bool loudnorm;
  bool compressor;
  double compThreshold;
  double compRatio;
  double compAttack;
  double compRelease;

  // ── Gate ──
  bool gate;
  double gateThreshold;
  double gateRatio;
  double gateAttack;
  double gateRelease;

  // ── De-esser ──
  bool deesser;
  double deesserIntensity;
  double deesserMix;
  double deesserFreq;

  // ── 18-band EQ ──
  bool eqEnabled;
  final Map<String, double> eqBands;

  // ── Pitch & tempo ──
  bool rubberbandEnabled;
  double pitch;
  double tempo;

  // ── Spatial ──
  bool crossfeed;
  double crossfeedStrength;
  bool stereoWiden;
  double stereoWidenDelay;

  // ── Creative ──
  bool exciter;
  double exciterAmount;
  bool crystalizer;
  double crystalizerIntensity;
  bool virtualBass;
  double virtualBassCutoff;

  // ── Echo / Delay ──
  bool echoEnabled;
  double echoInGain;
  double echoOutGain;
  String echoDelays;
  String echoDecays;

  // ── Modulation ──
  bool phaser;
  double phaserInGain;
  double phaserOutGain;
  double phaserDelay;
  double phaserDecay;
  double phaserSpeed;

  bool flanger;
  double flangerDelay;
  double flangerDepth;
  double flangerRegen;
  double flangerWidth;
  double flangerSpeed;

  bool chorus;
  double chorusInGain;
  double chorusOutGain;
  String chorusDelays;
  String chorusDecays;
  String chorusSpeeds;
  String chorusDepths;

  bool tremolo;
  double tremoloFreq;
  double tremoloDepth;

  bool vibrato;
  double vibratoFreq;
  double vibratoDepth;

  // ── Bit-crusher ──
  bool crusher;
  double crusherBits;
  double crusherMix;
  double crusherSamples;

  // ── Field dispatch ────────────────────────────────────────────────────────

  /// Updates a single effect field by name without triggering a rebuild.
  ///
  /// The screen's own [setState] handles the parent rebuild; section
  /// widgets use their local setState for immediate slider feedback.
  void setField(String field, dynamic value) {
    switch (field) {
      case 'loudnorm':
        loudnorm = value as bool;
      case 'compressor':
        compressor = value as bool;
      case 'compThreshold':
        compThreshold = value as double;
      case 'compRatio':
        compRatio = value as double;
      case 'compAttack':
        compAttack = value as double;
      case 'compRelease':
        compRelease = value as double;
      case 'gate':
        gate = value as bool;
      case 'gateThreshold':
        gateThreshold = value as double;
      case 'gateRatio':
        gateRatio = value as double;
      case 'gateAttack':
        gateAttack = value as double;
      case 'gateRelease':
        gateRelease = value as double;
      case 'deesser':
        deesser = value as bool;
      case 'deesserIntensity':
        deesserIntensity = value as double;
      case 'deesserMix':
        deesserMix = value as double;
      case 'deesserFreq':
        deesserFreq = value as double;
      case 'echoEnabled':
        echoEnabled = value as bool;
      case 'echoInGain':
        echoInGain = value as double;
      case 'echoOutGain':
        echoOutGain = value as double;
      case 'echoDelays':
        echoDelays = value as String;
      case 'echoDecays':
        echoDecays = value as String;
      case 'rubberbandEnabled':
        rubberbandEnabled = value as bool;
      case 'pitch':
        pitch = value as double;
      case 'tempo':
        tempo = value as double;
      case 'crossfeed':
        crossfeed = value as bool;
      case 'crossfeedStrength':
        crossfeedStrength = value as double;
      case 'stereoWiden':
        stereoWiden = value as bool;
      case 'stereoWidenDelay':
        stereoWidenDelay = value as double;
      case 'phaser':
        phaser = value as bool;
      case 'phaserInGain':
        phaserInGain = value as double;
      case 'phaserOutGain':
        phaserOutGain = value as double;
      case 'phaserDelay':
        phaserDelay = value as double;
      case 'phaserDecay':
        phaserDecay = value as double;
      case 'phaserSpeed':
        phaserSpeed = value as double;
      case 'flanger':
        flanger = value as bool;
      case 'flangerDelay':
        flangerDelay = value as double;
      case 'flangerDepth':
        flangerDepth = value as double;
      case 'flangerRegen':
        flangerRegen = value as double;
      case 'flangerWidth':
        flangerWidth = value as double;
      case 'flangerSpeed':
        flangerSpeed = value as double;
      case 'chorus':
        chorus = value as bool;
      case 'chorusInGain':
        chorusInGain = value as double;
      case 'chorusOutGain':
        chorusOutGain = value as double;
      case 'chorusDelays':
        chorusDelays = value as String;
      case 'chorusDecays':
        chorusDecays = value as String;
      case 'chorusSpeeds':
        chorusSpeeds = value as String;
      case 'chorusDepths':
        chorusDepths = value as String;
      case 'tremolo':
        tremolo = value as bool;
      case 'tremoloFreq':
        tremoloFreq = value as double;
      case 'tremoloDepth':
        tremoloDepth = value as double;
      case 'vibrato':
        vibrato = value as bool;
      case 'vibratoFreq':
        vibratoFreq = value as double;
      case 'vibratoDepth':
        vibratoDepth = value as double;
      case 'exciter':
        exciter = value as bool;
      case 'exciterAmount':
        exciterAmount = value as double;
      case 'crystalizer':
        crystalizer = value as bool;
      case 'crystalizerIntensity':
        crystalizerIntensity = value as double;
      case 'virtualBass':
        virtualBass = value as bool;
      case 'virtualBassCutoff':
        virtualBassCutoff = value as double;
      case 'crusher':
        crusher = value as bool;
      case 'crusherBits':
        crusherBits = value as double;
      case 'crusherMix':
        crusherMix = value as double;
      case 'crusherSamples':
        crusherSamples = value as double;
    }
  }

  // ── Reset ─────────────────────────────────────────────────────────────────

  /// Reset all DSP fields to their defaults.
  void reset() {
    masterEnabled = true;
    bass = 0;
    treble = 0;
    loudnorm = false;
    compressor = false;
    compThreshold = 0.1;
    compRatio = 4.0;
    compAttack = 20.0;
    compRelease = 250.0;
    eqEnabled = false;
    for (final k in eqBands.keys) {
      eqBands[k] = 1.0;
    }
    rubberbandEnabled = false;
    pitch = 1.0;
    tempo = 1.0;
    crossfeed = false;
    crossfeedStrength = 0.2;
    stereoWiden = false;
    stereoWidenDelay = 20.0;
    exciter = false;
    exciterAmount = 1.0;
    crystalizer = false;
    crystalizerIntensity = 2.0;
    virtualBass = false;
    virtualBassCutoff = 250.0;
    gate = false;
    gateThreshold = 0.01;
    gateRatio = 2.0;
    gateAttack = 20.0;
    gateRelease = 250.0;
    deesser = false;
    deesserIntensity = 0.0;
    deesserMix = 0.5;
    deesserFreq = 0.5;
    echoEnabled = false;
    echoInGain = 0.6;
    echoOutGain = 0.3;
    echoDelays = '500';
    echoDecays = '0.5';
    phaser = false;
    phaserInGain = 0.4;
    phaserOutGain = 0.74;
    phaserDelay = 3.0;
    phaserDecay = 0.4;
    phaserSpeed = 0.5;
    flanger = false;
    flangerDelay = 0.0;
    flangerDepth = 2.0;
    flangerRegen = 0.0;
    flangerWidth = 71.0;
    flangerSpeed = 0.5;
    chorus = false;
    chorusInGain = 0.4;
    chorusOutGain = 0.4;
    chorusDelays = '40|60';
    chorusDecays = '0.4|0.32';
    chorusSpeeds = '0.25|0.4';
    chorusDepths = '2|3';
    tremolo = false;
    tremoloFreq = 5.0;
    tremoloDepth = 0.5;
    vibrato = false;
    vibratoFreq = 5.0;
    vibratoDepth = 0.5;
    crusher = false;
    crusherBits = 8.0;
    crusherMix = 0.5;
    crusherSamples = 1.0;
  }

  // ── AudioEffects conversion ───────────────────────────────────────────────

  /// Build [AudioEffects] from the current state values.
  AudioEffects toAudioEffects() {
    return AudioEffects(
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
        params: buildEqParams(),
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
      tremolo: TremoloSettings(
        enabled: tremolo,
        f: tremoloFreq,
        d: tremoloDepth,
      ),
      vibrato: VibratoSettings(
        enabled: vibrato,
        f: vibratoFreq,
        d: vibratoDepth,
      ),
      acrusher: AcrusherSettings(
        enabled: crusher,
        bits: crusherBits,
        mix: crusherMix,
        samples: crusherSamples,
      ),
    );
  }

  /// Populate this state from persisted [AudioEffects].
  void loadFromAudioEffects(AudioEffects fx) {
    bass = fx.bass.g;
    treble = fx.treble.g;
    loudnorm = fx.loudnorm.enabled;
    compressor = fx.acompressor.enabled;
    compThreshold = fx.acompressor.threshold;
    compRatio = fx.acompressor.ratio;
    compAttack = fx.acompressor.attack;
    compRelease = fx.acompressor.release;
    eqEnabled = fx.superequalizer.enabled;
    for (final entry in fx.superequalizer.params.entries) {
      if (eqBands.containsKey(entry.key)) {
        eqBands[entry.key] = entry.value;
      }
    }
    rubberbandEnabled = fx.rubberband.enabled;
    pitch = fx.rubberband.pitch;
    tempo = fx.rubberband.tempo;
    crossfeed = fx.crossfeed.enabled;
    crossfeedStrength = fx.crossfeed.strength;
    stereoWiden = fx.stereowiden.enabled;
    stereoWidenDelay = fx.stereowiden.delay;
    exciter = fx.aexciter.enabled;
    exciterAmount = fx.aexciter.amount;
    crystalizer = fx.crystalizer.enabled;
    crystalizerIntensity = fx.crystalizer.i.clamp(-10.0, 10.0);
    virtualBass = fx.virtualbass.enabled;
    virtualBassCutoff = fx.virtualbass.cutoff;
    gate = fx.agate.enabled;
    gateThreshold = fx.agate.threshold;
    gateRatio = fx.agate.ratio;
    gateAttack = fx.agate.attack;
    gateRelease = fx.agate.release;
    deesser = fx.deesser.enabled;
    deesserIntensity = fx.deesser.i.clamp(0.0, 1.0);
    deesserMix = fx.deesser.m.clamp(0.0, 1.0);
    deesserFreq = fx.deesser.f.clamp(0.0, 1.0);
    echoEnabled = fx.aecho.enabled;
    echoInGain = fx.aecho.in_gain;
    echoOutGain = fx.aecho.out_gain;
    echoDelays = fx.aecho.delays;
    echoDecays = fx.aecho.decays;
    phaser = fx.aphaser.enabled;
    phaserInGain = fx.aphaser.in_gain;
    phaserOutGain = fx.aphaser.out_gain;
    phaserDelay = fx.aphaser.delay;
    phaserDecay = fx.aphaser.decay;
    phaserSpeed = fx.aphaser.speed;
    flanger = fx.flanger.enabled;
    flangerDelay = fx.flanger.delay;
    flangerDepth = fx.flanger.depth;
    flangerRegen = fx.flanger.regen;
    flangerWidth = fx.flanger.width;
    flangerSpeed = fx.flanger.speed;
    chorus = fx.chorus.enabled;
    chorusInGain = fx.chorus.in_gain;
    chorusOutGain = fx.chorus.out_gain;
    chorusDelays = fx.chorus.delays;
    chorusDecays = fx.chorus.decays;
    chorusSpeeds = fx.chorus.speeds;
    chorusDepths = fx.chorus.depths;
    tremolo = fx.tremolo.enabled;
    tremoloFreq = fx.tremolo.f;
    tremoloDepth = fx.tremolo.d;
    vibrato = fx.vibrato.enabled;
    vibratoFreq = fx.vibrato.f;
    vibratoDepth = fx.vibrato.d;
    crusher = fx.acrusher.enabled;
    crusherBits = fx.acrusher.bits;
    crusherMix = fx.acrusher.mix;
    crusherSamples = fx.acrusher.samples;
  }

  // ── EQ helpers ────────────────────────────────────────────────────────────

  /// Build super-equalizer params, filtering out unity-gain entries.
  Map<String, double> buildEqParams() {
    final params = <String, double>{};
    for (final entry in eqBands.entries) {
      if (entry.value != 1.0) params[entry.key] = entry.value;
    }
    return params;
  }

  // ── Badge counts ──────────────────────────────────────────────────────────

  int get dynamicsCount =>
      (loudnorm ? 1 : 0) +
      (compressor ? 1 : 0) +
      (gate ? 1 : 0) +
      (deesser ? 1 : 0);

  int get modulationCount =>
      (phaser ? 1 : 0) +
      (flanger ? 1 : 0) +
      (chorus ? 1 : 0) +
      (tremolo ? 1 : 0) +
      (vibrato ? 1 : 0);

  int get creativeCount =>
      (exciter ? 1 : 0) +
      (crystalizer ? 1 : 0) +
      (virtualBass ? 1 : 0) +
      (crusher ? 1 : 0);
}

/// Builds the 18-band EQ content widget.
Widget buildEqContent({
  required EqDspState state,
  required WidgetRef ref,
  required VoidCallback onApply,
  required void Function(bool) onEnabledChanged,
  required void Function(int, double) onGainChanged,
  required void Function(String, double) onBandChanged,
  required VoidCallback onResetBands,
  required VoidCallback onSavePreset,
}) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      EqEffectToggle(
        title: 'Enable graphic EQ',
        subtitle: '18-band ISO frequency equalizer',
        value: state.eqEnabled,
        onChanged: onEnabledChanged,
      ),
      EqExpandableContent(
        visible: state.eqEnabled,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 120,
              child: EqBandVisualization(
                labels: kEqBands.values.toList(),
                gains: kEqBands.keys
                    .map((k) => state.eqBands[k] ?? 1.0)
                    .toList(),
                accentColor: ref.watch(
                  currentSpectralProvider.select((s) => s.primary),
                ),
                onGainChanged: onGainChanged,
                onGainChangeEnd: onApply,
              ),
            ),
            const SizedBox(height: AfSpacing.s8),
            ...kEqBands.entries.map((entry) {
              final gain = state.eqBands[entry.key] ?? 1.0;
              return EqBandSlider(
                bandKey: entry.key,
                freq: entry.value,
                gain: gain,
                onChanged: (v) => onBandChanged(entry.key, v),
                onChangeEnd: onApply,
              );
            }),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onResetBands,
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
                  onPressed: onSavePreset,
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
