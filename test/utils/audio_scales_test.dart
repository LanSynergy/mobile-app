import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:aetherfin/utils/audio_scales.dart';

void main() {
  group('AudioScales', () {
    // ── Frequency normalization ────────────────────────────────────────────
    group('freqToNormalized', () {
      test('20 Hz maps to 0.0', () {
        expect(AudioScales.freqToNormalized(20), closeTo(0.0, 1e-10));
      });

      test('20000 Hz maps to 1.0', () {
        expect(AudioScales.freqToNormalized(20000), closeTo(1.0, 1e-10));
      });

      test('1000 Hz maps to ~0.5 (logarithmic midpoint)', () {
        final expected = (log(1000 / 20) / log(20000 / 20));
        expect(AudioScales.freqToNormalized(1000), closeTo(expected, 1e-10));
      });

      test('clamps below 20 Hz to 0.0', () {
        expect(AudioScales.freqToNormalized(10), 0.0);
      });

      test('clamps above 20000 Hz to 1.0', () {
        expect(AudioScales.freqToNormalized(50000), 1.0);
      });

      test('100 Hz is below midpoint (bass region)', () {
        expect(AudioScales.freqToNormalized(100), lessThan(0.5));
      });

      test('5000 Hz is above midpoint (treble region)', () {
        expect(AudioScales.freqToNormalized(5000), greaterThan(0.5));
      });
    });

    group('normalizedToFreq', () {
      test('0.0 maps to 20 Hz', () {
        expect(AudioScales.normalizedToFreq(0), closeTo(20, 1e-10));
      });

      test('1.0 maps to 20000 Hz', () {
        expect(AudioScales.normalizedToFreq(1), closeTo(20000, 1e-10));
      });

      test('round-trips through freqToNormalized', () {
        const freqs = [20.0, 50.0, 100.0, 500.0, 1000.0, 5000.0, 20000.0];
        for (final freq in freqs) {
          final normalized = AudioScales.freqToNormalized(freq);
          final roundTripped = AudioScales.normalizedToFreq(normalized);
          expect(roundTripped, closeTo(freq, 0.01));
        }
      });

      test('clamps below 0.0 to 20 Hz', () {
        expect(AudioScales.normalizedToFreq(-0.5), closeTo(20, 1e-10));
      });

      test('clamps above 1.0 to 20000 Hz', () {
        expect(AudioScales.normalizedToFreq(1.5), closeTo(20000, 1e-10));
      });
    });

    // ── Frequency ↔ pixel mapping ──────────────────────────────────────────
    group('freqToX / xToFreq', () {
      const width = 400.0;

      test('20 Hz maps to x=0', () {
        expect(AudioScales.freqToX(20, width), closeTo(0, 1e-10));
      });

      test('20000 Hz maps to x=width', () {
        expect(AudioScales.freqToX(20000, width), closeTo(width, 1e-10));
      });

      test('round-trips through pixel space', () {
        const freqs = [20.0, 100.0, 1000.0, 10000.0, 20000.0];
        for (final freq in freqs) {
          final x = AudioScales.freqToX(freq, width);
          final roundTripped = AudioScales.xToFreq(x, width);
          expect(roundTripped, closeTo(freq, 0.5));
        }
      });
    });

    // ── dB ↔ Y coordinate mapping ──────────────────────────────────────────
    group('dbToY / yToDb', () {
      const height = 200.0;
      const dbRange = 12.0;

      test('0 dB maps to center', () {
        expect(AudioScales.dbToY(0, height, dbRange: dbRange), height / 2);
      });

      test('+dB maps above center (lower y)', () {
        expect(
          AudioScales.dbToY(6, height, dbRange: dbRange),
          lessThan(height / 2),
        );
      });

      test('-dB maps below center (higher y)', () {
        expect(
          AudioScales.dbToY(-6, height, dbRange: dbRange),
          greaterThan(height / 2),
        );
      });

      test('round-trips through yToDb', () {
        const dbs = [-12.0, -6.0, 0.0, 3.0, 6.0, 12.0];
        for (final db in dbs) {
          final y = AudioScales.dbToY(db, height, dbRange: dbRange);
          final roundTripped = AudioScales.yToDb(y, height, dbRange: dbRange);
          expect(roundTripped, closeTo(db, 1e-10));
        }
      });
    });

    // ── dB ↔ multiplier conversion ─────────────────────────────────────────
    group('dB / multiplier conversion', () {
      test('1.0 multiplier = 0 dB', () {
        expect(AudioScales.multiplierToDb(1.0), closeTo(0.0, 1e-10));
      });

      test('0.5 multiplier = -6 dB', () {
        expect(AudioScales.multiplierToDb(0.5), closeTo(-6.02, 0.01));
      });

      test('2.0 multiplier = +6 dB', () {
        expect(AudioScales.multiplierToDb(2.0), closeTo(6.02, 0.01));
      });

      test('0 dB = 1.0 multiplier', () {
        expect(AudioScales.dbToMultiplier(0), closeTo(1.0, 1e-10));
      });

      test('-6 dB ≈ 0.5 multiplier', () {
        expect(AudioScales.dbToMultiplier(-6), closeTo(0.5, 0.01));
      });

      test('+6 dB ≈ 2.0 multiplier', () {
        expect(AudioScales.dbToMultiplier(6), closeTo(2.0, 0.01));
      });

      test('+12 dB ≈ 3.98 multiplier', () {
        expect(AudioScales.dbToMultiplier(12), closeTo(3.981, 0.01));
      });

      test('-12 dB ≈ 0.251 multiplier', () {
        expect(AudioScales.dbToMultiplier(-12), closeTo(0.251, 0.01));
      });

      test('round-trips multiplier → dB → multiplier', () {
        const multipliers = [0.25, 0.5, 0.707, 1.0, 1.414, 2.0, 4.0];
        for (final m in multipliers) {
          final db = AudioScales.multiplierToDb(m);
          final roundTripped = AudioScales.dbToMultiplier(db);
          expect(roundTripped, closeTo(m, 1e-6));
        }
      });
    });

    // ── Gain to band color ──────────────────────────────────────────────────
    group('bandColorForFrequency', () {
      test('20 Hz returns red-ish color', () {
        final color = AudioScales.bandColorForFrequency(20);
        // Red channel should be dominant
        expect(color.r, greaterThan(color.b));
      });

      test('20000 Hz returns blue-ish color', () {
        final color = AudioScales.bandColorForFrequency(20000);
        // Blue channel should be dominant
        expect(color.b, greaterThan(color.r));
      });

      test('1000 Hz returns yellow/green color', () {
        final color = AudioScales.bandColorForFrequency(1000);
        // Mid-range: green should be relatively high
        expect(color.g, greaterThan(0.3));
      });
    });

    // ── Snap to value ──────────────────────────────────────────────────────
    group('snapToValue', () {
      test('slow velocity snaps to 0.1 dB', () {
        expect(AudioScales.snapToValue(3.14159, velocity: 10), 3.1);
        expect(AudioScales.snapToValue(3.16, velocity: 10), 3.2);
      });

      test('fast velocity snaps to 1 dB', () {
        expect(AudioScales.snapToValue(3.7, velocity: 100), 4.0);
        expect(AudioScales.snapToValue(3.2, velocity: 100), 3.0);
      });

      test('zero velocity treated as slow', () {
        expect(AudioScales.snapToValue(3.14, velocity: 0), 3.1);
      });
    });

    // ── Snap to ISO frequency ──────────────────────────────────────────────
    group('snapToIsoFrequency', () {
      test('1000 Hz is already ISO', () {
        expect(AudioScales.snapToIsoFrequency(1000), 1000);
      });

      test('950 Hz snaps to nearest ISO (1000)', () {
        expect(AudioScales.snapToIsoFrequency(950), 1000);
      });

      test('20 Hz is ISO', () {
        expect(AudioScales.snapToIsoFrequency(20), 20);
      });

      test('20000 Hz is ISO', () {
        expect(AudioScales.snapToIsoFrequency(20000), 20000);
      });

      test('35 Hz snaps to 31.5 Hz', () {
        expect(AudioScales.snapToIsoFrequency(35), closeTo(31.5, 1));
      });
    });

    // ── Haptic threshold detection ──────────────────────────────────────────
    group('shouldTriggerHaptic', () {
      test('crossing whole dB triggers', () {
        expect(AudioScales.shouldTriggerHaptic(2.9, 3.1), isTrue);
      });

      test('crossing 0 dB triggers', () {
        expect(AudioScales.shouldTriggerHaptic(0.1, -0.1), isTrue);
        expect(AudioScales.shouldTriggerHaptic(-0.1, 0.1), isTrue);
      });

      test('same dB no trigger', () {
        expect(AudioScales.shouldTriggerHaptic(3.0, 3.05), isFalse);
      });

      test('staying in same dB range no trigger', () {
        expect(AudioScales.shouldTriggerHaptic(3.2, 3.8), isFalse);
      });
    });
  });
}
