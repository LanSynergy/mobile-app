import 'package:aetherfin/widgets/skeletons/album_card_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AlbumCardSkeleton renders block + 2 bars', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AlbumCardSkeleton())),
    );
    expect(find.byType(AlbumCardSkeleton), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
  });
}
