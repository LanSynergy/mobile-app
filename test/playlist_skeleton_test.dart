import 'package:aetherfin/widgets/skeletons/playlist_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('PlaylistSkeleton renders without exception', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PlaylistSkeleton())),
    );
    expect(find.byType(PlaylistSkeleton), findsOneWidget);
  });
}
