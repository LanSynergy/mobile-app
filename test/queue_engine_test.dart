import 'package:flutter_test/flutter_test.dart';
import 'package:aetherfin/core/audio/queue_engine.dart';
import 'package:aetherfin/core/jellyfin/models/items.dart';

void main() {
  group('AfQueueEngine', () {
    late AfQueueEngine engine;
    late List<AfTrack> tracks;

    setUp(() {
      engine = AfQueueEngine();
      tracks = [
        const AfTrack(id: '1', title: 'Track 1', artistName: 'A', albumName: 'B'),
        const AfTrack(id: '2', title: 'Track 2', artistName: 'A', albumName: 'B'),
        const AfTrack(id: '3', title: 'Track 3', artistName: 'A', albumName: 'B'),
        const AfTrack(id: '4', title: 'Track 4', artistName: 'A', albumName: 'B'),
        const AfTrack(id: '5', title: 'Track 5', artistName: 'A', albumName: 'B'),
      ];
    });

    group('replaceAll', () {
      test('replaces queue and sets current index', () {
        engine.replaceAll(tracks, 2);
        expect(engine.length, 5);
        expect(engine.currentIndex, 2);
        expect(engine.currentTrack?.id, '3');
        expect(engine.playbackEnded, isFalse);
        expect(engine.isShuffleEnabled, isFalse);
        expect(engine.windowStart, 2);
      });

      test('clamps start index out of bounds', () {
        engine.replaceAll(tracks, -1);
        expect(engine.currentIndex, 0);
        engine.replaceAll(tracks, 100);
        expect(engine.currentIndex, 4);
      });

      test('handles empty tracks', () {
        engine.replaceAll([], 0);
        expect(engine.isEmpty, isTrue);
        expect(engine.currentIndex, -1);
      });
    });

    group('shuffle', () {
      test('shuffle on creates index mapping', () {
        engine.replaceAll(tracks, 0);
        engine.setShuffle(true);
        expect(engine.isShuffleEnabled, isTrue);
        // Current track should still be track 1 (index 0 after mapping)
        expect(engine.currentTrack?.id, '1');
        // All 5 tracks should be present in the mapping
        final seen = <String>{};
        for (var i = 0; i < 5; i++) {
          seen.add(engine.trackAt(i).id);
        }
        expect(seen, equals({'1', '2', '3', '4', '5'}));
      });

      test('shuffle off clears mapping', () {
        engine.replaceAll(tracks, 0);
        engine.setShuffle(true);
        expect(engine.isShuffleEnabled, isTrue);
        engine.setShuffle(false);
        expect(engine.isShuffleEnabled, isFalse);
      });

      test('double shuffle on is no-op', () {
        engine.replaceAll(tracks, 0);
        engine.setShuffle(true);
        engine.setShuffle(true); // no-op
        expect(engine.isShuffleEnabled, isTrue);
      });

      test('shuffle preserves current track position', () {
        engine.replaceAll(tracks, 2);
        engine.setShuffle(true);
        // trackAt(0) should be the current track (id='3')
        expect(engine.trackAt(0).id, '3');
      });

      test('physicalIndex and logicalIndex roundtrip', () {
        engine.replaceAll(tracks, 0);
        engine.setShuffle(true);
        // Verify the mapping is consistent
        for (var i = 0; i < 5; i++) {
          final phys = engine.physicalIndex(i);
          final log = engine.logicalIndex(phys);
          expect(log, i);
        }
      });
    });

    group('track transitions', () {
      test('advanceIndex moves forward', () {
        engine.replaceAll(tracks, 1);
        expect(engine.advanceIndex(), 2);
        expect(engine.currentTrack?.id, '3');
      });

      test('advanceIndex stops at end', () {
        engine.replaceAll(tracks, 4);
        expect(engine.advanceIndex(), 4);
      });

      test('retreatIndex moves backward', () {
        engine.replaceAll(tracks, 2);
        expect(engine.retreatIndex(), 1);
        expect(engine.currentTrack?.id, '2');
      });

      test('retreatIndex stops at start', () {
        engine.replaceAll(tracks, 0);
        expect(engine.retreatIndex(), 0);
      });

      test('jumpTo moves to exact index', () {
        engine.replaceAll(tracks, 0);
        engine.jumpTo(3);
        expect(engine.currentIndex, 3);
        expect(engine.windowStart, 3);
      });

      test('jumpTo clamps out of bounds', () {
        engine.replaceAll(tracks, 0);
        engine.jumpTo(100);
        expect(engine.currentIndex, 4);
      });

      test('isAtQueueEnd is correct', () {
        engine.replaceAll(tracks, 3);
        expect(engine.isAtQueueEnd, isFalse);
        engine.advanceIndex();
        expect(engine.isAtQueueEnd, isTrue);
      });

      test('nextTrack returns correct track', () {
        engine.replaceAll(tracks, 2);
        expect(engine.nextTrack?.id, '4');
      });

      test('nextTrack is null at end', () {
        engine.replaceAll(tracks, 4);
        expect(engine.nextTrack, isNull);
      });

      test('nextNextTrack returns track at windowStart + 2', () {
        engine.replaceAll(tracks, 2);
        // windowStart = 2, windowStart + 2 = 4
        expect(engine.nextNextTrack?.id, '5');
      });

      test('nextNextTrack is null near end', () {
        engine.replaceAll(tracks, 3);
        expect(engine.nextNextTrack, isNull);
      });
    });

    group('queue mutations', () {
      test('remove removes track and adjusts indices', () {
        engine.replaceAll(tracks, 2);
        engine.remove(0);
        expect(engine.length, 4);
        // currentIndex was 2, now should be 1 (shifted)
        expect(engine.currentIndex, 1);
        expect(engine.currentTrack?.id, '3');
      });

      test('remove before windowStart shifts windowStart', () {
        engine.replaceAll(tracks, 3);
        expect(engine.windowStart, 3);
        engine.remove(1);
        expect(engine.windowStart, 2);
      });

      test('canRemove returns false for current index', () {
        engine.replaceAll(tracks, 2);
        expect(engine.canRemove(2), isFalse);
        expect(engine.canRemove(1), isTrue);
        expect(engine.canRemove(0), isTrue);
      });

      test('insert inserts track and adjusts currentIndex', () {
        engine.replaceAll(tracks, 1);
        const newTrack = AfTrack(id: 'new', title: 'New', artistName: 'X', albumName: 'Y');
        engine.insert(3, newTrack);
        expect(engine.length, 6);
        expect(engine.tracks[3].id, 'new');
        // currentIndex was 1, insert at 3 > 1 → currentIndex unchanged
        expect(engine.currentIndex, 1);
      });

      test('insert before currentIndex increments it', () {
        engine.replaceAll(tracks, 2);
        const newTrack = AfTrack(id: 'new', title: 'New', artistName: 'X', albumName: 'Y');
        engine.insert(0, newTrack);
        expect(engine.currentIndex, 3);
        expect(engine.windowStart, 3);
      });

      test('append adds to end', () {
        engine.replaceAll(tracks, 0);
        const newTrack = AfTrack(id: 'new', title: 'New', artistName: 'X', albumName: 'Y');
        engine.append(newTrack);
        expect(engine.length, 6);
        expect(engine.tracks.last.id, 'new');
      });

      test('reorder adjusts indices correctly', () {
        engine.replaceAll(tracks, 2);
        engine.reorder(0, 3); // Move track 0 to position 3
        // After reorder: [2, 3, 1, 4, 5], currentIndex adjusted to 1 (track '3')
        expect(engine.tracks[0].id, '2');
        expect(engine.tracks[2].id, '1');
        expect(engine.currentIndex, 1);
      });
    });

    group('endPlayback and clear', () {
      test('endPlayback sets index to -1', () {
        engine.replaceAll(tracks, 2);
        engine.endPlayback();
        expect(engine.currentIndex, -1);
        expect(engine.currentTrack, isNull);
        expect(engine.playbackEnded, isTrue);
        expect(engine.length, 5); // queue preserved
      });

      test('clear resets all state', () {
        engine.replaceAll(tracks, 2);
        engine.setShuffle(true);
        engine.clear();
        expect(engine.isEmpty, isTrue);
        expect(engine.currentIndex, -1);
        expect(engine.isShuffleEnabled, isFalse);
        expect(engine.playbackEnded, isFalse);
      });
    });

    group('window tracking', () {
      test('advanceWindow increments windowStart', () {
        engine.replaceAll(tracks, 2);
        expect(engine.windowStart, 2);
        engine.advanceWindow();
        expect(engine.windowStart, 3);
        expect(engine.windowSlot0?.id, '4');
      });

      test('slotToReplace returns opposite slot', () {
        expect(engine.slotToReplace(0), 1);
        expect(engine.slotToReplace(1), 0);
      });
    });
  });
}
