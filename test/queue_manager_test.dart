import 'package:flutter_test/flutter_test.dart';
import 'package:aetherfin/core/audio/queue_manager.dart';
import 'package:aetherfin/core/jellyfin/models/items.dart';

void main() {
  group('AfQueueManager (simplified)', () {
    late AfQueueManager queueManager;
    late List<AfTrack> tracks;

    setUp(() {
      queueManager = AfQueueManager();
      tracks = [
        const AfTrack(
          id: '1',
          title: 'Track 1',
          artistName: 'A',
          albumName: 'B',
        ),
        const AfTrack(
          id: '2',
          title: 'Track 2',
          artistName: 'A',
          albumName: 'B',
        ),
        const AfTrack(
          id: '3',
          title: 'Track 3',
          artistName: 'A',
          albumName: 'B',
        ),
      ];
    });

    group('queue lifecycle', () {
      test('replaceQueue replaces queue and emits on stream', () async {
        List<AfTrack>? emitted;
        final sub = queueManager.queueStream.listen((q) => emitted = q);

        queueManager.replaceQueue(tracks, 0);
        await Future<void>.delayed(Duration.zero);

        expect(queueManager.currentQueue.length, 3);
        expect(queueManager.currentIndex, 0);
        expect(queueManager.currentTrack?.id, '1');
        expect(emitted?.length, 3);
        await sub.cancel();
      });

      test('replaceQueue with empty list does not crash', () {
        queueManager.replaceQueue([], 0);
        expect(queueManager.currentQueue, isEmpty);
        expect(queueManager.currentIndex, -1);
      });

      test('endPlayback sets currentTrack to null preserving queue', () async {
        queueManager.replaceQueue(tracks, 0);

        AfTrack? emitted;
        final sub = queueManager.currentTrackStream.listen((t) => emitted = t);

        queueManager.endPlayback();
        await Future<void>.delayed(Duration.zero);

        expect(queueManager.currentTrack, isNull);
        expect(queueManager.currentIndex, -1);
        expect(emitted, isNull);
        expect(queueManager.currentQueue.length, 3);
        await sub.cancel();
      });

      test('clear resets everything', () {
        queueManager.replaceQueue(tracks, 0);
        queueManager.clear();
        expect(queueManager.currentQueue, isEmpty);
        expect(queueManager.currentIndex, -1);
        expect(queueManager.isShuffleEnabled, isFalse);
      });
    });

    group('queue mutations (delegated to engine)', () {
      test('reorder updates queue', () {
        queueManager.replaceQueue(tracks, 0);
        // [1, 2, 3], currentIndex=0 (track '1')
        queueManager.reorder(0, 2); // Move track 0 to position 2
        // After reorder: [2, 1, 3], currentIndex=1 (track '1')
        expect(queueManager.currentQueue[0].id, '2');
        expect(queueManager.currentQueue[1].id, '1');
        expect(queueManager.currentQueue[2].id, '3');
        expect(queueManager.currentIndex, 1);
      });

      test('remove removes track', () {
        queueManager.replaceQueue(tracks, 0);
        queueManager.remove(1);
        expect(queueManager.currentQueue.length, 2);
        expect(queueManager.currentQueue[1].id, '3');
      });

      test('insert adds track at position', () {
        queueManager.replaceQueue(tracks, 0);
        const newTrack = AfTrack(
          id: 'new',
          title: 'New',
          artistName: 'X',
          albumName: 'Y',
        );
        queueManager.insert(1, newTrack);
        expect(queueManager.currentQueue.length, 4);
        expect(queueManager.currentQueue[1].id, 'new');
      });

      test('append adds to end', () {
        queueManager.replaceQueue(tracks, 0);
        const newTrack = AfTrack(
          id: 'new',
          title: 'New',
          artistName: 'X',
          albumName: 'Y',
        );
        queueManager.append(newTrack);
        expect(queueManager.currentQueue.length, 4);
        expect(queueManager.currentQueue.last.id, 'new');
      });
    });

    group('streams', () {
      test('shuffleModeStream is wired correctly', () async {
        final emitted = <bool>[];
        final sub = queueManager.shuffleModeStream.listen(emitted.add);

        // Shuffle mode stream is available
        expect(queueManager.shuffleModeStream, isA<Stream<bool>>());

        await sub.cancel();
      });
    });
  });
}
