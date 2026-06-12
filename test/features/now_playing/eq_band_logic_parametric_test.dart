import 'package:flutter_test/flutter_test.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import 'package:aetherfin/features/now_playing/eq_band_logic.dart';

void main() {
  group('EqDspState parametric EQ', () {
    late EqDspState state;

    setUp(() {
      state = EqDspState();
    });

    // ── Default state ────────────────────────────────────────────────────
    group('defaults', () {
      test('parametricEnabled is false by default', () {
        expect(state.parametricEnabled, false);
      });

      test('parametricBands has 10 default bands', () {
        expect(state.parametricBands.length, 10);
      });

      test('parametricBands has correct default frequencies', () {
        expect(state.parametricBands[0].frequency, 31.0);
        expect(state.parametricBands[1].frequency, 62.0);
        expect(state.parametricBands[2].frequency, 125.0);
        expect(state.parametricBands[3].frequency, 250.0);
        expect(state.parametricBands[4].frequency, 500.0);
        expect(state.parametricBands[5].frequency, 1000.0);
        expect(state.parametricBands[6].frequency, 2000.0);
        expect(state.parametricBands[7].frequency, 4000.0);
        expect(state.parametricBands[8].frequency, 8000.0);
        expect(state.parametricBands[9].frequency, 16000.0);
      });

      test('parametricBands all start with zero gain', () {
        for (final band in state.parametricBands) {
          expect(band.gain, 0.0);
        }
      });
    });

    // ── setField dispatch ────────────────────────────────────────────────
    group('setField', () {
      test('sets parametricEnabled', () {
        state.setField('parametricEnabled', true);
        expect(state.parametricEnabled, true);
      });

      test('sets parametricBand0Freq', () {
        state.setField('parametricBand0Freq', 100.0);
        expect(state.parametricBands[0].frequency, 100.0);
      });

      test('sets parametricBand0Gain', () {
        state.setField('parametricBand0Gain', 5.0);
        expect(state.parametricBands[0].gain, 5.0);
      });

      test('sets parametricBand0Q', () {
        state.setField('parametricBand0Q', 2.5);
        expect(state.parametricBands[0].q, 2.5);
      });

      test('sets parametricBand0Enabled', () {
        state.setField('parametricBand0Enabled', false);
        expect(state.parametricBands[0].enabled, false);
      });

      test('sets parametricBand4Freq', () {
        state.setField('parametricBand4Freq', 15000.0);
        expect(state.parametricBands[4].frequency, 15000.0);
      });

      test('sets parametricBand4Gain', () {
        state.setField('parametricBand4Gain', -8.0);
        expect(state.parametricBands[4].gain, -8.0);
      });

      test('sets parametricBand4Q', () {
        state.setField('parametricBand4Q', 6.0);
        expect(state.parametricBands[4].q, 6.0);
      });

      test('sets parametricBand4Enabled', () {
        state.setField('parametricBand4Enabled', false);
        expect(state.parametricBands[4].enabled, false);
      });

      test('sets parametricBand2Freq for mid band', () {
        state.setField('parametricBand2Freq', 1200.0);
        expect(state.parametricBands[2].frequency, 1200.0);
      });
    });

    // ── reset ────────────────────────────────────────────────────────────
    group('reset', () {
      test('resets parametricEnabled to false', () {
        state.parametricEnabled = true;
        state.reset();
        expect(state.parametricEnabled, false);
      });

      test('resets all parametric bands to defaults', () {
        state.setField('parametricBand0Gain', 5.0);
        state.setField('parametricBand0Freq', 1000.0);
        state.setField('parametricBand2Q', 8.0);
        state.reset();
        expect(state.parametricBands[0].frequency, 31.0);
        expect(state.parametricBands[0].gain, 0.0);
        expect(state.parametricBands[0].q, 0.7);
        expect(state.parametricBands[2].frequency, 125.0);
        expect(state.parametricBands[2].gain, 0.0);
        expect(state.parametricBands[2].q, 0.8);
      });
    });

    // ── toAudioEffects custom injection ──────────────────────────────────
    group('toAudioEffects', () {
      test('includes parametric lavfi strings in custom when enabled', () {
        state.parametricEnabled = true;
        state.setField('parametricBand0Gain', 3.0);
        state.setField('parametricBand1Gain', -2.0);

        final fx = state.toAudioEffects();
        expect(fx.custom.length, 2);
        expect(fx.custom[0], contains('lavfi-equalizer'));
        expect(fx.custom[0], contains('f=31.0'));
        expect(fx.custom[1], contains('f=62.0'));
      });

      test('empty custom when parametric disabled', () {
        state.parametricEnabled = false;
        state.setField('parametricBand0Gain', 5.0);

        final fx = state.toAudioEffects();
        expect(fx.custom, isEmpty);
      });

      test('skips bands with near-zero gain', () {
        state.parametricEnabled = true;
        state.setField('parametricBand0Gain', 0.03); // below threshold
        state.setField('parametricBand1Gain', 3.0);

        final fx = state.toAudioEffects();
        expect(fx.custom.length, 1);
        expect(fx.custom[0], contains('f=62.0'));
      });

      test('skips disabled bands', () {
        state.parametricEnabled = true;
        state.setField('parametricBand0Enabled', false);
        state.setField('parametricBand0Gain', 5.0);
        state.setField('parametricBand1Gain', 2.0);

        final fx = state.toAudioEffects();
        expect(fx.custom.length, 1);
        expect(fx.custom[0], contains('f=62.0'));
      });

      test('includes all active bands', () {
        state.parametricEnabled = true;
        for (var i = 0; i < 10; i++) {
          state.setField('parametricBand${i}Gain', 1.0);
        }

        final fx = state.toAudioEffects();
        expect(fx.custom.length, 10);
      });
    });

    // ── loadFromAudioEffects ─────────────────────────────────────────────
    group('loadFromAudioEffects', () {
      test('loads parametric bands from custom strings', () {
        final fx = AudioEffects(
          custom: [
            'lavfi-equalizer=f=60.0:t=q:w=0.70:g=3.0',
            'lavfi-equalizer=f=230.0:t=q:w=0.70:g=-2.0',
          ],
        );
        state.loadFromAudioEffects(fx);
        expect(state.parametricBands.length, 2);
        expect(state.parametricBands[0].frequency, 60.0);
        expect(state.parametricBands[0].gain, 3.0);
        expect(state.parametricBands[0].q, 0.7);
        expect(state.parametricBands[1].frequency, 230.0);
        expect(state.parametricBands[1].gain, -2.0);
      });

      test('sets parametricEnabled when custom strings present', () {
        final fx = AudioEffects(
          custom: ['lavfi-equalizer=f=1000:t=q:w=1.0:g=5.0'],
        );
        state.loadFromAudioEffects(fx);
        expect(state.parametricEnabled, true);
      });

      test('sets parametricEnabled false when no custom strings', () {
        state.parametricEnabled = true;
        final fx = AudioEffects(custom: []);
        state.loadFromAudioEffects(fx);
        expect(state.parametricEnabled, false);
      });

      test('handles empty custom gracefully', () {
        final fx = AudioEffects();
        state.loadFromAudioEffects(fx);
        expect(state.parametricEnabled, false);
        expect(state.parametricBands, isEmpty);
      });
    });

    // ── parametricCount ──────────────────────────────────────────────────
    group('parametricCount', () {
      test('returns 0 when disabled', () {
        state.parametricEnabled = false;
        state.setField('parametricBand0Gain', 5.0);
        expect(state.parametricCount, 0);
      });

      test('counts only active bands with significant gain', () {
        state.parametricEnabled = true;
        state.setField('parametricBand0Gain', 3.0);
        state.setField('parametricBand1Gain', 0.03); // below threshold
        state.setField('parametricBand2Gain', -2.0);
        state.setField('parametricBand2Enabled', false);
        state.setField('parametricBand3Gain', 4.0);
        expect(state.parametricCount, 2);
      });
    });

    // ── Persistence round-trip via custom strings ────────────────────────
    group('persistence round-trip', () {
      test(
        'custom lavfi strings survive toAudioEffects -> loadFromAudioEffects',
        () {
          state.parametricEnabled = true;
          state.setField('parametricBand0Gain', 4.0);
          state.setField('parametricBand0Q', 2.5);
          state.setField('parametricBand1Gain', -3.0);
          state.setField('parametricBand1Freq', 300.0);

          final fx = state.toAudioEffects();

          // Reset and reload
          state.reset();
          expect(state.parametricBands[0].gain, 0.0);

          state.loadFromAudioEffects(fx);
          expect(state.parametricBands[0].frequency, 31.0);
          expect(state.parametricBands[0].gain, 4.0);
          expect(state.parametricBands[0].q, 2.5);
          expect(state.parametricBands[1].frequency, 300);
          expect(state.parametricBands[1].gain, -3.0);
        },
      );
    });
  });
}
