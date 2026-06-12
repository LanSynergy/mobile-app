import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:aetherfin/features/now_playing/parametric_band.dart';

void main() {
  group('ParametricBand', () {
    // ── Constructor defaults ──────────────────────────────────────────────
    group('constructor', () {
      test('creates with required frequency only', () {
        const band = ParametricBand(frequency: 1000);
        expect(band.frequency, 1000);
        expect(band.gain, 0.0);
        expect(band.q, 1.0);
        expect(band.enabled, true);
      });

      test('creates with all parameters', () {
        const band = ParametricBand(
          frequency: 230,
          gain: -3.5,
          q: 0.7,
          enabled: false,
        );
        expect(band.frequency, 230);
        expect(band.gain, -3.5);
        expect(band.q, 0.7);
        expect(band.enabled, false);
      });
    });

    // ── JSON round-trip ──────────────────────────────────────────────────
    group('toJson / fromJson', () {
      test('round-trips default values', () {
        const original = ParametricBand(frequency: 60);
        final json = original.toJson();
        final restored = ParametricBand.fromJson(json);
        expect(restored.frequency, 60);
        expect(restored.gain, 0.0);
        expect(restored.q, 1.0);
        expect(restored.enabled, true);
      });

      test('round-trips non-default values', () {
        const original = ParametricBand(
          frequency: 3500,
          gain: 6.5,
          q: 4.2,
          enabled: false,
        );
        final json = original.toJson();
        final restored = ParametricBand.fromJson(json);
        expect(restored.frequency, 3500);
        expect(restored.gain, 6.5);
        expect(restored.q, 4.2);
        expect(restored.enabled, false);
      });

      test('handles missing enabled key gracefully', () {
        final json = {'frequency': 100, 'gain': 2.0, 'q': 1.0};
        final band = ParametricBand.fromJson(json);
        expect(band.enabled, true);
      });

      test('serializes to valid JSON string', () {
        const band = ParametricBand(frequency: 230, gain: -1, q: 0.7);
        final jsonString = jsonEncode(band.toJson());
        final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
        expect(decoded['frequency'], 230);
        expect(decoded['gain'], -1);
        expect(decoded['q'], 0.7);
        expect(decoded['enabled'], true);
      });
    });

    // ── Lavfi string serialization ───────────────────────────────────────
    group('toLavfiString', () {
      test('produces correct lavfi format for active band', () {
        const band = ParametricBand(frequency: 60, gain: 2.0, q: 0.7);
        final lavfi = band.toLavfiString();
        expect(lavfi, 'lavfi-equalizer=f=60.0:t=q:w=0.70:g=2.0');
      });

      test('returns empty string when disabled', () {
        const band = ParametricBand(
          frequency: 60,
          gain: 5.0,
          q: 0.7,
          enabled: false,
        );
        expect(band.toLavfiString(), '');
      });

      test('returns empty string when gain is near zero', () {
        const band = ParametricBand(frequency: 60, gain: 0.03, q: 0.7);
        expect(band.toLavfiString(), '');
      });

      test('returns empty string when gain is negative near zero', () {
        const band = ParametricBand(frequency: 60, gain: -0.04, q: 0.7);
        expect(band.toLavfiString(), '');
      });

      test('produces correct lavfi for negative gain', () {
        const band = ParametricBand(frequency: 3500, gain: -6.0, q: 1.2);
        final lavfi = band.toLavfiString();
        expect(lavfi, 'lavfi-equalizer=f=3500.0:t=q:w=1.20:g=-6.0');
      });

      test('produces correct lavfi for high Q', () {
        const band = ParametricBand(frequency: 800, gain: -12, q: 8.0);
        final lavfi = band.toLavfiString();
        expect(lavfi, 'lavfi-equalizer=f=800.0:t=q:w=8.00:g=-12.0');
      });
    });

    // ── Default bands ────────────────────────────────────────────────────
    group('defaultBands', () {
      test('returns exactly 10 bands', () {
        final bands = ParametricBand.defaultBands();
        expect(bands.length, 10);
      });

      test('has correct logarithmic frequency spacing', () {
        final bands = ParametricBand.defaultBands();
        expect(bands[0].frequency, 31.0);
        expect(bands[1].frequency, 62.0);
        expect(bands[2].frequency, 125.0);
        expect(bands[3].frequency, 250.0);
        expect(bands[4].frequency, 500.0);
        expect(bands[5].frequency, 1000.0);
        expect(bands[6].frequency, 2000.0);
        expect(bands[7].frequency, 4000.0);
        expect(bands[8].frequency, 8000.0);
        expect(bands[9].frequency, 16000.0);
      });

      test('all bands start with zero gain', () {
        final bands = ParametricBand.defaultBands();
        for (final band in bands) {
          expect(band.gain, 0.0);
        }
      });

      test('all bands start enabled', () {
        final bands = ParametricBand.defaultBands();
        for (final band in bands) {
          expect(band.enabled, true);
        }
      });

      test('has correct Q values per band', () {
        final bands = ParametricBand.defaultBands();
        expect(bands[0].q, 0.7);
        expect(bands[1].q, 0.7);
        expect(bands[2].q, 0.8);
        expect(bands[3].q, 0.9);
        expect(bands[4].q, 1.0);
        expect(bands[5].q, 1.0);
        expect(bands[6].q, 1.0);
        expect(bands[7].q, 1.2);
        expect(bands[8].q, 0.9);
        expect(bands[9].q, 0.7);
      });
    });

    // ── defaultAt ────────────────────────────────────────────────────────
    group('defaultAt', () {
      test('creates correct band at index 0', () {
        final band = ParametricBand.defaultAt(0);
        expect(band.frequency, 31.0);
        expect(band.q, 0.7);
        expect(band.gain, 0.0);
      });

      test('creates correct band at index 4', () {
        final band = ParametricBand.defaultAt(4);
        expect(band.frequency, 500.0);
        expect(band.q, 1.0);
      });
    });

    // ── Edge cases ───────────────────────────────────────────────────────
    group('edge cases', () {
      test('handles minimum frequency (20 Hz)', () {
        const band = ParametricBand(frequency: 20, gain: 3, q: 0.3);
        final lavfi = band.toLavfiString();
        expect(lavfi, contains('f=20.0'));
      });

      test('handles maximum frequency (20000 Hz)', () {
        const band = ParametricBand(frequency: 20000, gain: 3, q: 12.0);
        final lavfi = band.toLavfiString();
        expect(lavfi, contains('f=20000.0'));
      });

      test('handles minimum Q (0.3)', () {
        const band = ParametricBand(frequency: 1000, gain: 3, q: 0.3);
        final lavfi = band.toLavfiString();
        expect(lavfi, contains('w=0.30'));
      });

      test('handles maximum Q (12.0)', () {
        const band = ParametricBand(frequency: 1000, gain: 3, q: 12.0);
        final lavfi = band.toLavfiString();
        expect(lavfi, contains('w=12.00'));
      });

      test('handles maximum gain (+24 dB)', () {
        const band = ParametricBand(frequency: 1000, gain: 24.0, q: 1.0);
        final lavfi = band.toLavfiString();
        expect(lavfi, contains('g=24.0'));
      });

      test('handles maximum negative gain (-24 dB)', () {
        const band = ParametricBand(frequency: 1000, gain: -24.0, q: 1.0);
        final lavfi = band.toLavfiString();
        expect(lavfi, contains('g=-24.0'));
      });

      test('gain of exactly 0.05 is treated as active', () {
        const band = ParametricBand(frequency: 1000, gain: 0.05, q: 1.0);
        expect(band.toLavfiString(), isNotEmpty);
      });

      test('gain of -0.05 is treated as active', () {
        const band = ParametricBand(frequency: 1000, gain: -0.05, q: 1.0);
        expect(band.toLavfiString(), isNotEmpty);
      });
    });
  });

  group('ParametricPreset', () {
    group('constructor', () {
      test('creates with name and bands', () {
        const preset = ParametricPreset(
          name: 'Test',
          bands: [
            ParametricBand(frequency: 60, gain: 2, q: 0.7),
            ParametricBand(frequency: 230, gain: -1, q: 0.7),
          ],
        );
        expect(preset.name, 'Test');
        expect(preset.bands.length, 2);
      });
    });

    group('toJson / fromJson', () {
      test('round-trips preset with multiple bands', () {
        const original = ParametricPreset(
          name: 'Vocal Presence',
          bands: [
            ParametricBand(frequency: 230, gain: -2, q: 1.0),
            ParametricBand(frequency: 910, gain: 1, q: 1.0),
            ParametricBand(frequency: 3500, gain: 3, q: 1.2),
          ],
        );
        final json = original.toJson();
        final restored = ParametricPreset.fromJson(json);
        expect(restored.name, 'Vocal Presence');
        expect(restored.bands.length, 3);
        expect(restored.bands[0].frequency, 230);
        expect(restored.bands[0].gain, -2);
        expect(restored.bands[1].frequency, 910);
        expect(restored.bands[2].frequency, 3500);
      });

      test('serializes to valid JSON string', () {
        const preset = ParametricPreset(
          name: 'Flat',
          bands: [ParametricBand(frequency: 60)],
        );
        final jsonString = jsonEncode(preset.toJson());
        final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
        expect(decoded['name'], 'Flat');
        expect(decoded['bands'], isA<List<dynamic>>());
      });
    });
  });
}
