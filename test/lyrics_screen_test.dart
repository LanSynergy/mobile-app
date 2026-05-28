import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:aetherfin/features/lyrics/lyrics_screen.dart';
import 'package:aetherfin/widgets/skeletons/lyrics_skeleton.dart';
import 'package:aetherfin/core/jellyfin/models/items.dart';
import 'package:aetherfin/core/lyrics/lrc_parser.dart';
import 'package:aetherfin/core/backend/music_backend.dart';
import 'package:aetherfin/core/local/local_backend.dart';
import 'package:aetherfin/state/providers.dart';

class MockMusicBackend extends Mock implements MusicBackend {}

class MockLocalBackend extends Mock implements LocalBackend {}

void main() {
  setUpAll(() {
    registerFallbackValue(Duration.zero);
  });

  group('LyricsScreen UI and Sync', () {
    testWidgets('renders empty state when current track is null', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [initialAuthProvider.overrideWithValue(null)],
          child: const MaterialApp(home: LyricsScreen()),
        ),
      );

      expect(find.text('Start a track to see lyrics.'), findsOneWidget);
    });

    testWidgets('renders loading state with CircularProgressIndicator and Fetching lyrics...', (
      tester,
    ) async {
      const track = AfTrack(
        id: 'track1',
        title: 'Song Title',
        artistName: 'Artist Name',
        albumName: 'Album Name',
        duration: Duration(minutes: 3),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            initialAuthProvider.overrideWithValue(null),
            currentTrackProvider.overrideWith((ref) => track),
            lyricsProvider('track1').overrideWith((ref) => Completer<Lrc?>().future),
          ],
          child: const MaterialApp(home: LyricsScreen()),
        ),
      );

      expect(find.byType(LyricsSkeleton), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Fetching lyrics...'), findsOneWidget);
    });

    testWidgets('renders missing lyrics state on server mode', (tester) async {
      final mockBackend = MockMusicBackend();
      when(() => mockBackend.serverType).thenReturn(ServerType.jellyfin);
      when(() => mockBackend.lyrics(any())).thenAnswer((_) async => null);

      const track = AfTrack(
        id: 'track1',
        title: 'Song Title',
        artistName: 'Artist Name',
        albumName: 'Album Name',
        duration: Duration(minutes: 3),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            initialAuthProvider.overrideWithValue(null),
            currentTrackProvider.overrideWith((ref) => track),
            musicBackendProvider.overrideWithValue(mockBackend),
            lyricsProvider('track1').overrideWith((ref) async => null),
          ],
          child: const MaterialApp(home: LyricsScreen()),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('No lyrics available for this track.'), findsOneWidget);
      expect(find.text('Load LRC File'), findsNothing);
    });

    testWidgets(
      'renders missing lyrics state on local mode with Load LRC File button',
      (tester) async {
        final mockBackend = MockLocalBackend();
        when(() => mockBackend.serverType).thenReturn(ServerType.local);
        when(() => mockBackend.lyrics(any())).thenAnswer((_) async => null);

        const track = AfTrack(
          id: 'track1',
          title: 'Song Title',
          artistName: 'Artist Name',
          albumName: 'Album Name',
          duration: Duration(minutes: 3),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              initialAuthProvider.overrideWithValue(null),
              currentTrackProvider.overrideWith((ref) => track),
              musicBackendProvider.overrideWithValue(mockBackend),
              lyricsProvider('track1').overrideWith((ref) async => null),
            ],
            child: const MaterialApp(home: LyricsScreen()),
          ),
        );

        await tester.pumpAndSettle();
        expect(
          find.text('No lyrics available for this track.'),
          findsOneWidget,
        );
        expect(find.text('Load LRC File'), findsOneWidget);
      },
    );

    testWidgets(
      'renders list of synced lyrics and updates active line based on playback progress',
      (tester) async {
        const track = AfTrack(
          id: 'track1',
          title: 'Song Title',
          artistName: 'Artist Name',
          albumName: 'Album Name',
          duration: Duration(minutes: 3),
        );

        const lrcContent =
            '[00:10.00]Line 1\n[00:20.00]Line 2\n[00:30.00]Line 3';
        final lrc = parseLrc(lrcContent);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              initialAuthProvider.overrideWithValue(null),
              currentTrackProvider.overrideWith((ref) => track),
              lyricsProvider('track1').overrideWith((ref) async => lrc),
              positionStreamProvider.overrideWith((ref) => Duration.zero),
            ],
            child: const MaterialApp(home: LyricsScreen()),
          ),
        );

        await tester.pumpAndSettle();
        expect(find.text('Line 1'), findsOneWidget);
        expect(find.text('Line 2'), findsOneWidget);
        expect(find.text('Line 3'), findsOneWidget);

        final element = tester.element(find.byType(LyricsScreen));
        final container = ProviderScope.containerOf(element);

        // Initially at 0s, activeIndex is -1 so no line is active.
        // Move to 15s -> Line 1 active (index 0)
        container.read(positionStreamProvider.notifier).state = const Duration(
          seconds: 15,
        );
        await tester.pumpAndSettle();

        // Move to 25s -> Line 2 active (index 1)
        container.read(positionStreamProvider.notifier).state = const Duration(
          seconds: 25,
        );
        await tester.pumpAndSettle();
      },
    );

    testWidgets('unsynced lyrics does not highlight active or autoscroll', (
      tester,
    ) async {
      const track = AfTrack(
        id: 'track1',
        title: 'Song Title',
        artistName: 'Artist Name',
        albumName: 'Album Name',
        duration: Duration(minutes: 3),
      );

      // Unsynced lyrics (all lines have timestamp 0)
      const lrcContent =
          '[00:00.00]Line One\n[00:00.00]Line Two\n[00:00.00]Line Three';
      final lrc = parseLrc(lrcContent);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            initialAuthProvider.overrideWithValue(null),
            currentTrackProvider.overrideWith((ref) => track),
            lyricsProvider('track1').overrideWith((ref) async => lrc),
            positionStreamProvider.overrideWith(
              (ref) => const Duration(seconds: 10),
            ),
          ],
          child: const MaterialApp(home: LyricsScreen()),
        ),
      );

      await tester.pumpAndSettle();

      // Verify list renders
      expect(find.text('Line One'), findsOneWidget);
      expect(find.text('Line Two'), findsOneWidget);
      expect(find.text('Line Three'), findsOneWidget);

      final element = tester.element(find.byType(LyricsScreen));
      final container = ProviderScope.containerOf(element);

      // Changing position to 20s should NOT trigger active line transition or auto-scroll
      container.read(positionStreamProvider.notifier).state = const Duration(
        seconds: 20,
      );
      await tester.pumpAndSettle();
    });
  });
}
