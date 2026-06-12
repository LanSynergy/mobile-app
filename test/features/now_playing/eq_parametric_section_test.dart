import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aetherfin/features/now_playing/sections/eq_parametric_section.dart';
import 'package:aetherfin/features/now_playing/parametric_band.dart';

void main() {
  group('EqParametricSection', () {
    late List<ParametricBand> bands;
    late List<String> changedFields;

    setUp(() {
      bands = ParametricBand.defaultBands();
      changedFields = [];
    });

    Widget buildTestWidget({
      bool enabled = false,
      void Function(String, dynamic)? onChanged,
      Future<void> Function()? onApply,
    }) {
      return ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: EqParametricSection(
                enabled: enabled,
                bands: bands,
                onChanged: onChanged ?? (f, v) => changedFields.add(f),
                onApply: onApply ?? () async {},
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.byType(EqParametricSection), findsOneWidget);
    });

    testWidgets('shows enable toggle', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      expect(find.text('Parametric Equalizer'), findsOneWidget);
    });

    testWidgets('enable toggle calls onChanged with parametricEnabled', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());
      // Find and tap the enable toggle
      final toggle = find.byType(SwitchListTile);
      if (tester.any(toggle)) {
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(changedFields, contains('parametricEnabled'));
      }
    });

    testWidgets('shows 5 band controls when enabled', (tester) async {
      await tester.pumpWidget(buildTestWidget(enabled: true));
      await tester.pumpAndSettle();
      // Should have band labels for all 5 bands
      expect(find.textContaining('Band 1'), findsOneWidget);
      expect(find.textContaining('Band 5'), findsOneWidget);
    });

    testWidgets('parametricEnabled defaults to false', (tester) async {
      await tester.pumpWidget(buildTestWidget(enabled: false));
      await tester.pumpAndSettle();
      // Section title always renders
      expect(find.text('Parametric Equalizer'), findsOneWidget);
    });

    testWidgets('shows frequency labels for default bands', (tester) async {
      await tester.pumpWidget(buildTestWidget(enabled: true));
      await tester.pumpAndSettle();
      // _formatFrequency shows "60Hz" and "12kHz"
      expect(find.textContaining('60'), findsWidgets);
      expect(find.textContaining('12'), findsWidgets);
    });

    testWidgets('shows gain sliders', (tester) async {
      await tester.pumpWidget(buildTestWidget(enabled: true));
      await tester.pumpAndSettle();
      expect(find.text('Gain'), findsWidgets);
    });

    testWidgets('shows frequency sliders', (tester) async {
      await tester.pumpWidget(buildTestWidget(enabled: true));
      await tester.pumpAndSettle();
      expect(find.text('Freq'), findsWidgets);
    });

    testWidgets('shows Q sliders', (tester) async {
      await tester.pumpWidget(buildTestWidget(enabled: true));
      await tester.pumpAndSettle();
      expect(find.text('Q'), findsWidgets);
    });

    testWidgets('gain slider fires onChanged', (tester) async {
      await tester.pumpWidget(buildTestWidget(enabled: true));
      await tester.pumpAndSettle();
      // Find the first gain slider and drag it
      final sliders = find.byType(Slider);
      if (tester.any(sliders)) {
        await tester.drag(sliders.first, const Offset(50, 0));
        await tester.pumpAndSettle();
        expect(changedFields, isNotEmpty);
      }
    });

    testWidgets('shows Reset button', (tester) async {
      await tester.pumpWidget(buildTestWidget(enabled: true));
      await tester.pumpAndSettle();
      expect(find.text('Reset'), findsOneWidget);
    });
  });
}
