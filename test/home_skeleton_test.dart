import 'package:aetherfin/widgets/skeletons/home_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('HomeCarouselSkeleton renders without exception', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: HomeCarouselSkeleton())),
    );
    expect(find.byType(HomeCarouselSkeleton), findsOneWidget);
  });

  testWidgets('HomeRecentSkeleton renders without exception', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: HomeRecentSkeleton())),
    );
    expect(find.byType(HomeRecentSkeleton), findsOneWidget);
  });

  testWidgets('HomeArtistsSkeleton renders without exception', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: HomeArtistsSkeleton())),
    );
    expect(find.byType(HomeArtistsSkeleton), findsOneWidget);
  });
}
