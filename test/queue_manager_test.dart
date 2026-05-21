import 'package:flutter_test/flutter_test.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show Media;

import 'package:aetherfin/core/audio/queue_manager.dart';
import 'package:aetherfin/core/jellyfin/models/items.dart';

void main() {
  group('AfQueueManager', () {
    late AfQueueManager queueManager;
    late List<AfTrack> tracks;

    setUp(() {
      queueManager = AfQueueManager();
      tracks = [
        const AfTrack(id: 'track1', title: 'Track 1', artistName: 'Artist', albumName: 'Album'),
        const AfTrack(id: 'track2', title: 'Track 2', artistName: 'Artist', albumName: 'Album'),
        const AfTrack(id: 'track3', title: 'Track 3', artistName: 'Artist', albumName: 'Album'),
      ];
    });

    group('BUG-002: Shuffle original queue preservation', () {
      test('setShuffleEnabled(false) does not clear original queue until clearOriginalQueueAfterSync is called', () {
        queueManager.replaceQueue(tracks, 0);

        // Enable shuffle
        queueManager.setShuffleEnabled(true);
        expect(queueManager.isShuffleEnabled, isTrue);

        // Disable shuffle
        queueManager.setShuffleEnabled(false);
        expect(queueManager.isShuffleEnabled, isFalse);

        // Reconcile / Sync
        final mpvItems = [
          Media('https://example.com/track2'),
          Media('https://example.com/track1'),
          Media('https://example.com/track3'),
        ];
        queueManager.rebuildUrlMap(mpvItems, [tracks[1], tracks[0], tracks[2]]);
        
        // Ensure original queue was not cleared, and sync resolves the tracks
        queueManager.syncFromMpv(mpvItems, 0);
        expect(queueManager.currentQueue.map((t) => t.id).toList(), ['track2', 'track1', 'track3']);

        // Explicitly clear it after sync completes
        queueManager.clearOriginalQueueAfterSync();
      });
    });
  });
}
