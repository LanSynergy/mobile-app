import 'package:aetherfin/widgets/skeletons/library_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final mode in LibrarySkeletonMode.values) {
    testWidgets('LibrarySkeleton(${mode.name}) renders without exception', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: LibrarySkeleton(mode: mode)),
        ),
      );
      expect(find.byType(LibrarySkeleton), findsOneWidget);
    });
  }
}
