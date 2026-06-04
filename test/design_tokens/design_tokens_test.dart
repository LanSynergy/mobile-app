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
      expect(AfColors.surfaceCanvas.toARGB32(), 0xFF0A0A0A);
      expect(AfColors.surfaceLow.toARGB32(), 0xFF161616);
      expect(AfColors.surfaceBase.toARGB32(), 0xFF222222);
      expect(AfColors.surfaceRaised.toARGB32(), 0xFF2E2E2E);
      expect(AfColors.surfaceHigh.toARGB32(), 0xFF3A3A3A);
      expect(AfColors.surfaceMax.toARGB32(), 0xFF464646);
    });

    test('accent colors use warm amber palette', () {
      expect(AfColors.accentPrimary.toARGB32(), 0xFFD4A574);
      expect(AfColors.accentSecondary.toARGB32(), 0xFFC86E4B);
      expect(AfColors.accentMuted.toARGB32(), 0xFF8B7355);
    });

    test('text colors use warm whites', () {
      expect(AfColors.textPrimary.toARGB32(), 0xFFF5F0EB);
      expect(AfColors.textSecondary.toARGB32(), 0xFFA89F94);
      expect(AfColors.textTertiary.toARGB32(), 0xFF6B6560);
    });
  });

  group('Spacing — non-negotiable', () {
    test('48dp minimum hit target everywhere', () {
      expect(AfSpacing.minHitTarget, 48);
    });
    test('floating mini-player is 64dp tall, 12dp side margin, 12dp gap', () {
      expect(AfSpacing.miniPlayerHeight, 64);
      expect(AfSpacing.miniPlayerSideMargin, 12);
      expect(AfSpacing.miniPlayerNavGap, 12);
    });
  });
}
