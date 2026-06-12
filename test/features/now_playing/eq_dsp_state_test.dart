import 'package:flutter_test/flutter_test.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import 'package:aetherfin/features/now_playing/eq_band_logic.dart';

void main() {
  group('EqDspState (DSP-only, no EQ)', () {
    late EqDspState state;

    setUp(() {
      state = EqDspState();
    });

    // ── DSP fields preserved ──────────────────────────────────────────────
    group('DSP fields preserved', () {
      test('has masterEnabled', () {
        expect(state.masterEnabled, true);
      });

      test('has tone fields (bass/treble)', () {
        expect(state.bass, 0);
        expect(state.treble, 0);
      });

      test('has dynamics fields', () {
        expect(state.loudnorm, false);
        expect(state.compressor, false);
        expect(state.compThreshold, 0.1);
        expect(state.compRatio, 4.0);
        expect(state.compAttack, 20.0);
        expect(state.compRelease, 250.0);
      });

      test('has gate fields', () {
        expect(state.gate, false);
        expect(state.gateThreshold, 0.01);
        expect(state.gateRatio, 2.0);
        expect(state.gateAttack, 20.0);
        expect(state.gateRelease, 250.0);
      });

      test('has deesser fields', () {
        expect(state.deesser, false);
        expect(state.deesserIntensity, 0);
        expect(state.deesserMix, 0.5);
        expect(state.deesserFreq, 0.5);
      });

      test('has pitch/tempo fields', () {
        expect(state.rubberbandEnabled, false);
        expect(state.pitch, 1.0);
        expect(state.tempo, 1.0);
      });

      test('has spatial fields', () {
        expect(state.crossfeed, false);
        expect(state.crossfeedStrength, 0.2);
        expect(state.stereoWiden, false);
        expect(state.stereoWidenDelay, 20.0);
      });

      test('has creative fields', () {
        expect(state.exciter, false);
        expect(state.exciterAmount, 1.0);
        expect(state.crystalizer, false);
        expect(state.crystalizerIntensity, 2.0);
        expect(state.virtualBass, false);
        expect(state.virtualBassCutoff, 250.0);
      });

      test('has echo fields', () {
        expect(state.echoEnabled, false);
        expect(state.echoInGain, 0.6);
        expect(state.echoOutGain, 0.3);
        expect(state.echoDelays, '500');
        expect(state.echoDecays, '0.5');
      });

      test('has modulation fields', () {
        expect(state.phaser, false);
        expect(state.flanger, false);
        expect(state.chorus, false);
        expect(state.tremolo, false);
        expect(state.vibrato, false);
      });

      test('has crusher fields', () {
        expect(state.crusher, false);
        expect(state.crusherBits, 8.0);
        expect(state.crusherMix, 0.5);
        expect(state.crusherSamples, 1.0);
      });
    });

    // ── toAudioEffects (no EQ) ────────────────────────────────────────────
    group('toAudioEffects', () {
      test('does not include superequalizer when current has none', () {
        final fx = state.toAudioEffects(const AudioEffects());
        expect(fx.superequalizer.enabled, false);
        expect(fx.superequalizer.params, isEmpty);
      });

      test('does not include custom filters when current has none', () {
        final fx = state.toAudioEffects(const AudioEffects());
        expect(fx.custom, isEmpty);
      });

      test('preserves existing superequalizer settings from current', () {
        const current = AudioEffects(
          superequalizer: SuperequalizerSettings(
            enabled: true,
            params: {'1b': 3.0, '5b': -1.5},
          ),
        );
        final fx = state.toAudioEffects(current);
        expect(fx.superequalizer.enabled, isTrue);
        expect(fx.superequalizer.params, {'1b': 3.0, '5b': -1.5});
      });

      test('preserves existing custom filters from current', () {
        const current = AudioEffects(
          custom: ['lavfi-equalizer=f=1000:t=q:w=1.0:g=3.0'],
        );
        final fx = state.toAudioEffects(current);
        expect(fx.custom, ['lavfi-equalizer=f=1000:t=q:w=1.0:g=3.0']);
      });

      test('preserves both superequalizer and custom from current', () {
        const current = AudioEffects(
          superequalizer: SuperequalizerSettings(
            enabled: true,
            params: {'1b': 2.0},
          ),
          custom: ['filter1'],
        );
        final fx = state.toAudioEffects(current);
        expect(fx.superequalizer.enabled, isTrue);
        expect(fx.superequalizer.params, {'1b': 2.0});
        expect(fx.custom, ['filter1']);
      });

      test('includes bass/treble', () {
        state.bass = 3.0;
        state.treble = -2.0;
        final fx = state.toAudioEffects(const AudioEffects());
        expect(fx.bass.enabled, true);
        expect(fx.bass.g, 3.0);
        expect(fx.treble.enabled, true);
        expect(fx.treble.g, -2.0);
      });

      test('includes dynamics', () {
        state.loudnorm = true;
        state.compressor = true;
        final fx = state.toAudioEffects(const AudioEffects());
        expect(fx.loudnorm.enabled, true);
        expect(fx.acompressor.enabled, true);
      });

      test('includes modulation effects', () {
        state.phaser = true;
        state.flanger = true;
        state.chorus = true;
        state.tremolo = true;
        state.vibrato = true;
        final fx = state.toAudioEffects(const AudioEffects());
        expect(fx.aphaser.enabled, true);
        expect(fx.flanger.enabled, true);
        expect(fx.chorus.enabled, true);
        expect(fx.tremolo.enabled, true);
        expect(fx.vibrato.enabled, true);
      });
    });

    // ── loadFromAudioEffects (no EQ) ──────────────────────────────────────
    group('loadFromAudioEffects', () {
      test('loads DSP fields from AudioEffects', () {
        const fx = AudioEffects(
          bass: BassSettings(enabled: true, g: 5.0),
          treble: TrebleSettings(enabled: true, g: -3.0),
          loudnorm: LoudnormSettings(enabled: true),
          acompressor: AcompressorSettings(enabled: true, threshold: 0.2),
          rubberband: RubberbandSettings(enabled: true, pitch: 1.2, tempo: 0.9),
        );
        state.loadFromAudioEffects(fx);
        expect(state.bass, 5.0);
        expect(state.treble, -3.0);
        expect(state.loudnorm, true);
        expect(state.compressor, true);
        expect(state.compThreshold, 0.2);
        expect(state.rubberbandEnabled, true);
        expect(state.pitch, 1.2);
        expect(state.tempo, 0.9);
      });

      test('ignores superequalizer settings', () {
        const fx = AudioEffects(
          superequalizer: SuperequalizerSettings(
            enabled: true,
            params: {'1b': 2.0, '2b': 1.5},
          ),
        );
        state.loadFromAudioEffects(fx);
        // Verify the output still has no superequalizer (DSP state doesn't own it)
        final out = state.toAudioEffects(const AudioEffects());
        expect(out.superequalizer.enabled, false);
        expect(out.superequalizer.params, isEmpty);
      });

      test('ignores custom filters', () {
        const fx = AudioEffects(
          custom: ['lavfi-equalizer=f=1000:t=q:w=1.0:g=3.0'],
        );
        state.loadFromAudioEffects(fx);
        // Verify the output still has no custom filters (DSP state doesn't own them)
        final out = state.toAudioEffects(const AudioEffects());
        expect(out.custom, isEmpty);
      });
    });

    // ── setField (no EQ cases) ────────────────────────────────────────────
    group('setField', () {
      test('sets DSP fields', () {
        state.setField('bass', 5.0);
        state.setField('treble', -3.0);
        state.setField('loudnorm', true);
        state.setField('compressor', true);
        state.setField('echoEnabled', true);
        state.setField('phaser', true);
        state.setField('crusher', true);

        expect(state.bass, 5.0);
        expect(state.treble, -3.0);
        expect(state.loudnorm, true);
        expect(state.compressor, true);
        expect(state.echoEnabled, true);
        expect(state.phaser, true);
        expect(state.crusher, true);
      });
    });

    // ── Typed setters (m1) ────────────────────────────────────────────────
    group('typed setters (m1)', () {
      test('setBass sets bass value', () {
        state.setBass(5.0);
        expect(state.bass, 5.0);
      });

      test('setTreble sets treble value', () {
        state.setTreble(-3.0);
        expect(state.treble, -3.0);
      });

      test('setLoudnorm sets loudnorm value', () {
        state.setLoudnorm(true);
        expect(state.loudnorm, true);
      });

      test('setCompressor sets compressor value', () {
        state.setCompressor(true);
        expect(state.compressor, true);
      });

      test('setCompThreshold sets compThreshold value', () {
        state.setCompThreshold(-20.0);
        expect(state.compThreshold, -20.0);
      });

      test('setCompRatio sets compRatio value', () {
        state.setCompRatio(8.0);
        expect(state.compRatio, 8.0);
      });

      test('setCompAttack sets compAttack value', () {
        state.setCompAttack(50.0);
        expect(state.compAttack, 50.0);
      });

      test('setCompRelease sets compRelease value', () {
        state.setCompRelease(500.0);
        expect(state.compRelease, 500.0);
      });

      test('setGate sets gate value', () {
        state.setGate(true);
        expect(state.gate, true);
      });

      test('setGateThreshold sets gateThreshold value', () {
        state.setGateThreshold(-30.0);
        expect(state.gateThreshold, -30.0);
      });

      test('setDeesser sets deesser value', () {
        state.setDeesser(true);
        expect(state.deesser, true);
      });

      test('setDeesserIntensity sets deesserIntensity value', () {
        state.setDeesserIntensity(0.8);
        expect(state.deesserIntensity, 0.8);
      });

      test('setEchoEnabled sets echoEnabled value', () {
        state.setEchoEnabled(true);
        expect(state.echoEnabled, true);
      });

      test('setEchoDelays sets echoDelays value', () {
        state.setEchoDelays('100|200');
        expect(state.echoDelays, '100|200');
      });

      test('setRubberbandEnabled sets rubberbandEnabled value', () {
        state.setRubberbandEnabled(true);
        expect(state.rubberbandEnabled, true);
      });

      test('setPitch sets pitch value', () {
        state.setPitch(1.2);
        expect(state.pitch, 1.2);
      });

      test('setTempo sets tempo value', () {
        state.setTempo(0.9);
        expect(state.tempo, 0.9);
      });

      test('setCrossfeed sets crossfeed value', () {
        state.setCrossfeed(true);
        expect(state.crossfeed, true);
      });

      test('setPhaser sets phaser value', () {
        state.setPhaser(true);
        expect(state.phaser, true);
      });

      test('setFlanger sets flanger value', () {
        state.setFlanger(true);
        expect(state.flanger, true);
      });

      test('setChorus sets chorus value', () {
        state.setChorus(true);
        expect(state.chorus, true);
      });

      test('setChorusDelays sets chorusDelays value', () {
        state.setChorusDelays('30|60');
        expect(state.chorusDelays, '30|60');
      });

      test('setTremolo sets tremolo value', () {
        state.setTremolo(true);
        expect(state.tremolo, true);
      });

      test('setTremoloFreq sets tremoloFreq value', () {
        state.setTremoloFreq(8.0);
        expect(state.tremoloFreq, 8.0);
      });

      test('setVibrato sets vibrato value', () {
        state.setVibrato(true);
        expect(state.vibrato, true);
      });

      test('setExciter sets exciter value', () {
        state.setExciter(true);
        expect(state.exciter, true);
      });

      test('setCrystalizer sets crystalizer value', () {
        state.setCrystalizer(true);
        expect(state.crystalizer, true);
      });

      test('setVirtualBass sets virtualBass value', () {
        state.setVirtualBass(true);
        expect(state.virtualBass, true);
      });

      test('setCrusher sets crusher value', () {
        state.setCrusher(true);
        expect(state.crusher, true);
      });

      test('setCrusherBits sets crusherBits value', () {
        state.setCrusherBits(12.0);
        expect(state.crusherBits, 12.0);
      });
    });

    // ── reset (no EQ) ─────────────────────────────────────────────────────
    group('reset', () {
      test('resets DSP fields to defaults', () {
        state.bass = 5.0;
        state.treble = -3.0;
        state.loudnorm = true;
        state.compressor = true;
        state.phaser = true;
        state.crusher = true;
        state.reset();

        expect(state.bass, 0);
        expect(state.treble, 0);
        expect(state.loudnorm, false);
        expect(state.compressor, false);
        expect(state.phaser, false);
        expect(state.crusher, false);
      });
    });

    // ── Badge counts ─────────────────────────────────────────────────────
    group('badge counts', () {
      test('has dynamicsCount', () {
        state.loudnorm = true;
        state.compressor = true;
        expect(state.dynamicsCount, 2);
      });

      test('has modulationCount', () {
        state.phaser = true;
        state.flanger = true;
        state.chorus = true;
        expect(state.modulationCount, 3);
      });

      test('has creativeCount', () {
        state.exciter = true;
        state.crystalizer = true;
        state.virtualBass = true;
        state.crusher = true;
        expect(state.creativeCount, 4);
      });
    });
  });
}
