import 'package:aetherfin/widgets/skeletons/genre_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('GenreSkeleton renders without exception', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: GenreSkeleton())),
    );
    expect(find.byType(GenreSkeleton), findsOneWidget);
  });
}
