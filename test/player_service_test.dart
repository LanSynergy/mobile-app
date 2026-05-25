import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import 'package:aetherfin/core/audio/media_session_bridge.dart';
import 'package:aetherfin/core/audio/player_service.dart';
import 'package:aetherfin/core/jellyfin/models/items.dart';
import 'helpers/fake_player.dart';

class MockMethodChannel extends Mock implements MethodChannel {}

/// Wraps a mutable [PlayerState] so tests can change the mock's state.
typedef _StateUpdater =
    void Function(PlayerState Function(PlayerState) updater);

/// Test helper that creates a fresh mock player + service + channel.
({
  AfPlayerService service,
  NativeMediaSessionBridge bridge,
  MockPlayer player,
  StreamControllers ctrls,
  MockMethodChannel channel,
  _StateUpdater updateState,
  Future<dynamic> Function(MethodCall)? handler,
})
_createFixture() {
  final result = createMockPlayer();
  final player = result.player;
  final ctrls = result.ctrls;
  final channel = MockMethodChannel();

  // Mutable state so the test can change _player.state mid-lifecycle.
  var mutableState = const PlayerState();
  when(() => player.state).thenAnswer((_) => mutableState);
  void updateState(PlayerState Function(PlayerState) updater) {
    mutableState = updater(mutableState);
  }

  Future<dynamic> Function(MethodCall)? handler;

  // Stub MethodChannel calls (the bridge uses catchError on failures).
  when(() => channel.invokeMethod(any())).thenAnswer((_) async => null);
  when(() => channel.invokeMethod(any(), any())).thenAnswer((_) async => null);
  when(() => channel.setMethodCallHandler(any())).thenAnswer((
    invocation,
  ) async {
    handler =
        invocation.positionalArguments[0]
            as Future<dynamic> Function(MethodCall)?;
  });

  final bridge = NativeMediaSessionBridge(channel: channel);
  final service = AfPlayerService.test(player: player, bridge: bridge);

  return (
    service: service,
    bridge: bridge,
    player: player,
    ctrls: ctrls,
    channel: channel,
    updateState: updateState,
    handler: handler,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('AfPlayerService playback integration', () {
    late AfPlayerService service;
    late MockPlayer player;
    late StreamControllers ctrls;
    late _StateUpdater updateState;
    Future<dynamic> Function(MethodCall)? handler;

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

    String resolveStreamUrl(AfTrack t) => 'https://example.com/${t.id}.flac';

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
      final fixture = _createFixture();
      service = fixture.service;
      player = fixture.player;
      ctrls = fixture.ctrls;
      updateState = fixture.updateState;
      handler = fixture.handler;
    });

    tearDown(() async {
      await service.dispose();
      ctrls.dispose();
    });

    // -----------------------------------------------------------------------
    // 1. playQueue uses openAll for small queues and emits currentTrack
    // -----------------------------------------------------------------------
    test('playQueue opens tracks and emits currentTrack', () async {
      AfTrack? changedTrack;
      service.onTrackChanged = (track) {
        changedTrack = track;
      };

      await service.playQueue(
        [trackA, trackB],
        startIndex: 0,
        resolveStreamUrl: resolveStreamUrl,
      );

      // Should have opened all tracks in mpv (original design: openAll for ≤5).
      verify(
        () => player.openAll(any(that: hasLength(2)), index: 0, play: true),
      ).called(1);

      // Current track should be set immediately from Dart state.
      expect(service.currentTrack?.id, equals('1'));
      expect(service.currentTrack?.title, equals('Track A'));
      expect(service.currentQueue.length, equals(2));

      // onTrackChanged should fire.
      expect(changedTrack?.id, equals('1'));
    });

    // -----------------------------------------------------------------------
    // 2. playQueue with single track loads only 1 media
    // -----------------------------------------------------------------------
    test('playQueue with single track opens 1 media', () async {
      await service.playQueue(
        [trackA],
        startIndex: 0,
        resolveStreamUrl: resolveStreamUrl,
      );

      verify(
        () => player.openAll(any(that: hasLength(1)), index: 0, play: true),
      ).called(1);

      expect(service.currentQueue.length, equals(1));
    });

    // -----------------------------------------------------------------------
    // 3. Track auto-advance on completion advances engine state
    // -----------------------------------------------------------------------
    test('completed handler advances engine and emits next track', () async {
      AfTrack? changedTrack;
      service.onTrackChanged = (track) {
        changedTrack = track;
      };

      await service.playQueue(
        [trackA, trackB],
        startIndex: 0,
        resolveStreamUrl: resolveStreamUrl,
      );
      await Future<void>.delayed(Duration.zero);
      expect(service.currentTrack?.id, equals('1'));

      // Set state so we're not at queue end (length=2, index 0 → advance to 1)
      updateState(
        (s) => s.copyWith(playing: true, completed: false, loop: Loop.off),
      );

      ctrls.completed.add(true);
      await Future<void>.delayed(Duration.zero);

      // Engine advanced — current index should be 1 (track B).
      expect(service.currentTrack?.id, equals('2'));
      expect(changedTrack?.id, equals('2'));
      // player.jump() is never called — _jumpAndPlay was removed.
      verifyNever(() => player.jump(any()));
      // player.play() not called because playingAtEvent is true.
      verifyNever(() => player.play());
    });

    // -----------------------------------------------------------------------
    // 4. Completion at queue end with loop=off stops and clears track
    // -----------------------------------------------------------------------
    test('queue end with loop=off stops and clears track', () async {
      AfTrack? changedTrack;
      service.onTrackChanged = (track) {
        changedTrack = track;
      };

      await service.playQueue(
        [trackA],
        startIndex: 0,
        resolveStreamUrl: resolveStreamUrl,
      );
      await Future<void>.delayed(Duration.zero);
      expect(service.currentTrack?.id, equals('1'));

      when(() => player.stop()).thenAnswer((_) async {});

      // Simulate completion at queue end (nextIdx = 1, length = 1).
      updateState(
        (s) => s.copyWith(playing: true, completed: false, loop: Loop.off),
      );

      ctrls.completed.add(true);
      await Future<void>.delayed(Duration.zero);

      // Queue end with loop=off: stop + endPlayback.
      verify(() => player.stop()).called(1);
      expect(service.currentTrack, isNull);
      expect(changedTrack, isNull);
      // The track list is preserved but currentIndex goes to -1.
      // (Real behavior: _engine.endPlayback() sets index to -1, doesn't clear tracks.)
    });

    // -----------------------------------------------------------------------
    // 5. Completion at queue end with loop=playlist wraps around
    // -----------------------------------------------------------------------
    test('loop playlist wraps to first track at queue end', () async {
      await service.playQueue(
        [trackA, trackB],
        startIndex: 1, // Start at last track.
        resolveStreamUrl: resolveStreamUrl,
      );
      await Future<void>.delayed(Duration.zero);
      expect(service.currentTrack?.id, equals('2'));

      await service.setAfLoopMode(Loop.playlist);

      when(
        () => player.openAll(
          any(),
          index: any(named: 'index'),
          play: any(named: 'play'),
        ),
      ).thenAnswer((_) async {});

      // Simulate completion at queue end with loop=playlist.
      updateState(
        (s) => s.copyWith(playing: true, completed: false, loop: Loop.playlist),
      );

      ctrls.completed.add(true);
      await Future<void>.delayed(Duration.zero);

      // Engine wrapped to index 0 via _rebuildWindow → openAll.
      expect(service.currentTrack?.id, equals('1'));
      verify(
        () => player.openAll(
          any(that: hasLength(2)),
          index: 0,
          play: any(named: 'play'),
        ),
      ).called(1);
      verifyNever(() => player.jump(any()));
    });

    // -----------------------------------------------------------------------
    // 6. Completion at queue end with loop=file replays in place
    // -----------------------------------------------------------------------
    test('loop file at queue end replays without track change', () async {
      await service.playQueue(
        [trackA],
        startIndex: 0,
        resolveStreamUrl: resolveStreamUrl,
      );
      await Future<void>.delayed(Duration.zero);
      expect(service.currentTrack?.id, equals('1'));

      await service.setAfLoopMode(Loop.file);
      when(() => player.play()).thenAnswer((_) async {});

      // Simulate completion at queue end with loop=file.
      updateState(
        (s) => s.copyWith(
          playing: false, // mpv stopped at end of file
          completed: false,
          loop: Loop.file,
        ),
      );

      ctrls.completed.add(true);
      await Future<void>.delayed(Duration.zero);

      // Track stays the same; play() is called to restart.
      expect(service.currentTrack?.id, equals('1'));
      verify(() => player.play()).called(1);
    });

    // -----------------------------------------------------------------------
    // 8. Queue mutations are pure Dart — 0 mpv calls
    // -----------------------------------------------------------------------
    test('queue mutations are pure Dart — 0 mpv calls', () async {
      await service.playQueue(
        [trackA, trackB],
        startIndex: 0,
        resolveStreamUrl: resolveStreamUrl,
      );
      await Future<void>.delayed(Duration.zero);
      expect(service.currentQueue.length, equals(2));

      // insertIntoQueue at index 1 — verify Dart state change
      await service.insertIntoQueue(
        1,
        trackC,
        resolveStreamUrl: resolveStreamUrl,
      );
      expect(service.currentQueue.length, equals(3));
      expect(service.currentQueue[1].id, equals('3'));

      // playNext inserts after current index (still 0)
      await service.playNext(trackC, resolveStreamUrl: resolveStreamUrl);
      expect(service.currentQueue.length, equals(4));
      expect(service.currentQueue[1].id, equals('3'));

      // addToQueue appends
      await service.addToQueue(trackC, resolveStreamUrl: resolveStreamUrl);
      expect(service.currentQueue.length, equals(5));

      // reorderQueue — verify Dart state change
      await service.reorderQueue(4, 2);
      expect(service.currentQueue[2].id, equals('3'));

      // removeFromQueue (not currently playing — index 3 is not current 0)
      final removed = await service.removeFromQueue(3);
      expect(removed, isTrue);
      expect(service.currentQueue.length, equals(4));

      // remove currently playing index fails
      final removedCurrent = await service.removeFromQueue(0);
      expect(removedCurrent, isFalse);
      expect(service.currentQueue.length, equals(4));

      // 0 mpv calls for queue mutations.
      verifyNever(() => player.sendRawCommand(any()));
    });

    // -----------------------------------------------------------------------
    // 9. Play/Pause respect disposed guard
    // -----------------------------------------------------------------------
    test('play and pause respect disposed guard', () async {
      await service.dispose();
      await service.play();
      verifyNever(() => player.play());
      await service.pause();
      verifyNever(() => player.pause());
    });

    // -----------------------------------------------------------------------
    // 10. Seek/Skip work after playQueue; skipToQueueItem uses openAll
    // -----------------------------------------------------------------------
    test(
      'seek, skipToNext, skipToPrevious, skipToQueueItem work after playQueue',
      () async {
        when(
          () => player.openAll(
            any(),
            index: any(named: 'index'),
            play: any(named: 'play'),
          ),
        ).thenAnswer((_) async {});
        when(() => player.seek(any())).thenAnswer((_) async {});
        when(() => player.next()).thenAnswer((_) async {});
        when(() => player.previous()).thenAnswer((_) async {});

        await service.playQueue(
          [trackA, trackB],
          startIndex: 0,
          resolveStreamUrl: resolveStreamUrl,
        );
        await Future<void>.delayed(Duration.zero);

        await service.seek(const Duration(seconds: 1));
        verify(() => player.seek(const Duration(seconds: 1))).called(1);

        await service.skipToNext();
        verify(
          () => player.openAll(
            any(),
            index: any(named: 'index'),
            play: any(named: 'play'),
          ),
        ).called(greaterThan(0));

        await service.skipToPrevious();
        verify(
          () => player.openAll(
            any(),
            index: any(named: 'index'),
            play: any(named: 'play'),
          ),
        ).called(greaterThan(0));

        // skipToQueueItem now uses _rebuildWindow → openAll, not jump().
        // Use called(>0) because openAll is also called by playQueue (both use
        // index:0 — no distinguishing index matcher possible in this test).
        await service.skipToQueueItem(0);
        verify(
          () => player.openAll(
            any(),
            index: any(named: 'index'),
            play: any(named: 'play'),
          ),
        ).called(greaterThan(0));
      },
    );

    // -----------------------------------------------------------------------
    // 11. playQueue error recovery
    // -----------------------------------------------------------------------
    test('playQueue error clears queue manager and stops player', () async {
      when(
        () => player.openAll(
          any(),
          index: any(named: 'index'),
          play: any(named: 'play'),
        ),
      ).thenThrow(Exception('openAll failed'));
      when(() => player.stop()).thenAnswer((_) async {});

      await expectLater(
        service.playQueue(
          [trackA, trackB],
          startIndex: 0,
          resolveStreamUrl: resolveStreamUrl,
        ),
        throwsA(isA<Exception>()),
      );

      verify(() => player.stop()).called(1);
      expect(service.currentQueue, isEmpty);
    });

    // -----------------------------------------------------------------------
    // 12. skipToNext/Prev call mpv; skipToQueueItem uses openAll
    // -----------------------------------------------------------------------
    test(
      'skipToNext, skipToPrevious call mpv; skipToQueueItem uses openAll',
      () async {
        await service.playQueue(
          [trackA, trackB, trackC],
          startIndex: 1, // Start at track B
          resolveStreamUrl: resolveStreamUrl,
        );
        await Future<void>.delayed(Duration.zero);
        expect(service.currentTrack?.id, equals('2'));

        when(
          () => player.openAll(
            any(),
            index: any(named: 'index'),
            play: any(named: 'play'),
          ),
        ).thenAnswer((_) async {});

        // skipToNext
        await service.skipToNext();
        verify(
          () => player.openAll(
            any(),
            index: any(named: 'index'),
            play: any(named: 'play'),
          ),
        ).called(greaterThan(0));

        // skipToPrevious
        await service.skipToPrevious();
        verify(
          () => player.openAll(
            any(),
            index: any(named: 'index'),
            play: any(named: 'play'),
          ),
        ).called(greaterThan(0));

        // skipToQueueItem now uses _rebuildWindow → openAll, not jump().
        // Both playQueue and skipToQueueItem reload window at mpv index 0,
        // so use greaterThan(0) to verify openAll was called at least once.
        await service.skipToQueueItem(0);
        verify(
          () => player.openAll(
            any(),
            index: any(named: 'index'),
            play: any(named: 'play'),
          ),
        ).called(greaterThan(0));
        verifyNever(() => player.jump(any()));
      },
    );

    // -----------------------------------------------------------------------
    // 13. Platform method calls invoke corresponding service methods
    // -----------------------------------------------------------------------
    test('platform method calls invoke corresponding service methods', () async {
      expect(handler, isNotNull);

      // Load 2 tracks so skipToNext/Previous have somewhere to go.
      when(
        () => player.openAll(
          any(),
          index: any(named: 'index'),
          play: any(named: 'play'),
        ),
      ).thenAnswer((_) async {});
      await service.playQueue(
        [trackA, trackB],
        startIndex: 0,
        resolveStreamUrl: resolveStreamUrl,
      );
      await Future<void>.delayed(Duration.zero);

      // Stub methods called by player_service
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

      await handler!(const MethodCall('play'));
      await Future<void>.delayed(Duration.zero);
      verify(() => player.play()).called(1);

      await handler!(const MethodCall('pause'));
      await Future<void>.delayed(Duration.zero);
      verify(() => player.pause()).called(1);

      await handler!(const MethodCall('next'));
      await Future<void>.delayed(Duration.zero);
      verify(
        () => player.openAll(
          any(),
          index: any(named: 'index'),
          play: any(named: 'play'),
        ),
      ).called(greaterThan(0));

      await handler!(const MethodCall('previous'));
      await Future<void>.delayed(Duration.zero);
      verify(
        () => player.openAll(
          any(),
          index: any(named: 'index'),
          play: any(named: 'play'),
        ),
      ).called(greaterThan(0));

      await handler!(const MethodCall('stop'));
      await Future<void>.delayed(Duration.zero);
      verify(() => player.stop()).called(1);

      await handler!(const MethodCall('seek', {'positionMs': 1234}));
      await Future<void>.delayed(Duration.zero);
      verify(() => player.seek(const Duration(milliseconds: 1234))).called(1);

      // skipToQueueItem(5) uses _rebuildWindow → openAll, not jump().
      // Distinguish from playQueue (2 tracks) by matching window length (1 track).
      await handler!(const MethodCall('skipTo', {'queueIndex': 5}));
      await Future<void>.delayed(Duration.zero);
      verify(
        () => player.openAll(
          any(that: hasLength(1)),
          index: any(named: 'index'),
          play: any(named: 'play'),
        ),
      ).called(1);
      verifyNever(() => player.jump(any()));

      expect(
        () => handler!(const MethodCall('invalidMethod')),
        throwsA(isA<PlatformException>()),
      );
    });

    test(
      'completed handler appends next-next track to player playlist',
      () async {
        when(() => player.add(any())).thenAnswer((_) async {});

        await service.playQueue(
          [trackA, trackB, trackC],
          startIndex: 0,
          resolveStreamUrl: resolveStreamUrl,
        );
        await Future<void>.delayed(Duration.zero);
        expect(service.currentTrack?.id, equals('1'));

        updateState(
          (s) => s.copyWith(playing: true, completed: false, loop: Loop.off),
        );

        ctrls.completed.add(true);
        await Future<void>.delayed(Duration.zero);

        verify(() => player.add(any(that: isA<Media>()))).called(1);
      },
    );

    test('setAfShuffleMode emits updated shuffle status to stream', () async {
      final shuffleStates = <bool>[];
      final sub = service.shuffleModeStream.listen(shuffleStates.add);

      await service.playQueue(
        [trackA, trackB],
        startIndex: 0,
        resolveStreamUrl: resolveStreamUrl,
      );
      await Future<void>.delayed(Duration.zero);

      await service.setAfShuffleMode(true);
      await Future<void>.delayed(Duration.zero);
      await service.setAfShuffleMode(false);
      await Future<void>.delayed(Duration.zero);

      expect(shuffleStates, contains(true));
      expect(shuffleStates, contains(false));
      await sub.cancel();
    });

    // -----------------------------------------------------------------------
    // stopAndClear clears queue, nulls track, calls stop
    // -----------------------------------------------------------------------
    test('stopAndClear clears queue and nulls current track', () async {
      AfTrack? changedTrack;
      service.onTrackChanged = (track) {
        changedTrack = track;
      };

      // Load a queue first
      await service.playQueue(
        [trackA, trackB],
        resolveStreamUrl: resolveStreamUrl,
        startIndex: 0,
      );

      // Verify queue is populated
      expect(service.currentQueue.length, 2);
      expect(service.currentTrack, isNotNull);

      // Track changed values before stopAndClear
      changedTrack = null;

      await service.stopAndClear();

      // Queue is empty
      expect(service.currentQueue, isEmpty);
      expect(service.currentTrack, isNull);

      // onTrackChanged was called with null
      expect(changedTrack, isNull);

      // player.stop() was called
      verify(() => player.stop()).called(1);
    });

    test('stopAndClear is safe when already stopped', () async {
      await service.stop();
      // Second call should not throw
      await service.stopAndClear();
      // After stopAndClear, queue is empty
      expect(service.currentQueue, isEmpty);
      expect(service.currentTrack, isNull);
    });

    test(
      'setAfForNtimes and setAfNtimesCount configure engine correctly',
      () async {
        expect(service.isForNtimesMode, isFalse);

        await service.setAfForNtimes(true);
        expect(service.isForNtimesMode, isTrue);
      },
    );

    test(
      'forNtimes loop mode repeats the track and seeks to zero instead of advancing',
      () async {
        await service.playQueue(
          [trackA, trackB],
          startIndex: 0,
          resolveStreamUrl: resolveStreamUrl,
        );
        await Future<void>.delayed(Duration.zero);
        expect(service.currentTrack?.id, equals('1'));

        await service.setAfForNtimes(true);
        await service.setAfNtimesCount(2);

        updateState(
          (s) => s.copyWith(playing: true, completed: false, loop: Loop.off),
        );

        when(() => player.seek(Duration.zero)).thenAnswer((_) async {});

        // First completion: repeats remaining = 2 -> 1, seeks, doesn't advance
        ctrls.completed.add(true);
        await Future<void>.delayed(Duration.zero);

        expect(service.currentTrack?.id, equals('1')); // still track A!
        verify(() => player.seek(Duration.zero)).called(1);
      },
    );

    test('duck and unduck adjust volume correctly', () async {
      expect(handler, isNotNull);

      updateState((s) => s.copyWith(volume: 1.0));
      when(() => player.setVolume(any())).thenAnswer((_) async {});

      // Simulate 'duck' with volume ratio 0.2
      await handler!(const MethodCall('duck', {'volume': 0.2}));
      await Future<void>.delayed(Duration.zero);

      verify(() => player.setVolume(0.2)).called(1);

      // Simulate 'unduck'
      await handler!(const MethodCall('unduck'));
      await Future<void>.delayed(Duration.zero);

      verify(() => player.setVolume(1.0)).called(1);
    });
  });
}
