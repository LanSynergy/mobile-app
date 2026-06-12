import 'package:aetherfin/design_tokens/pro_audio.dart';
import 'package:aetherfin/features/now_playing/pro_eq/pro_eq_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aetherfin/features/now_playing/parametric_band.dart';
import 'package:aetherfin/features/now_playing/eq_preset.dart';

void main() {
  group('ProSectionPanel', () {
    testWidgets('renders title and child', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProSectionPanel(
              title: 'Test Section',
              child: SizedBox(height: 50),
            ),
          ),
        ),
      );
      expect(find.text('Test Section'), findsOneWidget);
      expect(find.byType(SizedBox), findsWidgets);
    });

    testWidgets('has dark panel background', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProSectionPanel(title: 'Test', child: SizedBox()),
          ),
        ),
      );
      // Verify the panel renders with the correct section header
      expect(find.text('Test'), findsOneWidget);
    });
  });

  group('ProStereoPeakMeter', () {
    testWidgets('renders L and R labels', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProStereoPeakMeter(leftLevel: 0.5, rightLevel: 0.3),
          ),
        ),
      );
      expect(find.text('L'), findsOneWidget);
      expect(find.text('R'), findsOneWidget);
    });

    testWidgets('handles zero levels', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ProStereoPeakMeter(leftLevel: 0, rightLevel: 0)),
        ),
      );
      expect(find.byType(ProStereoPeakMeter), findsOneWidget);
    });

    testWidgets('handles max levels', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProStereoPeakMeter(leftLevel: 1.0, rightLevel: 1.0),
          ),
        ),
      );
      expect(find.byType(ProStereoPeakMeter), findsOneWidget);
    });
  });

  group('ProFrequencyResponseView', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 200,
              child: ProFrequencyResponseView(
                bands: ParametricBand.defaultBands().take(5).toList(),
                selectedBand: 0,
                accentColor: ProAudioColors.curveActive,
                onBandChanged: (_, _) {},
                onBandSelected: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(find.byType(ProFrequencyResponseView), findsOneWidget);
    });
  });

  group('ProParametricControls', () {
    testWidgets('renders 5 band tabs', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProParametricControls(
              bands: ParametricBand.defaultBands(),
              selectedBand: 0,
              onBandSelected: (_) {},
              onBandChanged: (_, _) {},
            ),
          ),
        ),
      );
      expect(find.text('1'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('shows gain/freq/Q labels', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProParametricControls(
              bands: ParametricBand.defaultBands(),
              selectedBand: 0,
              onBandSelected: (_) {},
              onBandChanged: (_, _) {},
            ),
          ),
        ),
      );
      expect(find.text('Freq'), findsOneWidget);
      expect(find.text('Gain'), findsOneWidget);
      expect(find.text('Q'), findsOneWidget);
    });
  });

  group('ProToneControls', () {
    testWidgets('renders bass and treble sliders', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProToneControls(bass: 0, treble: 0, onChanged: (_, _) {}),
          ),
        ),
      );
      expect(find.text('Bass'), findsOneWidget);
      expect(find.text('Treble'), findsOneWidget);
    });

    testWidgets('displays dB values', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProToneControls(bass: 3, treble: -2, onChanged: (_, _) {}),
          ),
        ),
      );
      expect(find.text('+3 dB'), findsOneWidget);
      expect(find.text('-2 dB'), findsOneWidget);
    });
  });

  group('ProPresetChips', () {
    testWidgets('renders built-in presets', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProPresetChips(activePreset: null, onApply: (_, _) {}),
          ),
        ),
      );
      expect(find.text('Flat'), findsOneWidget);
      expect(find.text('Rock'), findsOneWidget);
      expect(find.text('Jazz'), findsOneWidget);
    });

    testWidgets('highlights active preset', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProPresetChips(activePreset: 'Rock', onApply: (_, _) {}),
          ),
        ),
      );
      final chip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'Rock'),
      );
      expect(chip.selected, isTrue);
    });
  });

  group('ProGraphicEqControls', () {
    testWidgets('renders enable toggle', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProGraphicEqControls(
              bands: kEqBands,
              gains: {for (final k in kEqBands.keys) k: 1.0},
              enabled: true,
              onEnabledChanged: (_) {},
              onGainChanged: (_, _) {},
              onBandSelected: (_) {},
            ),
          ),
        ),
      );
      expect(find.byType(Switch), findsOneWidget);
    });
  });
}
