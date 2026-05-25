import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import 'package:aetherfin/core/audio/media_session_bridge.dart';
import 'package:aetherfin/core/audio/player_service.dart';
import 'package:aetherfin/core/jellyfin/models/items.dart';
import 'helpers/fake_player.dart';

class MockMethodChannel extends Mock implements MethodChannel {}

typedef _StateUpdater =
    void Function(PlayerState Function(PlayerState) updater);

({
  AfPlayerService service,
  NativeMediaSessionBridge bridge,
  MockPlayer player,
  StreamControllers ctrls,
  MockMethodChannel channel,
  _StateUpdater updateState,
})
_createFixture() {
  final result = createMockPlayer();
  final player = result.player;
  final ctrls = result.ctrls;
  final channel = MockMethodChannel();

  var mutableState = const PlayerState();
  when(() => player.state).thenAnswer((_) => mutableState);
  void updateState(PlayerState Function(PlayerState) updater) {
    mutableState = updater(mutableState);
  }

  when(() => channel.invokeMethod(any())).thenAnswer((_) async => null);
  when(() => channel.invokeMethod(any(), any())).thenAnswer((_) async => null);
  when(() => channel.setMethodCallHandler(any())).thenAnswer((_) async {});

  final bridge = NativeMediaSessionBridge(channel: channel);
  final service = AfPlayerService.test(player: player, bridge: bridge);

  return (
    service: service,
    bridge: bridge,
    player: player,
    ctrls: ctrls,
    channel: channel,
    updateState: updateState,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Completed handler with 2-track window', () {
    late AfPlayerService service;
    late MockPlayer player;
    late StreamControllers ctrls;
    late _StateUpdater updateState;

    const trackA = AfTrack(
      id: '1',
      title: 'Track A',
      artistName: 'Test Artist',
      albumName: 'Test Album',
    );
    const trackB = AfTrack(
      id: '2',
      title: 'Track B',
      artistName: 'Test Artist',
      albumName: 'Test Album',
    );
    const trackC = AfTrack(
      id: '3',
      title: 'Track C',
      artistName: 'Test Artist',
      albumName: 'Test Album',
    );

    setUpAll(() {
      registerFallbackValue(Duration.zero);
      registerFallbackValue(Device.auto);
      registerFallbackValue(Loop.off);
      registerFallbackValue(Gapless.weak);
      registerFallbackValue(SpectrumSettings.defaults);
      registerFallbackValue(const Media(''));
      registerFallbackValue(<Media>[]);
    });

    setUp(() async {
      final fixture = _createFixture();
      service = fixture.service;
      player = fixture.player;
      ctrls = fixture.ctrls;
      updateState = fixture.updateState;

      // Stub methods called during playback setup
      when(() => player.setAudioDevice(any())).thenAnswer((_) async {});
      when(() => player.setAudioExclusive(any())).thenAnswer((_) async {});
      when(() => player.setAudioSampleRate(any())).thenAnswer((_) async {});
      when(() => player.setPrefetchPlaylist(any())).thenAnswer((_) async {});
      when(() => player.setRate(any())).thenAnswer((_) async {});
      when(() => player.setGapless(any())).thenAnswer((_) async {});
      when(() => player.setLoop(any())).thenAnswer((_) async {});
      when(() => player.setShuffle(any())).thenAnswer((_) async {});

      // Stub mpv player methods
      when(() => player.play()).thenAnswer((_) async {});
      when(() => player.pause()).thenAnswer((_) async {});
      when(() => player.stop()).thenAnswer((_) async {});
      when(() => player.next()).thenAnswer((_) async {});
      when(() => player.previous()).thenAnswer((_) async {});
      when(() => player.seek(any())).thenAnswer((_) async {});
      when(
        () => player.openAll(
          any(),
          index: any(named: 'index'),
          play: any(named: 'play'),
        ),
      ).thenAnswer((_) async {});

      // Populate queue
      await service.playQueue(
        [trackA, trackB, trackC],
        startIndex: 0,
        resolveStreamUrl: (t) => 'https://example.com/${t.id}.flac',
      );

      await Future<void>.delayed(Duration.zero);
    });

    tearDown(() async {
      await service.dispose();
      ctrls.dispose();
    });

    // -----------------------------------------------------------------------
    // Completed handler + skipToNext — both advance engine, no lock needed
    // -----------------------------------------------------------------------
    test(
      'completed handler advances engine; then skipToNext advances again',
      () async {
        expect(service.currentTrack?.id, equals('1'));

        // Fire completed at non-queue-end (index 0 of 3).
        updateState(
          (s) => s.copyWith(playing: true, completed: true, loop: Loop.off),
        );
        ctrls.completed.add(true);
        await Future<void>.delayed(Duration.zero);

        // Handler advanced engine to index 1.
        expect(service.currentTrack?.id, equals('2'));

        // Now skip to next.
        await service.skipToNext();
        expect(service.currentTrack?.id, equals('3'));
        verify(
          () => player.openAll(
            any(),
            index: any(named: 'index'),
            play: any(named: 'play'),
          ),
        ).called(greaterThan(0));
        // No jump() call in 2-track model.
        verifyNever(() => player.jump(any()));
      },
    );

    // -----------------------------------------------------------------------
    // Completed handler + skipToQueueItem — both rebuild window
    // -----------------------------------------------------------------------
    test(
      'completed handler advances engine; then skipToQueueItem jumps',
      () async {
        expect(service.currentTrack?.id, equals('1'));

        // Fire completed at non-queue-end.
        updateState(
          (s) => s.copyWith(playing: true, completed: true, loop: Loop.off),
        );
        ctrls.completed.add(true);
        await Future<void>.delayed(Duration.zero);

        // Handler advanced engine to index 1.
        expect(service.currentTrack?.id, equals('2'));

        // Now skip to queue item 2 (track C).
        clearInteractions(player);
        await service.skipToQueueItem(2);
        expect(service.currentTrack?.id, equals('3'));
        // skipToQueueItem uses _rebuildWindow → openAll, not jump().
        verify(
          () => player.openAll(
            any(),
            index: any(named: 'index'),
            play: any(named: 'play'),
          ),
        ).called(1);
        verifyNever(() => player.jump(any()));
      },
    );

    // -----------------------------------------------------------------------
    // Completed at queue end (loop=off) stops; then play resets
    // -----------------------------------------------------------------------
    test('completed stops at queue end; then play restarts', () async {
      // Start at last track.
      await service.playQueue(
        [trackA, trackB, trackC],
        startIndex: 2,
        resolveStreamUrl: (t) => 'https://example.com/${t.id}.flac',
      );
      await Future<void>.delayed(Duration.zero);
      clearInteractions(player);

      expect(service.currentTrack?.id, equals('3'));

      // Fire completed at queue end.
      updateState(
        (s) => s.copyWith(playing: true, completed: true, loop: Loop.off),
      );
      ctrls.completed.add(true);
      await Future<void>.delayed(Duration.zero);

      // Handler stopped player and ended playback.
      verify(() => player.stop()).called(1);
      expect(service.currentTrack, isNull);

      // Now play — should restart playback.
      clearInteractions(player);
      await service.play();
      verify(() => player.play()).called(1);
    });

    // -----------------------------------------------------------------------
    // Completed handler advances engine; then seek works independently
    // -----------------------------------------------------------------------
    test('completed handler advances engine; seek is independent', () async {
      expect(service.currentTrack?.id, equals('1'));

      // Fire completed at non-queue-end.
      updateState(
        (s) => s.copyWith(playing: true, completed: true, loop: Loop.off),
      );
      ctrls.completed.add(true);
      await Future<void>.delayed(Duration.zero);

      // Handler advanced engine to index 1.
      expect(service.currentTrack?.id, equals('2'));

      // Seek — independent operation, no jump/stop interaction.
      clearInteractions(player);
      await service.seek(const Duration(seconds: 10));
      verify(() => player.seek(const Duration(seconds: 10))).called(1);
    });
  });
}
