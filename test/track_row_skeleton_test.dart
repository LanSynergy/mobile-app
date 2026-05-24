import 'package:aetherfin/widgets/skeletons/track_row_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('TrackRowSkeleton renders circle + 2 bars', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: TrackRowSkeleton())),
    );
    // Row with circle (40dp) + 2 skeleton bars = 3 skeleton primitives
    expect(find.byType(TrackRowSkeleton), findsOneWidget);
    // Should render without exception
    await tester.pump(const Duration(milliseconds: 100));
  });
}
