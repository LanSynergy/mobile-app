import 'package:aetherfin/widgets/skeletons/lyrics_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('LyricsSkeleton renders without exception', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LyricsSkeleton())),
    );
    expect(find.byType(LyricsSkeleton), findsOneWidget);
  });
}
