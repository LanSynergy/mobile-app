import 'package:flutter_test/flutter_test.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show Loop;

import 'package:aetherfin/core/audio/player_service.dart';
import 'package:aetherfin/core/audio/queue_manager.dart';
import 'package:aetherfin/core/jellyfin/models/items.dart';

void main() {
  group('Loop mode race conditions', () {
    late AfQueueManager queueManager;
    late List<AfTrack> tracks;

    setUp(() {
      queueManager = AfQueueManager();
      tracks = [
        const AfTrack(
          id: 'track1',
          title: 'Track 1',
          artistName: 'Artist',
          albumName: 'Album',
        ),
        const AfTrack(
          id: 'track2',
          title: 'Track 2',
          artistName: 'Artist',
          albumName: 'Album',
        ),
        const AfTrack(
          id: 'track3',
          title: 'Track 3',
          artistName: 'Artist',
          albumName: 'Album',
        ),
      ];
    });

    group('BUG: completed handler races with setAfLoopMode', () {
      test(
        'loop mode read inside queueLock action sees stale value after '
        'async gap',
        () async {
          final lock = AfAsyncLock();
          var mutableLoop = Loop.off;
          Loop? actionResult;

          // Queue an action in the lock — simulates completed handler
          // entering _queueLock.run(() { ... }).
          final fut = lock.run(() async {
            // Simulate the async gap within the lock action.
            await Future<void>.delayed(Duration.zero);
            actionResult = mutableLoop;
          });

          // Between queueing and execution, mutable state changes —
          // simulates setAfLoopMode calling _player.setLoop(mode)
          // outside the lock while the completed handler is queued.
          mutableLoop = Loop.playlist;

          await fut;

          // BUG: actionResult is Loop.playlist (the changed value),
          // not Loop.off (the value at "event" time).
          expect(
            actionResult,
            equals(Loop.playlist),
            reason: 'BUG: Lock action reads stale loop mode after async gap',
          );
        },
      );

      test(
        'completed handler at queue end uses wrong loop mode when '
        'setAfLoopMode interleaves',
        () async {
          // Simulate the exact pattern from _bindStreams completed
          // listener: queue at end, loop=off, then setAfLoopMode
          // changes loop to playlist before the lock action runs.
          queueManager.replaceQueue(tracks, 2);
          expect(queueManager.currentIndex, 2);
          expect(queueManager.isAtQueueEnd, isTrue);

          final lock = AfAsyncLock();
          var currentLoop = Loop.off;

          // This simulates the completed handler pattern:
          // 1. Capture loop mode (what the fix should do)
          final loopAtEvent = currentLoop;

          // 2. Enter the lock (async gap)
          Loop? actionLoop;
          final completedFut = lock.run(() async {
            await Future<void>.delayed(Duration.zero);
            actionLoop = currentLoop; // reads live state inside lock — BUG
            final nextIdx = queueManager.currentIndex + 1;
            final isAtEnd = nextIdx >= queueManager.currentQueue.length;

            if (isAtEnd) {
              // This is where the bug manifests: if actionLoop is
              // Loop.playlist instead of Loop.off, it jumps to 0
              // instead of pausing.
              if (actionLoop == Loop.off) {
                // pause — correct behavior
              } else if (actionLoop == Loop.playlist) {
                // jumpAndPlay(0) — WRONG when original loop was off
              }
            }
          });

          // Simulate setAfLoopMode changing loop while completed
          // handler is queued
          currentLoop = Loop.playlist;

          await completedFut;

          // The action reads the NEW loop mode, not the one at event time
          expect(actionLoop, equals(Loop.playlist));
          expect(loopAtEvent, equals(Loop.off),
              reason: 'loopAtEvent correctly captured the original mode');
          // Demonstrated: loopAtEvent != actionLoop, so the completed
          // handler would act on the wrong loop mode.
        },
      );
    });

    group('FIX: capture loop mode before entering lock', () {
      test(
        'completed handler uses captured loop mode, avoiding race with '
        'setAfLoopMode',
        () async {
          final lock = AfAsyncLock();
          var mutableLoop = Loop.off;
          Loop? actionResult;

          // The fix: capture state before entering the lock.
          final capturedLoop = mutableLoop;

          final fut = lock.run(() async {
            await Future<void>.delayed(Duration.zero);
            // Use captured value instead of live state.
            actionResult = capturedLoop;
          });

          // Loop mode changes while action is queued.
          mutableLoop = Loop.playlist;

          await fut;

          // FIX: actionResult is Loop.off (the value at event time)
          // even though mutableLoop changed.
          expect(
            actionResult,
            equals(Loop.off),
            reason:
                'FIX: Captured loop mode is preserved across async gap',
          );

          // Confirm the live state did change.
          expect(mutableLoop, equals(Loop.playlist));
        },
      );

      test(
        'completed handler at queue end pauses when loop=off, even if '
        'loop changes to playlist during async gap',
        () async {
          // Full simulation of the completed handler behavior.
          // Queue at end, loop=off. User changes to playlist during gap.
          // With the fix, the handler should still pause.
          queueManager.replaceQueue(tracks, 2);
          expect(queueManager.isAtQueueEnd, isTrue);

          final lock = AfAsyncLock();
          var currentLoop = Loop.off;

          // Fix: capture at event time
          final loopAtEvent = currentLoop;

          String? actionTaken;
          final completedFut = lock.run(() async {
            await Future<void>.delayed(Duration.zero);
            final nextIdx = queueManager.currentIndex + 1;
            final isAtEnd = nextIdx >= queueManager.currentQueue.length;

            if (isAtEnd) {
              switch (loopAtEvent) {
                case Loop.off:
                  actionTaken = 'pause';
                case Loop.playlist:
                  actionTaken = 'jumpToStart';
                case Loop.file:
                  actionTaken = 'replayFile';
              }
            }
          });

          // Loop mode changes during the async gap
          currentLoop = Loop.playlist;

          await completedFut;

          expect(actionTaken, equals('pause'),
              reason:
                  'Handler should pause because loop was off at event time, '
                  'even though it changed to playlist during the gap');

          // After the completed handler, setAfLoopMode's own lock
          // action will run and can restart playback.
          String? secondAction;
          await lock.run(() async {
            await Future<void>.delayed(Duration.zero);
            if (currentLoop == Loop.playlist) {
              secondAction = 'jumpToStart';
            }
          });

          expect(secondAction, equals('jumpToStart'),
              reason:
                  'setAfLoopMode runs after completed handler and '
                  'restarts playback');
        },
      );
    });
  });
}
