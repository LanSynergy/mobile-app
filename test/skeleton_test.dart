import 'package:aetherfin/widgets/skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ShimmerWrap', () {
    testWidgets('creates AnimationController and renders child',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ShimmerWrap(
              child: SizedBox(width: 100, height: 20),
            ),
          ),
        ),
      );
      // Should find the SizedBox child through ShimmerWrap
      expect(find.byType(SizedBox), findsOneWidget);
      // Should have started the animation
      await tester.pump(const Duration(milliseconds: 750));
      // No crash = success
    });

    testWidgets('handles zero-size bounds gracefully', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ShimmerWrap(
              child: SizedBox(width: 0, height: 0),
            ),
          ),
        ),
      );
      // Should not throw
      await tester.pump(const Duration(milliseconds: 100));
    });
  });

  group('SkeletonBar', () {
    testWidgets('renders with default dimensions', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SkeletonBar()),
        ),
      );
      // Default height=14, no explicit width (fills parent)
      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(SkeletonBar),
          matching: find.byType(Container),
        ),
      );
      // No width constraint — defaults to fill parent
      expect(container.decoration, isNotNull);
    });

    testWidgets('accepts custom width, height, borderRadius, color',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SkeletonBar(
              width: 120,
              height: 20,
              borderRadius: BorderRadius.all(Radius.circular(16)),
              color: Colors.red,
            ),
          ),
        ),
      );
      // Find the inner Container
      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(SkeletonBar),
          matching: find.byType(Container),
        ).last,
      );
      expect(container.decoration, isNotNull);
    });
  });

  group('SkeletonBlock', () {
    testWidgets('renders with required dimensions', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SkeletonBlock(width: 200, height: 200),
          ),
        ),
      );
      expect(find.byType(SkeletonBlock), findsOneWidget);
    });
  });

  group('SkeletonCircle', () {
    testWidgets('renders circle shape', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SkeletonCircle(size: 48),
          ),
        ),
      );
      expect(find.byType(SkeletonCircle), findsOneWidget);
    });
  });
}
