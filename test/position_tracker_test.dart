import 'dart:async';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import 'package:aetherfin/core/audio/position_tracker.dart';
import 'helpers/fake_player.dart';

void main() {
  setUpAll(() {
    registerFallbackValue(Duration.zero);
    registerFallbackValue(Device.auto);
    registerFallbackValue(Loop.off);
    registerFallbackValue(Gapless.weak);
    registerFallbackValue(SpectrumSettings.defaults);
    registerFallbackValue(Media(''));
  });

  group('AfPositionTracker', () {
    late MockPlayer player;
    late StreamControllers ctrls;
    late List<Duration> emittedPositions;
    late StreamSubscription<Duration> subscription;

    setUp(() {
      final fixture = createMockPlayer();
      player = fixture.player;
      ctrls = fixture.ctrls;
      emittedPositions = <Duration>[];
    });

    tearDown(() async {
      await subscription.cancel();
      ctrls.dispose();
    });

    test('frame-skip gate filters emissions within 500ms delta', () {
      fakeAsync((async) {
        final shouldAdvance = false;
        final tracker = AfPositionTracker(
          player: player,
          shouldAdvancePosition: () => shouldAdvance,
        );

        subscription = tracker.positionStream.listen(emittedPositions.add);
        tracker.start();

        // 1. Initial trigger: seek forces emission of 1.0s
        tracker.onSeek(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(emittedPositions, [const Duration(seconds: 1)]);
        emittedPositions.clear();

        // Mock raw properties for subsequent ticks
        // Tick 1 (+500ms): raw pos is 1200ms. Delta is 200ms (< 500ms frame skip delta), so it gets skipped.
        when(() => player.getRawProperty('time-pos')).thenAnswer((_) async => '1.2');
        async.elapse(const Duration(milliseconds: 500));
        async.flushMicrotasks();
        expect(emittedPositions, isEmpty);

        // Tick 2 (+1000ms): raw pos is 1600ms. Delta from last emitted (1000ms) is 600ms (>= 500ms), so it gets emitted.
        when(() => player.getRawProperty('time-pos')).thenAnswer((_) async => '1.6');
        async.elapse(const Duration(milliseconds: 500));
        async.flushMicrotasks();
        expect(emittedPositions, [const Duration(milliseconds: 1600)]);

        tracker.stop();
      });
    });

    test('onSeek, onTrackChanged, and onStop force emit bypassing frame-skip gate', () {
      fakeAsync((async) {
        final tracker = AfPositionTracker(
          player: player,
          shouldAdvancePosition: () => false,
        );

        subscription = tracker.positionStream.listen(emittedPositions.add);

        // 1. onSeek forces emission
        tracker.onSeek(const Duration(milliseconds: 100));
        async.flushMicrotasks();
        expect(emittedPositions, [const Duration(milliseconds: 100)]);
        emittedPositions.clear();

        // 2. onTrackChanged forces emission of zero
        tracker.onTrackChanged();
        async.flushMicrotasks();
        expect(emittedPositions, [Duration.zero]);
        emittedPositions.clear();

        // 3. onStop forces emission of zero
        tracker.onStop();
        async.flushMicrotasks();
        expect(emittedPositions, [Duration.zero]);
      });
    });

    test('isSeeking flag resets after 300ms seek reset timer', () {
      fakeAsync((async) {
        final tracker = AfPositionTracker(
          player: player,
          shouldAdvancePosition: () => false,
        );

        subscription = tracker.positionStream.listen(emittedPositions.add);

        expect(tracker.isSeeking, isFalse);
        tracker.onSeek(const Duration(seconds: 5));
        expect(tracker.isSeeking, isTrue);

        // Elapse 150ms: still seeking
        async.elapse(const Duration(milliseconds: 150));
        async.flushMicrotasks();
        expect(tracker.isSeeking, isTrue);

        // Elapse another 150ms: 300ms total, seeking resets to false
        async.elapse(const Duration(milliseconds: 150));
        async.flushMicrotasks();
        expect(tracker.isSeeking, isFalse);
      });
    });

    test('stale raw position detection triggers fallback extrapolation', () {
      fakeAsync((async) {
        final tracker = AfPositionTracker(
          player: player,
          shouldAdvancePosition: () => true,
        );

        // Mock state to return playing = true, duration = 10s, rate = 1.0
        when(() => player.state).thenReturn(
          const PlayerState(playing: true, duration: Duration(seconds: 10), rate: 1.0),
        );

        subscription = tracker.positionStream.listen(emittedPositions.add);
        tracker.start();

        // Tick 1: Raw position is 1.0s. First time seen.
        when(() => player.getRawProperty('time-pos')).thenAnswer((_) async => '1.0');
        async.elapse(const Duration(milliseconds: 500));
        async.flushMicrotasks();
        expect(tracker.lastKnownPosition, const Duration(seconds: 1));
        emittedPositions.clear();

        // Tick 2: Raw position remains 1.0s (stale tick 1)
        async.elapse(const Duration(milliseconds: 500));
        async.flushMicrotasks();
        expect(tracker.lastKnownPosition, const Duration(seconds: 1));

        // Tick 3: Raw position remains 1.0s (stale tick 2)
        async.elapse(const Duration(milliseconds: 500));
        async.flushMicrotasks();

        // Tick 4: Raw position remains 1.0s (stale tick 3)
        async.elapse(const Duration(milliseconds: 500));
        async.flushMicrotasks();

        // Tick 5: Raw position remains 1.0s (stale tick 4 -> triggers stale detection)
        // Now it should switch to extrapolation. Last known position was 1.0s at Tick 1.
        // It starts extrapolating from Tick 5.
        async.elapse(const Duration(milliseconds: 500));
        async.flushMicrotasks();

        // Let's verify it starts extrapolating.
        // If we elapse more time, lastKnownPosition should increase.
        final lastPosBeforeExtra = tracker.lastKnownPosition;
        async.elapse(const Duration(milliseconds: 500));
        async.flushMicrotasks();
        expect(tracker.lastKnownPosition, greaterThan(lastPosBeforeExtra));

        tracker.stop();
      });
    });

    test('extrapolation correctly scales with playback rate and caps at duration', () {
      fakeAsync((async) {
        final tracker = AfPositionTracker(
          player: player,
          shouldAdvancePosition: () => true,
        );

        // 1. Double speed (rate = 2.0), duration = 5s
        when(() => player.state).thenReturn(
          const PlayerState(playing: true, duration: Duration(seconds: 5), rate: 2.0),
        );

        subscription = tracker.positionStream.listen(emittedPositions.add);
        tracker.start();

        tracker.updateKnownPosition(const Duration(seconds: 2));

        // Stale raw positions so it extrapolates
        when(() => player.getRawProperty('time-pos')).thenAnswer((_) async => '2.0');

        // Tick 1
        async.elapse(const Duration(milliseconds: 500));
        async.flushMicrotasks();
        // Tick 2
        async.elapse(const Duration(milliseconds: 500));
        async.flushMicrotasks();
        // Tick 3
        async.elapse(const Duration(milliseconds: 500));
        async.flushMicrotasks();
        // Tick 4
        async.elapse(const Duration(milliseconds: 500));
        async.flushMicrotasks();

        // Tick 5 (+500ms): stale detection triggers fallback extrapolation.
        // Extrapolated: 2s + (500ms * 2.0) = 3s.
        async.elapse(const Duration(milliseconds: 500));
        async.flushMicrotasks();
        expect(tracker.lastKnownPosition, const Duration(seconds: 3));

        // Tick 6 (+500ms): 3s + (500ms * 2.0) = 4s.
        async.elapse(const Duration(milliseconds: 500));
        async.flushMicrotasks();
        expect(tracker.lastKnownPosition, const Duration(seconds: 4));

        // Tick 7 (+500ms): 4s + (500ms * 2.0) = 5s (capped at duration).
        async.elapse(const Duration(milliseconds: 500));
        async.flushMicrotasks();
        expect(tracker.lastKnownPosition, const Duration(seconds: 5));

        // Tick 8 (+500ms): stays at 5s.
        async.elapse(const Duration(milliseconds: 500));
        async.flushMicrotasks();
        expect(tracker.lastKnownPosition, const Duration(seconds: 5));

        tracker.stop();
      });
    });

    test('getRawPosition and getRawDuration return zero on null, non-parsable, or exceptions', () async {
      final tracker = AfPositionTracker(
        player: player,
        shouldAdvancePosition: () => false,
      );

      subscription = tracker.positionStream.listen(emittedPositions.add);

      // Null values
      when(() => player.getRawProperty('time-pos')).thenAnswer((_) async => null);
      when(() => player.getRawProperty('duration')).thenAnswer((_) async => null);
      expect(await tracker.getRawPosition(), Duration.zero);
      expect(await tracker.getRawDuration(), Duration.zero);

      // Non-parsable / garbage values
      when(() => player.getRawProperty('time-pos')).thenAnswer((_) async => 'garbage');
      when(() => player.getRawProperty('duration')).thenAnswer((_) async => 'invalid');
      expect(await tracker.getRawPosition(), Duration.zero);
      expect(await tracker.getRawDuration(), Duration.zero);

      // Negative values
      when(() => player.getRawProperty('time-pos')).thenAnswer((_) async => '-1.5');
      when(() => player.getRawProperty('duration')).thenAnswer((_) async => '-10');
      expect(await tracker.getRawPosition(), Duration.zero);
      expect(await tracker.getRawDuration(), Duration.zero);

      // Exceptions
      when(() => player.getRawProperty('time-pos')).thenThrow(Exception('mpv crash'));
      when(() => player.getRawProperty('duration')).thenThrow(Exception('mpv crash'));
      expect(await tracker.getRawPosition(), Duration.zero);
      expect(await tracker.getRawDuration(), Duration.zero);
    });

    test('pollAndEmitPosition bails early when seeking or loading queue', () {
      fakeAsync((async) {
        var isLoading = false;
        final tracker = AfPositionTracker(
          player: player,
          shouldAdvancePosition: () => false,
          isLoadingQueue: () => isLoading,
        );

        subscription = tracker.positionStream.listen(emittedPositions.add);
        tracker.start();

        // 1. Mock raw position to return 5s
        when(() => player.getRawProperty('time-pos')).thenAnswer((_) async => '5.0');

        // Elapse 400ms so that the next periodic timer tick (at T=500ms) falls within the seek reset window (300ms)
        async.elapse(const Duration(milliseconds: 400));
        async.flushMicrotasks();

        // Call onSeek at T=400ms. Seek reset timer is scheduled for T=700ms.
        tracker.onSeek(const Duration(seconds: 2));
        async.flushMicrotasks();
        emittedPositions.clear();

        // Elapse 100ms (T=500ms). The 500ms periodic timer fires.
        async.elapse(const Duration(milliseconds: 100));
        async.flushMicrotasks();
        
        // At T=500ms, isSeeking is still true, so it must bail early and not emit 5.0s.
        expect(emittedPositions, isNot(contains(const Duration(seconds: 5))));

        // Elapse another 500ms (T=1000ms).
        // At T=700ms, seek reset timer fires, resetting isSeeking to false.
        // At T=1000ms, periodic timer fires again. Since isSeeking is false, it polls and emits 5.0s.
        async.elapse(const Duration(milliseconds: 500));
        async.flushMicrotasks();
        expect(emittedPositions, contains(const Duration(seconds: 5)));

        // 2. When loading queue, it emits zero and resets
        isLoading = true;
        emittedPositions.clear();

        async.elapse(const Duration(milliseconds: 500));
        async.flushMicrotasks();
        expect(tracker.lastKnownPosition, Duration.zero);
        expect(emittedPositions, [Duration.zero]);

        tracker.stop();
      });
    });
  });
}
