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

    test('durations match the Dark Moody spec', () {
      expect(AfDurations.instant.inMilliseconds, 60);
      expect(AfDurations.quick.inMilliseconds, 120);
      expect(AfDurations.standard.inMilliseconds, 200);
      expect(AfDurations.expressive.inMilliseconds, 350);
      expect(AfDurations.long.inMilliseconds, 500);
    });

    test('exactly five easing curves are exposed', () {
      expect(const [
        AfCurves.easeStandard,
        AfCurves.easeEmphasized,
        AfCurves.easeOut,
        AfCurves.easeIn,
        AfCurves.linear,
      ], hasLength(5));
    });
  });

  group('Color tokens — Dark Moody palette', () {
    test('surface scale uses exact hex values', () {
      expect(AfColors.surfaceCanvas.toARGB32(), 0xFF0A0A0A);
      expect(AfColors.surfaceLow.toARGB32(), 0xFF111111);
      expect(AfColors.surfaceBase.toARGB32(), 0xFF181818);
      expect(AfColors.surfaceRaised.toARGB32(), 0xFF222222);
      expect(AfColors.surfaceHigh.toARGB32(), 0xFF2A2A2A);
      expect(AfColors.surfaceMax.toARGB32(), 0xFF333333);
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
