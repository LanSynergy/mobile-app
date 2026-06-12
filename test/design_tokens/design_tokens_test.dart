import 'package:aetherfin/design_tokens/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Motion tokens — non-negotiable', () {
    test('exactly five duration tiers exist', () {
      final tiers = {
        AfDurations.instant,
        AfDurations.quick,
        AfDurations.standard,
        AfDurations.expressive,
        AfDurations.long,
      };
      expect(tiers, hasLength(5));
    });

    test('durations match the iOS-like spec', () {
      expect(AfDurations.instant.inMilliseconds, 80);
      expect(AfDurations.quick.inMilliseconds, 180);
      expect(AfDurations.standard.inMilliseconds, 350);
      expect(AfDurations.expressive.inMilliseconds, 500);
      expect(AfDurations.long.inMilliseconds, 700);
    });

    test('exactly seven easing curves are exposed', () {
      expect(const [
        AfCurves.easeStandard,
        AfCurves.easeEmphasized,
        AfCurves.springPresent,
        AfCurves.springDismiss,
        AfCurves.easeOut,
        AfCurves.easeIn,
        AfCurves.linear,
      ], hasLength(7));
    });
  });

  group('Color tokens — Dark Moody palette', () {
    test('surface scale uses exact hex values', () {
      expect(AfColors.surfaceCanvas.toARGB32(), 0xFF0A0B0E);
      expect(AfColors.surfaceLow.toARGB32(), 0xFF14161A);
      expect(AfColors.surfaceBase.toARGB32(), 0xFF1E2028);
      expect(AfColors.surfaceRaised.toARGB32(), 0xFF282A34);
      expect(AfColors.surfaceHigh.toARGB32(), 0xFF343640);
      expect(AfColors.surfaceMax.toARGB32(), 0xFF40424E);
    });

    test('accent colors use ocean blue palette', () {
      expect(AfColors.accentPrimary.toARGB32(), 0xFF2E6FA8);
      expect(AfColors.accentSecondary.toARGB32(), 0xFF3A7CA5);
      expect(AfColors.accentMuted.toARGB32(), 0xFF6B8FA3);
    });

    test('text colors use cool whites', () {
      expect(AfColors.textPrimary.toARGB32(), 0xFFE8ECF2);
      expect(AfColors.textSecondary.toARGB32(), 0xFF9AA0AD);
      expect(AfColors.textTertiary.toARGB32(), 0xFF7C8290);
    });
  });

  group('Spacing — non-negotiable', () {
    test('48dp minimum hit target everywhere', () {
      expect(AfSpacing.minHitTarget, 48);
    });
  });
}
