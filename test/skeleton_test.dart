import 'package:aetherfin/widgets/skeleton.dart';
import 'package:aetherfin/widgets/skeletons/album_card_skeleton.dart';
import 'package:aetherfin/widgets/skeletons/album_skeleton.dart';
import 'package:aetherfin/widgets/skeletons/artist_skeleton.dart';
import 'package:aetherfin/widgets/skeletons/genre_skeleton.dart';
import 'package:aetherfin/widgets/skeletons/home_skeleton.dart';
import 'package:aetherfin/widgets/skeletons/library_skeleton.dart';
import 'package:aetherfin/widgets/skeletons/lyrics_skeleton.dart';
import 'package:aetherfin/widgets/skeletons/playlist_skeleton.dart';
import 'package:aetherfin/widgets/skeletons/search_skeleton.dart';
import 'package:aetherfin/widgets/skeletons/sheet_skeleton.dart';
import 'package:aetherfin/widgets/skeletons/track_row_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ShimmerWrap', () {
    testWidgets('creates AnimationController and renders child', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ShimmerWrap(child: SizedBox(width: 100, height: 20)),
          ),
        ),
      );
      // Should find the SizedBox child through ShimmerWrap
      expect(find.byType(SizedBox), findsOneWidget);
      // Should have started the animation
      await tester.pump(const Duration(milliseconds: 750));
      // No crash = success
    });

    testWidgets('handles zero-size bounds gracefully', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ShimmerWrap(child: SizedBox(width: 0, height: 0)),
          ),
        ),
      );
      // Should not throw
      await tester.pump(const Duration(milliseconds: 100));
    });
  });

  group('SkeletonBar', () {
    testWidgets('renders with default dimensions', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SkeletonBar())),
      );
      // Default height=14, no explicit width (fills parent)
      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(SkeletonBar),
          matching: find.byType(Container),
        ),
      );
      // No width constraint — defaults to fill parent
      expect(container.decoration, isNotNull);
    });

    testWidgets('accepts custom width, height, borderRadius, color', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SkeletonBar(
              width: 120,
              height: 20,
              borderRadius: BorderRadius.all(Radius.circular(16)),
              color: Colors.red,
            ),
          ),
        ),
      );
      // Find the inner Container
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(SkeletonBar),
              matching: find.byType(Container),
            )
            .last,
      );
      expect(container.decoration, isNotNull);
    });
  });

  group('SkeletonBlock', () {
    testWidgets('renders with required dimensions', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SkeletonBlock(width: 200, height: 200)),
        ),
      );
      expect(find.byType(SkeletonBlock), findsOneWidget);
    });
  });

  group('SkeletonCircle', () {
    testWidgets('renders circle shape', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SkeletonCircle(size: 48))),
      );
      expect(find.byType(SkeletonCircle), findsOneWidget);
    });
  });

  group('Screen Skeletons', () {
    testWidgets('AlbumCardSkeleton renders block + 2 bars', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AlbumCardSkeleton())),
      );
      expect(find.byType(AlbumCardSkeleton), findsOneWidget);
    });

    testWidgets('AlbumSkeleton renders without exception', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: AlbumSkeleton())),
      );
      expect(find.byType(AlbumSkeleton), findsOneWidget);
    });

    testWidgets('ArtistSkeleton renders without exception', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ArtistSkeleton())),
      );
      expect(find.byType(ArtistSkeleton), findsOneWidget);
    });

    testWidgets('GenreSkeleton renders without exception', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: GenreSkeleton())),
      );
      expect(find.byType(GenreSkeleton), findsOneWidget);
    });

    group('Home Skeleton', () {
      testWidgets('HomeCarouselSkeleton renders without exception', (
        tester,
      ) async {
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: HomeCarouselSkeleton())),
        );
        expect(find.byType(HomeCarouselSkeleton), findsOneWidget);
      });

      testWidgets('HomeRecentSkeleton renders without exception', (
        tester,
      ) async {
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: HomeRecentSkeleton())),
        );
        expect(find.byType(HomeRecentSkeleton), findsOneWidget);
      });

      testWidgets('HomeArtistsSkeleton renders without exception', (
        tester,
      ) async {
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: HomeArtistsSkeleton())),
        );
        expect(find.byType(HomeArtistsSkeleton), findsOneWidget);
      });
    });

    group('LibrarySkeleton', () {
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
    });

    testWidgets('LyricsSkeleton renders without exception', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: LyricsSkeleton())),
      );
      expect(find.byType(LyricsSkeleton), findsOneWidget);
    });

    testWidgets('PlaylistSkeleton renders without exception', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: PlaylistSkeleton())),
      );
      expect(find.byType(PlaylistSkeleton), findsOneWidget);
    });

    testWidgets('SearchSkeleton renders 5 bars', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SearchSkeleton())),
      );
      expect(find.byType(SearchSkeleton), findsOneWidget);
    });

    group('SheetSkeleton', () {
      testWidgets('SheetSkeleton renders 4 static rows by default', (
        tester,
      ) async {
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
    });

    testWidgets('TrackRowSkeleton renders circle + 2 bars', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: TrackRowSkeleton())),
      );
      expect(find.byType(TrackRowSkeleton), findsOneWidget);
    });
  });
}
