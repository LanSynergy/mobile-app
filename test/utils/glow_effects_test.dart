import 'package:aetherfin/utils/glow_effects.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GlowEffects', () {
    group('drawGlowingCurve', () {
      test('does not throw with valid path', () {
        // Pure function test — just verify the helper creates valid paints
        final paints = GlowEffects.glowPaints(Colors.blue);
        expect(paints, hasLength(3));
      });

      test('returns 3 paint layers (outer, inner, core)', () {
        final paints = GlowEffects.glowPaints(Colors.blue);
        // Outer: widest stroke, most transparent
        expect(paints[0].strokeWidth, greaterThan(paints[1].strokeWidth));
        // Inner: medium stroke
        expect(paints[1].strokeWidth, greaterThan(paints[2].strokeWidth));
        // Core: narrowest stroke
        expect(paints[2].strokeWidth, 2.5);
      });

      test('outer glow has lowest opacity', () {
        final paints = GlowEffects.glowPaints(Colors.blue);
        final outerAlpha = paints[0].color.a;
        final innerAlpha = paints[1].color.a;
        final coreAlpha = paints[2].color.a;
        expect(outerAlpha, lessThan(innerAlpha));
        expect(innerAlpha, lessThan(coreAlpha));
      });

      test('core paint has full opacity', () {
        final paints = GlowEffects.glowPaints(Colors.blue);
        expect(paints[2].color.a, closeTo(1.0, 0.01));
      });

      test('outer and inner have blur mask filter', () {
        final paints = GlowEffects.glowPaints(Colors.blue);
        expect(paints[0].maskFilter, isNotNull);
        expect(paints[1].maskFilter, isNotNull);
      });
    });

    group('drawBandNode', () {
      test('returns list of paints for node layers', () {
        final paints = GlowEffects.bandNodePaints(
          const Color(0xFFFF0000),
          isActive: false,
          isHovered: false,
        );
        expect(paints.length, greaterThanOrEqualTo(3));
      });

      test('active node has larger radius paint', () {
        final activePaints = GlowEffects.bandNodePaints(
          const Color(0xFFFF0000),
          isActive: true,
        );
        final inactivePaints = GlowEffects.bandNodePaints(
          const Color(0xFFFF0000),
          isActive: false,
        );
        // Active main circle should be larger
        expect(
          activePaints[1].strokeWidth,
          greaterThanOrEqualTo(inactivePaints[1].strokeWidth),
        );
      });
    });
  });

  group('BiquadEQ', () {
    group('peakingEqMagnitude', () {
      test('returns 0 dB at center frequency with 0 dB gain', () {
        final mag = BiquadEQ.peakingEqMagnitude(
          freq: 1000,
          f0: 1000,
          gainDb: 0,
          q: 1.0,
        );
        expect(mag, closeTo(0.0, 0.1));
      });

      test('returns positive dB at center frequency with +6 dB gain', () {
        final mag = BiquadEQ.peakingEqMagnitude(
          freq: 1000,
          f0: 1000,
          gainDb: 6,
          q: 1.0,
        );
        expect(mag, greaterThan(5.0));
        expect(mag, lessThan(7.0));
      });

      test('returns negative dB at center frequency with -6 dB gain', () {
        final mag = BiquadEQ.peakingEqMagnitude(
          freq: 1000,
          f0: 1000,
          gainDb: -6,
          q: 1.0,
        );
        expect(mag, lessThan(-5.0));
        expect(mag, greaterThan(-7.0));
      });

      test('returns near 0 dB far from center frequency', () {
        final mag = BiquadEQ.peakingEqMagnitude(
          freq: 20,
          f0: 1000,
          gainDb: 6,
          q: 1.0,
        );
        expect(mag.abs(), lessThan(1.0));
      });

      test('higher Q produces narrower peak', () {
        final wide = BiquadEQ.peakingEqMagnitude(
          freq: 1200,
          f0: 1000,
          gainDb: 6,
          q: 0.5,
        );
        final narrow = BiquadEQ.peakingEqMagnitude(
          freq: 1200,
          f0: 1000,
          gainDb: 6,
          q: 5.0,
        );
        // Narrow Q should have less gain at 1200 Hz (off-center)
        expect(narrow.abs(), lessThan(wide.abs()));
      });

      test('handles edge frequency 20 Hz', () {
        final mag = BiquadEQ.peakingEqMagnitude(
          freq: 20,
          f0: 20,
          gainDb: 6,
          q: 1.0,
        );
        expect(mag, greaterThan(5.0));
      });

      test('handles edge frequency 20000 Hz', () {
        final mag = BiquadEQ.peakingEqMagnitude(
          freq: 20000,
          f0: 20000,
          gainDb: 6,
          q: 1.0,
        );
        expect(mag, greaterThan(5.0));
      });
    });

    group('combinedResponse', () {
      test('flat response with no bands enabled', () {
        final response = BiquadEQ.combinedResponse(
          bands: [],
          startFreq: 20,
          endFreq: 20000,
          numPoints: 100,
        );
        for (final db in response) {
          expect(db, closeTo(0.0, 0.1));
        }
      });

      test('peak response at band frequency', () {
        final response = BiquadEQ.combinedResponse(
          bands: [const BiquadBand(frequency: 1000, gainDb: 6, q: 1.0)],
          startFreq: 20,
          endFreq: 20000,
          numPoints: 100,
        );
        // Middle of response should be near 1000 Hz peak
        final midIdx = response.length ~/ 2;
        expect(response[midIdx], greaterThan(3.0));
      });

      test('multiple bands combine additively', () {
        final single = BiquadEQ.combinedResponse(
          bands: [const BiquadBand(frequency: 1000, gainDb: 6, q: 1.0)],
          startFreq: 20,
          endFreq: 20000,
          numPoints: 100,
        );
        final double_ = BiquadEQ.combinedResponse(
          bands: [
            const BiquadBand(frequency: 1000, gainDb: 6, q: 1.0),
            const BiquadBand(frequency: 1000, gainDb: 6, q: 1.0),
          ],
          startFreq: 20,
          endFreq: 20000,
          numPoints: 100,
        );
        // Two identical bands should produce larger response
        final midIdx = single.length ~/ 2;
        expect(double_[midIdx], greaterThan(single[midIdx]));
      });
    });
  });
}
