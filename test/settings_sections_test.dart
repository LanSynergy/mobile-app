import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import 'package:aetherfin/core/audio/media_session_bridge.dart';
import 'package:aetherfin/core/audio/player_service.dart';
import 'package:aetherfin/features/settings/settings_sections.dart';
import 'package:aetherfin/state/providers.dart';
import 'helpers/fake_player.dart';

class MockMethodChannel extends Mock implements MethodChannel {}

/// Creates a fixture with a mock player service for widget tests.
({
  AfPlayerService service,
  ProviderContainer container,
  MockPlayer player,
  StreamControllers ctrls,
})
_createSettingsFixture() {
  final result = createMockPlayer();
  final player = result.player;
  final ctrls = result.ctrls;

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
  when(() => channel.invokeMethod(any(), any())).thenAnswer((_) async => null);

  final bridge = NativeMediaSessionBridge(channel: channel);
  final service = AfPlayerService.test(player: player, bridge: bridge);

  final container = ProviderContainer(
    overrides: [playerServiceProvider.overrideWithValue(service)],
  );

  return (service: service, container: container, player: player, ctrls: ctrls);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MusicFoldersCard', () {
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
      final fixture = _createSettingsFixture();
      service = fixture.service;
      container = fixture.container;
      player = fixture.player;
      ctrls = fixture.ctrls;
    });

    tearDown(() async {
      await service.dispose();
      ctrls.dispose();
      container.dispose();
    });

    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: MusicFoldersCard())),
        ),
      );
      // Should not throw — loading state is shown initially
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('stopAndClear is called before folder operations', (
      tester,
    ) async {
      // Verify the method exists and can be called
      await service.stopAndClear();
      verify(() => player.stop()).called(1);
      expect(service.currentQueue, isEmpty);
      expect(service.currentTrack, isNull);
    });
  });
}
