import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aetherfin/core/audio/player_settings_store.dart';
import 'package:aetherfin/features/now_playing/graphic_eq_state.dart';
import 'package:aetherfin/features/now_playing/parametric_eq_state.dart';

void main() {
  group('PlayerSettingsStore 3-key persistence', () {
    // ── Graphic EQ persistence ─────────────────────────────────────────────
    group('saveGraphicEq / loadGraphicEq', () {
      test('round-trips default state', () async {
        SharedPreferences.setMockInitialValues({});
        final p = await SharedPreferences.getInstance();
        final state = GraphicEqState();
        await PlayerSettingsStore.saveGraphicEq(state);
        final loaded = PlayerSettingsStore.loadGraphicEq(p);
        expect(loaded.levels.length, 18);
        for (final level in loaded.levels) {
          expect(level, 0.0);
        }
        expect(loaded.enabled, false);
      });

      test('round-trips with non-default levels', () async {
        SharedPreferences.setMockInitialValues({});
        final p = await SharedPreferences.getInstance();
        final state = GraphicEqState(
          levels: List.generate(18, (i) => i * 0.5),
          enabled: true,
        );
        await PlayerSettingsStore.saveGraphicEq(state);
        final loaded = PlayerSettingsStore.loadGraphicEq(p);
        expect(loaded.enabled, true);
        for (var i = 0; i < 18; i++) {
          expect(loaded.levels[i], i * 0.5);
        }
      });

      test('loads defaults when no key exists', () async {
        SharedPreferences.setMockInitialValues({});
        final p = await SharedPreferences.getInstance();
        final loaded = PlayerSettingsStore.loadGraphicEq(p);
        expect(loaded.levels.length, 18);
        expect(loaded.enabled, false);
      });

      test('stores under af.graphic_eq_json key', () async {
        SharedPreferences.setMockInitialValues({});
        final p = await SharedPreferences.getInstance();
        final state = GraphicEqState(enabled: true);
        await PlayerSettingsStore.saveGraphicEq(state);
        expect(p.getString('af.graphic_eq_json'), isNotNull);
      });
    });

    // ── Parametric EQ persistence ──────────────────────────────────────────
    group('saveParametricEq / loadParametricEq', () {
      test('round-trips default state', () async {
        SharedPreferences.setMockInitialValues({});
        final p = await SharedPreferences.getInstance();
        final state = ParametricEqState();
        await PlayerSettingsStore.saveParametricEq(state);
        final loaded = PlayerSettingsStore.loadParametricEq(p);
        expect(loaded.bands.length, 18);
      });

      test('round-trips with modified bands', () async {
        SharedPreferences.setMockInitialValues({});
        final p = await SharedPreferences.getInstance();
        final state = ParametricEqState();
        state.setBand(
          0,
          const ParametricEqBand(
            frequency: 1000,
            gain: 5.0,
            q: 2.0,
            type: BandType.lowShelf,
            enabled: true,
          ),
        );
        await PlayerSettingsStore.saveParametricEq(state);
        final loaded = PlayerSettingsStore.loadParametricEq(p);
        expect(loaded.bands[0].frequency, 1000);
        expect(loaded.bands[0].gain, 5.0);
        expect(loaded.bands[0].q, 2.0);
        expect(loaded.bands[0].type, BandType.lowShelf);
        expect(loaded.bands[0].enabled, true);
      });

      test('loads defaults when no key exists', () async {
        SharedPreferences.setMockInitialValues({});
        final p = await SharedPreferences.getInstance();
        final loaded = PlayerSettingsStore.loadParametricEq(p);
        expect(loaded.bands.length, 18);
      });

      test('stores under af.parametric_eq_json key', () async {
        SharedPreferences.setMockInitialValues({});
        final p = await SharedPreferences.getInstance();
        final state = ParametricEqState();
        await PlayerSettingsStore.saveParametricEq(state);
        expect(p.getString('af.parametric_eq_json'), isNotNull);
      });
    });

    // ── DSP state persistence ──────────────────────────────────────────────
    group('saveDspState / loadDspState', () {
      test('round-trips DSP-only effects', () async {
        SharedPreferences.setMockInitialValues({});
        final p = await SharedPreferences.getInstance();
        const fx = AudioEffects(
          bass: BassSettings(enabled: true, g: 5.0),
          treble: TrebleSettings(enabled: true, g: -3.0),
          loudnorm: LoudnormSettings(enabled: true),
        );
        await PlayerSettingsStore.saveDspState(fx);
        final loaded = PlayerSettingsStore.loadDspState(p);
        expect(loaded, isNotNull);
        expect(loaded!.bass.enabled, true);
        expect(loaded.bass.g, 5.0);
        expect(loaded.treble.enabled, true);
        expect(loaded.treble.g, -3.0);
        expect(loaded.loudnorm.enabled, true);
      });

      test('loads null when no key exists', () async {
        SharedPreferences.setMockInitialValues({});
        final p = await SharedPreferences.getInstance();
        final loaded = PlayerSettingsStore.loadDspState(p);
        expect(loaded, isNull);
      });

      test('stores under af.dsp_state_json key', () async {
        SharedPreferences.setMockInitialValues({});
        final p = await SharedPreferences.getInstance();
        const fx = AudioEffects();
        await PlayerSettingsStore.saveDspState(fx);
        expect(p.getString('af.dsp_state_json'), isNotNull);
      });
    });

    // ── Migration from old key ─────────────────────────────────────────────
    group('migration from af.audio_effects_json', () {
      test('migrates old key to 3 new keys', () async {
        // Set up old key with combined effects
        final oldFx = {
          'bass_g': 5.0,
          'bass_enabled': true,
          'treble_g': -3.0,
          'treble_enabled': true,
          'loudnorm_enabled': true,
          'compressor_enabled': false,
          'compressor_threshold': 0.1,
          'compressor_ratio': 4.0,
          'compressor_attack': 20.0,
          'compressor_release': 250.0,
          'eq_enabled': true,
          'eq_params': {'1b': 1.5, '2b': 1.2},
          'rubberband_enabled': false,
          'rubberband_pitch': 1.0,
          'rubberband_tempo': 1.0,
          'crossfeed_enabled': false,
          'crossfeed_strength': 0.2,
          'stereowiden_enabled': false,
          'stereowiden_delay': 20.0,
          'exciter_enabled': false,
          'exciter_amount': 1.0,
          'crystalizer_enabled': false,
          'crystalizer_i': 2.0,
          'virtualbass_enabled': false,
          'virtualbass_cutoff': 250.0,
          'gate_enabled': false,
          'gate_threshold': 0.01,
          'gate_ratio': 2.0,
          'gate_attack': 20.0,
          'gate_release': 250.0,
          'deesser_enabled': false,
          'deesser_i': 0.0,
          'deesser_m': 0.5,
          'deesser_f': 0.5,
          'echo_enabled': false,
          'echo_in_gain': 0.6,
          'echo_out_gain': 0.3,
          'echo_delays': '500',
          'echo_decays': '0.5',
          'phaser_enabled': false,
          'phaser_in_gain': 0.4,
          'phaser_out_gain': 0.74,
          'phaser_delay': 3.0,
          'phaser_decay': 0.4,
          'phaser_speed': 0.5,
          'flanger_enabled': false,
          'flanger_delay': 0.0,
          'flanger_depth': 2.0,
          'flanger_regen': 0.0,
          'flanger_width': 71.0,
          'flanger_speed': 0.5,
          'chorus_enabled': false,
          'chorus_in_gain': 0.4,
          'chorus_out_gain': 0.4,
          'chorus_delays': '40|60',
          'chorus_decays': '0.4|0.32',
          'chorus_speeds': '0.25|0.4',
          'chorus_depths': '2|3',
          'tremolo_enabled': false,
          'tremolo_f': 5.0,
          'tremolo_d': 0.5,
          'vibrato_enabled': false,
          'vibrato_f': 5.0,
          'vibrato_d': 0.5,
          'crusher_enabled': false,
          'crusher_bits': 8.0,
          'crusher_mix': 0.5,
          'crusher_samples': 1.0,
          'custom_filters': [
            'lavfi-equalizer=f=1000:t=q:w=1.0:g=3.0',
            'lavfi-bass=f=200:t=q:w=0.7:g=6',
          ],
        };

        SharedPreferences.setMockInitialValues({
          'af.audio_effects_json': jsonEncode(oldFx),
        });
        final p = await SharedPreferences.getInstance();

        // Run migration
        await PlayerSettingsStore.migrateFromOldKey(p);

        // Verify old key is removed
        expect(p.getString('af.audio_effects_json'), isNull);

        // Verify 3 new keys exist
        expect(p.getString('af.dsp_state_json'), isNotNull);
        expect(p.getString('af.graphic_eq_json'), isNotNull);
        expect(p.getString('af.parametric_eq_json'), isNotNull);

        // Verify DSP state loaded correctly
        final dsp = PlayerSettingsStore.loadDspState(p);
        expect(dsp, isNotNull);
        expect(dsp!.bass.enabled, true);
        expect(dsp.bass.g, 5.0);
        expect(dsp.loudnorm.enabled, true);

        // Verify graphic EQ loaded correctly
        final graphicEq = PlayerSettingsStore.loadGraphicEq(p);
        expect(graphicEq.enabled, true);
        expect(graphicEq.levels[0], closeTo(1.0, 0.1));

        // Verify parametric EQ loaded correctly
        final parametricEq = PlayerSettingsStore.loadParametricEq(p);
        expect(parametricEq.bands.length, 2);
        expect(parametricEq.bands[0].frequency, 1000);
        expect(parametricEq.bands[0].type, BandType.peak);
        expect(parametricEq.bands[1].frequency, 200);
        expect(parametricEq.bands[1].type, BandType.lowShelf);
      });

      test('does nothing when old key does not exist', () async {
        SharedPreferences.setMockInitialValues({});
        final p = await SharedPreferences.getInstance();

        await PlayerSettingsStore.migrateFromOldKey(p);

        // No keys should be created
        expect(p.getString('af.audio_effects_json'), isNull);
        expect(p.getString('af.dsp_state_json'), isNull);
        expect(p.getString('af.graphic_eq_json'), isNull);
        expect(p.getString('af.parametric_eq_json'), isNull);
      });

      test('migration is idempotent', () async {
        final oldFx = {
          'bass_g': 3.0,
          'bass_enabled': true,
          'treble_g': 0.0,
          'treble_enabled': false,
          'loudnorm_enabled': false,
          'compressor_enabled': false,
          'compressor_threshold': 0.1,
          'compressor_ratio': 4.0,
          'compressor_attack': 20.0,
          'compressor_release': 250.0,
          'eq_enabled': false,
          'eq_params': <String, dynamic>{},
          'rubberband_enabled': false,
          'rubberband_pitch': 1.0,
          'rubberband_tempo': 1.0,
          'crossfeed_enabled': false,
          'crossfeed_strength': 0.2,
          'stereowiden_enabled': false,
          'stereowiden_delay': 20.0,
          'exciter_enabled': false,
          'exciter_amount': 1.0,
          'crystalizer_enabled': false,
          'crystalizer_i': 2.0,
          'virtualbass_enabled': false,
          'virtualbass_cutoff': 250.0,
          'gate_enabled': false,
          'gate_threshold': 0.01,
          'gate_ratio': 2.0,
          'gate_attack': 20.0,
          'gate_release': 250.0,
          'deesser_enabled': false,
          'deesser_i': 0.0,
          'deesser_m': 0.5,
          'deesser_f': 0.5,
          'echo_enabled': false,
          'echo_in_gain': 0.6,
          'echo_out_gain': 0.3,
          'echo_delays': '500',
          'echo_decays': '0.5',
          'phaser_enabled': false,
          'phaser_in_gain': 0.4,
          'phaser_out_gain': 0.74,
          'phaser_delay': 3.0,
          'phaser_decay': 0.4,
          'phaser_speed': 0.5,
          'flanger_enabled': false,
          'flanger_delay': 0.0,
          'flanger_depth': 2.0,
          'flanger_regen': 0.0,
          'flanger_width': 71.0,
          'flanger_speed': 0.5,
          'chorus_enabled': false,
          'chorus_in_gain': 0.4,
          'chorus_out_gain': 0.4,
          'chorus_delays': '40|60',
          'chorus_decays': '0.4|0.32',
          'chorus_speeds': '0.25|0.4',
          'chorus_depths': '2|3',
          'tremolo_enabled': false,
          'tremolo_f': 5.0,
          'tremolo_d': 0.5,
          'vibrato_enabled': false,
          'vibrato_f': 5.0,
          'vibrato_d': 0.5,
          'crusher_enabled': false,
          'crusher_bits': 8.0,
          'crusher_mix': 0.5,
          'crusher_samples': 1.0,
          'custom_filters': <String>[],
        };

        SharedPreferences.setMockInitialValues({
          'af.audio_effects_json': jsonEncode(oldFx),
        });
        final p = await SharedPreferences.getInstance();

        // Run migration twice
        await PlayerSettingsStore.migrateFromOldKey(p);
        await PlayerSettingsStore.migrateFromOldKey(p);

        // Old key should still be removed
        expect(p.getString('af.audio_effects_json'), isNull);

        // New keys should exist and be valid
        expect(p.getString('af.dsp_state_json'), isNotNull);
        expect(p.getString('af.graphic_eq_json'), isNotNull);
        expect(p.getString('af.parametric_eq_json'), isNotNull);
      });
    });
  });
}
