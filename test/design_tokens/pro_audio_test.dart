import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aetherfin/design_tokens/pro_audio.dart';

void main() {
  group('ProAudioColors', () {
    group('backgrounds', () {
      test('bgPrimary is #1A1A1E', () {
        expect(ProAudioColors.bgPrimary.toARGB32(), 0xFF1A1A1E);
      });

      test('bgPanel is #12141A', () {
        expect(ProAudioColors.bgPanel.toARGB32(), 0xFF12141A);
      });

      test('bgSurface is #22242A', () {
        expect(ProAudioColors.bgSurface.toARGB32(), 0xFF22242A);
      });

      test('bgOverlay is #0A0B0E', () {
        expect(ProAudioColors.bgOverlay.toARGB32(), 0xFF0A0B0E);
      });
    });

    group('grid and subtle', () {
      test('gridLine is 10% white', () {
        expect(ProAudioColors.gridLine.toARGB32(), 0x1AFFFFFF);
      });

      test('gridLineCenter is 30% white', () {
        expect(ProAudioColors.gridLineCenter.toARGB32(), 0x4DFFFFFF);
      });

      test('textDim is 45% white', () {
        expect(ProAudioColors.textDim.toARGB32(), 0x73FFFFFF);
      });

      test('textBright is 90% white', () {
        expect(ProAudioColors.textBright.toARGB32(), 0xFFE0E0E0);
      });
    });

    group('EQ curve', () {
      test('curveActive is gold #FFD700', () {
        expect(ProAudioColors.curveActive.toARGB32(), 0xFFFFD700);
      });

      test('curveGlow is 20% gold', () {
        expect(ProAudioColors.curveGlow.toARGB32(), 0x33FFD700);
      });

      test('curveInactive is 30% white', () {
        expect(ProAudioColors.curveInactive.toARGB32(), 0x4DFFFFFF);
      });
    });

    group('band colors (frequency-coded)', () {
      test('bandLow is red', () {
        const c = ProAudioColors.bandLow;
        expect(c.r, greaterThan(c.b));
        expect(c.r, greaterThan(c.g));
      });

      test('bandLowMid is orange', () {
        const c = ProAudioColors.bandLowMid;
        expect(c.r, greaterThan(c.b));
      });

      test('bandMid is yellow', () {
        const c = ProAudioColors.bandMid;
        expect(c.r, greaterThan(0.8));
        expect(c.g, greaterThan(0.7));
      });

      test('bandHighMid is green', () {
        const c = ProAudioColors.bandHighMid;
        expect(c.g, greaterThan(c.r));
      });

      test('bandHigh is blue', () {
        const c = ProAudioColors.bandHigh;
        expect(c.b, greaterThan(c.r));
        expect(c.b, greaterThan(c.g));
      });
    });

    group('meter zones', () {
      test('meterGreen, meterYellow, meterRed are distinct', () {
        expect(ProAudioColors.meterGreen, isNot(ProAudioColors.meterYellow));
        expect(ProAudioColors.meterYellow, isNot(ProAudioColors.meterRed));
        expect(ProAudioColors.meterGreen, isNot(ProAudioColors.meterRed));
      });

      test('meterGreen is greenish', () {
        expect(ProAudioColors.meterGreen.g, greaterThan(0.2));
      });

      test('meterRed is reddish', () {
        expect(ProAudioColors.meterRed.r, greaterThan(0.7));
      });
    });

    group('state colors', () {
      test('activeNode is white', () {
        expect(ProAudioColors.activeNode.toARGB32(), 0xFFFFFFFF);
      });

      test('inactiveNode is gray', () {
        expect(ProAudioColors.inactiveNode.toARGB32(), 0xFFAAAAAA);
      });

      test('accentFocus is light blue', () {
        expect(ProAudioColors.accentFocus.toARGB32(), 0xFF64B5F6);
      });
    });
  });

  group('ProAudioTypography', () {
    test('readout uses JetBrains Mono 13px', () {
      const style = ProAudioTypography.readout;
      expect(style.fontFamily, 'JetBrains Mono');
      expect(style.fontSize, 13);
      expect(style.fontWeight, FontWeight.w500);
    });

    test('freqLabel uses JetBrains Mono 9px', () {
      const style = ProAudioTypography.freqLabel;
      expect(style.fontFamily, 'JetBrains Mono');
      expect(style.fontSize, 9);
    });

    test('dbLabel uses JetBrains Mono 8px', () {
      const style = ProAudioTypography.dbLabel;
      expect(style.fontFamily, 'JetBrains Mono');
      expect(style.fontSize, 8);
    });

    test('sectionHeader uses Inter 11px bold', () {
      const style = ProAudioTypography.sectionHeader;
      expect(style.fontFamily, 'Inter');
      expect(style.fontSize, 11);
      expect(style.fontWeight, FontWeight.w700);
    });

    test('controlLabel uses Inter 10px', () {
      const style = ProAudioTypography.controlLabel;
      expect(style.fontFamily, 'Inter');
      expect(style.fontSize, 10);
      expect(style.fontWeight, FontWeight.w500);
    });

    test('valueLarge uses JetBrains Mono 18px', () {
      const style = ProAudioTypography.valueLarge;
      expect(style.fontFamily, 'JetBrains Mono');
      expect(style.fontSize, 18);
      expect(style.fontWeight, FontWeight.w600);
    });
  });

  group('ProAudioSpacing', () {
    test('controlGap is 2dp', () {
      expect(ProAudioSpacing.controlGap, 2.0);
    });

    test('sectionGap is 8dp', () {
      expect(ProAudioSpacing.sectionGap, 8.0);
    });

    test('panelPadding is 8dp', () {
      expect(ProAudioSpacing.panelPadding, 8.0);
    });

    test('panelRadius is 2dp', () {
      expect(ProAudioSpacing.panelRadius, 2.0);
    });

    test('nodeRadius is 7dp', () {
      expect(ProAudioSpacing.nodeRadius, 7.0);
    });
  });
}
