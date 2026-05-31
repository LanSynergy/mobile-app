import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import 'package:aetherfin/core/audio/media_session_bridge.dart';
import 'package:aetherfin/core/audio/player_service.dart';
import 'package:aetherfin/core/jellyfin/models/items.dart';
import 'package:aetherfin/widgets/global_mini_player_overlay.dart';
import 'package:aetherfin/widgets/mini_player.dart';
import 'package:aetherfin/state/providers.dart';
import 'package:aetherfin/app/router.dart';
import '../helpers/fake_player.dart';

class MockMethodChannel extends Mock implements MethodChannel {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GlobalMiniPlayerOverlay', () {
    late ProviderContainer container;
    late AfPlayerService service;
    late MockPlayer player;
    late StreamControllers ctrls;

    setUpAll(() {
      registerFallbackValue(Duration.zero);
      registerFallbackValue(Device.auto);
      registerFallbackValue(Loop.off);
      registerFallbackValue(Gapless.weak);
      registerFallbackValue(SpectrumSettings.defaults);
      registerFallbackValue(const Media(''));
      registerFallbackValue(<Media>[]);
    });

    setUp(() {
      final result = createMockPlayer();
      player = result.player;
      ctrls = result.ctrls;

      const mutableState = PlayerState();
      when(() => player.state).thenAnswer((_) => mutableState);
      when(() => player.setAudioDriver(any())).thenAnswer((_) async {});
      when(() => player.setAudioBuffer(any())).thenAnswer((_) async {});
      when(() => player.setAudioDevice(any())).thenAnswer((_) async {});
      when(player.stop).thenAnswer((_) async {});
      when(player.play).thenAnswer((_) async {});
      when(player.pause).thenAnswer((_) async {});
      when(player.dispose).thenAnswer((_) async {});

      final channel = MockMethodChannel();
      when(() => channel.invokeMethod(any())).thenAnswer((_) async => null);
      when(
        () => channel.invokeMethod(any(), any()),
      ).thenAnswer((_) async => null);

      final bridge = NativeMediaSessionBridge(channel: channel);
      service = AfPlayerService.test(player: player, bridge: bridge);

      container = ProviderContainer(
        overrides: [playerServiceProvider.overrideWithValue(service)],
      );
    });

    tearDown(() async {
      await service.dispose();
      ctrls.dispose();
      container.dispose();
    });

    testWidgets('renders miniplayer when active playback is present', (
      tester,
    ) async {
      // Set current track to verify that hasActivePlaybackProvider is true
      container.read(currentTrackProvider.notifier).state = const AfTrack(
        id: 'track-1',
        title: 'Test Title',
        artistName: 'Test Artist',
        albumName: 'Test Album',
        duration: Duration(minutes: 3),
        imageUrl: '',
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: appRouter,
            builder: (context, child) {
              return Stack(
                children: [
                  child ?? const SizedBox.shrink(),
                  const GlobalMiniPlayerOverlay(),
                ],
              );
            },
          ),
        ),
      );

      // Trigger navigation to /home
      appRouter.go('/home');
      await tester.pump(const Duration(milliseconds: 500));

      // Check if MiniPlayer is found
      expect(find.byType(MiniPlayer), findsOneWidget);
    });

    testWidgets(
      'renders miniplayer when active playback is present and navigating to /album/:id',
      (tester) async {
        container.read(currentTrackProvider.notifier).state = const AfTrack(
          id: 'track-1',
          title: 'Test Title',
          artistName: 'Test Artist',
          albumName: 'Test Album',
          duration: Duration(minutes: 3),
          imageUrl: '',
        );

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(
              routerConfig: appRouter,
              builder: (context, child) {
                return Stack(
                  children: [
                    child ?? const SizedBox.shrink(),
                    const GlobalMiniPlayerOverlay(),
                  ],
                );
              },
            ),
          ),
        );

        // Trigger navigation to /album/album-id-123
        appRouter.go('/album/album-id-123');
        await tester.pump(const Duration(milliseconds: 500));

        // Check if MiniPlayer is found on the album screen
        expect(find.byType(MiniPlayer), findsOneWidget);
      },
    );
  });
}
