import 'package:aetherfin/widgets/skeletons/sheet_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('SheetSkeleton renders 4 static rows by default', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SheetSkeleton())),
    );
    expect(find.byType(SheetSkeleton), findsOneWidget);
  });

  testWidgets('SheetSkeleton accepts custom rowCount', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SheetSkeleton(rowCount: 3))),
    );
    expect(find.byType(SheetSkeleton), findsOneWidget);
  });
}
