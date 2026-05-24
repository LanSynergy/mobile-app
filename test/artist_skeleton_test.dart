import 'package:aetherfin/widgets/skeletons/artist_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ArtistSkeleton renders without exception', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ArtistSkeleton())),
    );
    expect(find.byType(ArtistSkeleton), findsOneWidget);
  });
}
