import 'package:flutter_test/flutter_test.dart';
import 'package:aetherfin/features/now_playing/parametric_presets.dart';

void main() {
  group('kParametricPresets', () {
    test('contains Flat preset', () {
      expect(kParametricPresets.containsKey('Flat'), true);
    });

    test('contains Vocal Presence preset', () {
      expect(kParametricPresets.containsKey('Vocal Presence'), true);
    });

    test('contains Remove Resonance preset', () {
      expect(kParametricPresets.containsKey('Remove Resonance'), true);
    });

    test('contains Air Boost preset', () {
      expect(kParametricPresets.containsKey('Air Boost'), true);
    });

    test('contains Low Cut preset', () {
      expect(kParametricPresets.containsKey('Low Cut'), true);
    });

    test('contains Scooped preset', () {
      expect(kParametricPresets.containsKey('Scooped'), true);
    });

    test('has at least 6 built-in presets', () {
      expect(kParametricPresets.length, greaterThanOrEqualTo(6));
    });

    test('Flat preset has all zero gains', () {
      final flat = kParametricPresets['Flat']!;
      for (final band in flat.bands) {
        expect(band.gain, 0.0);
      }
    });

    test('Flat preset has 5 bands', () {
      final flat = kParametricPresets['Flat']!;
      expect(flat.bands.length, 5);
    });

    test('Vocal Presence preset has correct name', () {
      final preset = kParametricPresets['Vocal Presence']!;
      expect(preset.name, 'Vocal Presence');
    });

    test('all presets have valid band frequencies', () {
      for (final entry in kParametricPresets.entries) {
        for (final band in entry.value.bands) {
          expect(band.frequency, greaterThanOrEqualTo(20));
          expect(band.frequency, lessThanOrEqualTo(20000));
        }
      }
    });

    test('all presets have valid Q values', () {
      for (final entry in kParametricPresets.entries) {
        for (final band in entry.value.bands) {
          expect(band.q, greaterThanOrEqualTo(0.3));
          expect(band.q, lessThanOrEqualTo(12.0));
        }
      }
    });

    test('all presets have valid gain values', () {
      for (final entry in kParametricPresets.entries) {
        for (final band in entry.value.bands) {
          expect(band.gain, greaterThanOrEqualTo(-24));
          expect(band.gain, lessThanOrEqualTo(24));
        }
      }
    });

    test('Remove Resonance preset has narrow Q', () {
      final preset = kParametricPresets['Remove Resonance']!;
      expect(preset.bands[0].q, 8.0);
    });

    test('Low Cut preset has negative gain', () {
      final preset = kParametricPresets['Low Cut']!;
      expect(preset.bands[0].gain, lessThan(0));
    });

    test('Scooped preset has multiple bands', () {
      final preset = kParametricPresets['Scooped']!;
      expect(preset.bands.length, greaterThan(1));
    });
  });
}
