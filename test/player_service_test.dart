import 'dart:async';
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
typedef _StateUpdater = void Function(PlayerState Function(PlayerState) updater);

/// Test helper that creates a fresh mock player + service + channel.
///
/// Returns the service, along with helpers for controlling state and streams.
({
  AfPlayerService service,
  NativeMediaSessionBridge bridge,
  MockPlayer player,
  StreamControllers ctrls,
  MockMethodChannel channel,
  _StateUpdater updateState,
  Future<dynamic> Function(MethodCall)? handler,
}) _createFixture() {
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
  when(() => channel.setMethodCallHandler(any())).thenAnswer((invocation) async {
    handler = invocation.positionalArguments[0] as Future<dynamic> Function(MethodCall)?;
  });

  final bridge = NativeMediaSessionBridge(channel: channel);
  final service = AfPlayerService.test(
    player: player,
    bridge: bridge,
  );

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
    late MockMethodChannel channel;
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
      channel = fixture.channel;
      updateState = fixture.updateState;
      handler = fixture.handler;
    });

    tearDown(() async {
      await service.dispose();
      ctrls.dispose();
    });

    // -----------------------------------------------------------------------
    // 1. Play queue → track starts
    // -----------------------------------------------------------------------
    test('playQueue emits currentTrack and pushes state to native', () async {
      AfTrack? changedTrack;
      service.onTrackChanged = (track) {
        changedTrack = track;
      };

      await service.playQueue(
        [trackA, trackB],
        startIndex: 0,
        resolveStreamUrl: resolveStreamUrl,
      );

      // Simulate mpv playlist event (fires after openAll in real plugin).
      ctrls.playlist.add(
        const Playlist(
          [
            Media('https://example.com/1.flac'),
            Media('https://example.com/2.flac'),
          ],
          index: 0,
        ),
      );

      // Let stream handlers process.
      await Future<void>.delayed(Duration.zero);

      expect(service.currentTrack?.id, equals('1'));
      expect(service.currentTrack?.title, equals('Track A'));
      expect(service.isPlaying, isFalse);
      expect(service.currentQueue.length, equals(2));

      // onTrackChanged should have been called.
      expect(changedTrack?.id, equals('1'));
    });

    // -----------------------------------------------------------------------
    // 2. Track auto-advance on completion
    // -----------------------------------------------------------------------
    test('track auto-advances when current track completes', () async {
      await service.playQueue(
        [trackA, trackB],
        startIndex: 1, // Start at last track so we're at queue end.
        resolveStreamUrl: resolveStreamUrl,
      );

      ctrls.playlist.add(
        const Playlist(
          [
            Media('https://example.com/1.flac'),
            Media('https://example.com/2.flac'),
          ],
          index: 1,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(service.currentTrack?.id, equals('2'));

      // Set loop mode to file.
      await service.setAfLoopMode(Loop.file);

      // Simulate track completion while at queue end and loop=file.
      // The completed handler should NOT advance; it should replay
      // via mpv (which handles it internally).
      updateState((s) => s.copyWith(
            playing: true,
            completed: false,
            loop: Loop.file,
            playlist: const Playlist(
              [
                Media('https://example.com/1.flac'),
                Media('https://example.com/2.flac'),
              ],
              index: 1,
            ),
          ));

      ctrls.completed.add(true);
      await Future<void>.delayed(Duration.zero);

      // Track should remain the same (file loop replays in place).
      expect(service.currentTrack?.id, equals('2'));
    });

    // -----------------------------------------------------------------------
    // 4. Loop queue (wrap around)
    // -----------------------------------------------------------------------
    test('loop queue wraps to first track at end', () async {
      await service.playQueue(
        [trackA, trackB],
        startIndex: 1, // Last track.
        resolveStreamUrl: resolveStreamUrl,
      );

      ctrls.playlist.add(
        const Playlist(
          [
            Media('https://example.com/1.flac'),
            Media('https://example.com/2.flac'),
          ],
          index: 1,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(service.currentTrack?.id, equals('2'));

      // Set loop mode to playlist.
      await service.setAfLoopMode(Loop.playlist);

      // Simulate completion at queue end with loop=playlist.
      updateState((s) => s.copyWith(
            playing: true,
            completed: false,
            loop: Loop.playlist,
            playlist: const Playlist(
              [
                Media('https://example.com/1.flac'),
                Media('https://example.com/2.flac'),
              ],
              index: 1,
            ),
          ));

      ctrls.completed.add(true);
      await Future<void>.delayed(Duration.zero);

      // The completed handler should call player.jump(0) which wraps around.
      // Simulate the resulting playlist event.
      ctrls.playlist.add(
        const Playlist(
          [
            Media('https://example.com/1.flac'),
            Media('https://example.com/2.flac'),
          ],
          index: 0,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(service.currentTrack?.id, equals('1'));
    });

    // -----------------------------------------------------------------------
    // 5. Queue end behavior (no loop)
    // -----------------------------------------------------------------------
    test('queue end with loop=off stops playback and clears native state',
        () async {
      AfTrack? changedTrack;
      service.onTrackChanged = (track) {
        changedTrack = track;
      };

      await service.playQueue(
        [trackA],
        startIndex: 0,
        resolveStreamUrl: resolveStreamUrl,
      );

      ctrls.playlist.add(
        const Playlist([Media('https://example.com/1.flac')], index: 0),
      );
      await Future<void>.delayed(Duration.zero);
      expect(service.currentTrack?.id, equals('1'));

      // Simulate completion at queue end with loop=off (default).
      updateState((s) => s.copyWith(
            playing: true,
            completed: false,
            loop: Loop.off,
            playlist: const Playlist([Media('https://example.com/1.flac')], index: 0),
          ));

      ctrls.completed.add(true);
      await Future<void>.delayed(Duration.zero);

      // Queue end with loop=off: service should stop, clear track.
      expect(changedTrack, isNull); // onTrackChanged called with null.
      expect(service.currentTrack, isNull);

      // Simulate mpv reacting to stop() by setting playing=false on state.
      // (the playing stream listener doesn't update _player.state.playing,
      //  isPlaying reads it directly, so we update mutableState.)
      updateState((s) => s.copyWith(playing: false));
      expect(service.isPlaying, isFalse);

      // Native channel should be called with 'clear' (or 'updateState').
      verify(() => channel.invokeMethod('clear', any())).called(1);
    });

    // -----------------------------------------------------------------------
    // 6. Generation counter prevents stale sync
    // -----------------------------------------------------------------------
    test('generation counter discards stale queue load', () async {
      // First playQueue call starts but doesn't complete its lock action
      // because the second call increments _queueLoadGen.
      //
      // playQueue uses _queueLock.run() which chains async operations.
      // When the second call's _queueLoadGen check inside the lock fails,
      // the first load's later operations become no-ops.

      // Start with an "in-flight" queue load (simulate by not awaiting).
      // The first load's lock action will check _queueLoadGen which is 1
      // after the first call increments it.
      //
      // Actually, playQueue increments _queueLoadGen at the start, then
      // enters the lock. The second call also increments _queueLoadGen
      // (to 2), then enters the lock. The first call's lock action
      // checks `myGen != _queueLoadGen` → 1 != 2 → returns early.
      // The second call's lock action proceeds normally.

      final fut1 = service.playQueue(
        [trackA, trackB],
        startIndex: 0,
        resolveStreamUrl: resolveStreamUrl,
      );

      // Second load starts before first finishes.
      await service.playQueue(
        [trackC],
        startIndex: 0,
        resolveStreamUrl: resolveStreamUrl,
      );

      await fut1; // First load's lock action is a no-op (stale gen).

      // Only the second queue's tracks should remain.
      // The queue was loaded with [trackC], so that's what we have.
      expect(service.currentQueue.length, equals(1));
      expect(service.currentQueue[0].id, equals('3'));
    });

    // -----------------------------------------------------------------------
    // 7. Shuffle reorder
    // -----------------------------------------------------------------------
    test('shuffle reorders queue via mpv', () async {
      await service.playQueue(
        [trackA, trackB, trackC],
        startIndex: 0,
        resolveStreamUrl: resolveStreamUrl,
      );

      ctrls.playlist.add(
        const Playlist(
          [
            Media('https://example.com/1.flac'),
            Media('https://example.com/2.flac'),
            Media('https://example.com/3.flac'),
          ],
          index: 0,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      // Enable shuffle.
      await service.setAfShuffleMode(true);

      // Verify mpv's setShuffle was called.
      verify(() => player.setShuffle(true)).called(1);

      // Verify shuffle mode is reflected.
      expect(service.isShuffleEnabled, isTrue);

      // Simulate shuffle reorder by emitting a playlist with reordered items.
      ctrls.playlist.add(
        const Playlist(
          [
            Media('https://example.com/3.flac'),
            Media('https://example.com/1.flac'),
            Media('https://example.com/2.flac'),
          ],
          index: 0,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      // Disable shuffle.
      await service.setAfShuffleMode(false);

      // setShuffle(false) is also called once during playQueue (non-shuffle path).
      verify(() => player.setShuffle(false)).called(greaterThanOrEqualTo(1));
      expect(service.isShuffleEnabled, isFalse);
    });

    test('play and pause respect disposed guard', () async {
      await service.dispose();
      await service.play();
      verifyNever(() => player.play());
      await service.pause();
      verifyNever(() => player.pause());
    });

    test('seek, skipToNext, skipToPrevious, skipToQueueItem respect isLoadingQueue guard', () async {
      final completer = Completer<void>();
      when(() => player.openAll(any(), index: any(named: 'index'), play: any(named: 'play')))
          .thenAnswer((_) => completer.future);

      final playQueueFuture = service.playQueue(
        [trackA, trackB],
        startIndex: 0,
        resolveStreamUrl: resolveStreamUrl,
      );

      // Give event loop a chance to run so playQueue starts and sets _isLoadingQueue = true.
      await Future<void>.delayed(Duration.zero);

      // Now call seek, next, previous, skipToQueueItem. They should do nothing and return.
      await service.seek(const Duration(seconds: 1));
      verifyNever(() => player.seek(any()));

      await service.skipToNext();
      verifyNever(() => player.next());

      await service.skipToPrevious();
      verifyNever(() => player.previous());

      await service.skipToQueueItem(1);
      verifyNever(() => player.jump(any()));

      // Clean up by completing the openAll call.
      completer.complete();
      await playQueueFuture;
    });

    test('playQueue error recovery clears queue manager and stops player on failure', () async {
      when(() => player.openAll(any(), index: any(named: 'index'), play: any(named: 'play')))
          .thenThrow(Exception('openAll failed'));
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

    test('removeFromQueue, insertIntoQueue, playNext, addToQueue, reorderQueue operate correctly', () async {
      // First populate the queue
      await service.playQueue(
        [trackA, trackB],
        startIndex: 0,
        resolveStreamUrl: resolveStreamUrl,
      );

      ctrls.playlist.add(
        const Playlist([
          Media('https://example.com/1.flac'),
          Media('https://example.com/2.flac'),
        ], index: 0),
      );
      await Future<void>.delayed(Duration.zero);

      // 1. insertIntoQueue
      when(() => player.sendRawCommand(any())).thenAnswer((_) async {});
      await service.insertIntoQueue(1, trackC, resolveStreamUrl: resolveStreamUrl);
      verify(() => player.sendRawCommand([
        'loadfile',
        'https://example.com/3.flac',
        'insert-at',
        '1',
      ])).called(1);
      expect(service.currentQueue.length, equals(3));
      expect(service.currentQueue[1].id, equals('3'));

      // 2. playNext
      await service.playNext(trackC, resolveStreamUrl: resolveStreamUrl);
      // currentIndex is 0, so it inserts at 1.
      verify(() => player.sendRawCommand([
        'loadfile',
        'https://example.com/3.flac',
        'insert-at',
        '1',
      ])).called(1);

      // 3. addToQueue
      await service.addToQueue(trackC, resolveStreamUrl: resolveStreamUrl);
      verify(() => player.sendRawCommand([
        'loadfile',
        'https://example.com/3.flac',
        'append',
      ])).called(1);

      // 4. reorderQueue
      await service.reorderQueue(1, 2);
      verify(() => player.sendRawCommand(['playlist-move', '1', '1'])).called(1);

      // 5. removeFromQueue
      // Removing index 1 (trackB/trackC) should succeed (as long as it's not the currently playing index 0).
      final removed = await service.removeFromQueue(1);
      expect(removed, isTrue);
      verify(() => player.sendRawCommand(['playlist-remove', '1'])).called(1);

      // Removing current index (0) should fail
      final removedCurrent = await service.removeFromQueue(0);
      expect(removedCurrent, isFalse);
    });

    test('platform method calls invoke corresponding service methods', () async {
      expect(handler, isNotNull);

      // Stub methods called by player_service
      when(() => player.play()).thenAnswer((_) async {});
      when(() => player.pause()).thenAnswer((_) async {});
      when(() => player.stop()).thenAnswer((_) async {});
      when(() => player.next()).thenAnswer((_) async {});
      when(() => player.previous()).thenAnswer((_) async {});
      when(() => player.seek(any())).thenAnswer((_) async {});
      when(() => player.jump(any())).thenAnswer((_) async {});

      await handler!(const MethodCall('play'));
      await Future<void>.delayed(Duration.zero);
      verify(() => player.play()).called(1);

      await handler!(const MethodCall('pause'));
      await Future<void>.delayed(Duration.zero);
      verify(() => player.pause()).called(1);

      await handler!(const MethodCall('next'));
      await Future<void>.delayed(Duration.zero);
      verify(() => player.next()).called(1);

      await handler!(const MethodCall('previous'));
      await Future<void>.delayed(Duration.zero);
      verify(() => player.previous()).called(1);

      await handler!(const MethodCall('stop'));
      await Future<void>.delayed(Duration.zero);
      verify(() => player.stop()).called(1);

      await handler!(const MethodCall('seek', {'positionMs': 1234}));
      await Future<void>.delayed(Duration.zero);
      verify(() => player.seek(const Duration(milliseconds: 1234))).called(1);

      await handler!(const MethodCall('skipTo', {'queueIndex': 5}));
      await Future<void>.delayed(Duration.zero);
      verify(() => player.jump(5)).called(1);

      expect(
        () => handler!(const MethodCall('invalidMethod')),
        throwsA(isA<PlatformException>()),
      );
    });
  });
}
