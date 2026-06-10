import 'package:aetherfin/design_tokens/tokens.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Elevation tokens', () {
    test('none is empty', () {
      expect(AfElevation.none, isEmpty);
    });

    test('sm has exactly 1 shadow', () {
      expect(AfElevation.sm, hasLength(1));
    });

    test('md has exactly 1 shadow', () {
      expect(AfElevation.md, hasLength(1));
    });

    test('lg has exactly 1 shadow', () {
      expect(AfElevation.lg, hasLength(1));
    });

    test('xl has exactly 1 shadow', () {
      expect(AfElevation.xl, hasLength(1));
    });

    test('blur radius increases monotonically', () {
      final smBlur = AfElevation.sm.first.blurRadius;
      final mdBlur = AfElevation.md.first.blurRadius;
      final lgBlur = AfElevation.lg.first.blurRadius;
      final xlBlur = AfElevation.xl.first.blurRadius;
      expect(smBlur, lessThan(mdBlur));
      expect(mdBlur, lessThan(lgBlur));
      expect(lgBlur, lessThan(xlBlur));
    });

    test('spectralGlow returns 2 shadows', () {
      final glow = AfElevation.spectralGlow(const Color(0xFF5B9BD5), 0.5);
      expect(glow, hasLength(2));
    });

    test('spectralGlow clamps energy to 0.0-1.0', () {
      final low = AfElevation.spectralGlow(const Color(0xFF5B9BD5), 0.0);
      final high = AfElevation.spectralGlow(const Color(0xFF5B9BD5), 1.0);
      final over = AfElevation.spectralGlow(const Color(0xFF5B9BD5), 2.0);
      // All should produce valid shadows without throwing
      expect(low.first.blurRadius, 24);
      expect(high.first.blurRadius, 32);
      expect(over.first.blurRadius, 32); // clamped to 1.0
    });
  });
}
