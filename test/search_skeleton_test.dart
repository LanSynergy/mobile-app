import 'package:aetherfin/widgets/skeletons/search_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('SearchSkeleton renders 5 bars', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SearchSkeleton())),
    );
    expect(find.byType(SearchSkeleton), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
  });
}
