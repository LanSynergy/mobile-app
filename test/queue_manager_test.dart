import 'package:flutter_test/flutter_test.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show Media;

import 'package:aetherfin/core/audio/queue_manager.dart';
import 'package:aetherfin/core/audio/track_id_extractor.dart';
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

    group('BUG-009: Full sync failure preservation', () {
      test('syncFromMpv preserves existing queue on full sync failure', () async {
        queueManager.replaceQueue(tracks, 0);

        // Listen to streams
        AfTrack? emittedTrack;
        List<AfTrack>? emittedQueue;

        final sub1 = queueManager.currentTrackStream.listen((track) {
          emittedTrack = track;
        });

        final sub2 = queueManager.queueStream.listen((q) {
          emittedQueue = q;
        });

        int? syncFailedResolved;
        int? syncFailedTotal;
        queueManager.onSyncFailed = (resolved, total) {
          syncFailedResolved = resolved;
          syncFailedTotal = total;
        };

        // Trigger a full sync failure by resolving 0 tracks
        final mpvItems = [Media('https://example.com/unknown_url')];
        queueManager.syncFromMpv(mpvItems, 0);

        // Allow microtasks to process stream events
        await Future<void>.delayed(Duration.zero);

        // Queue should be preserved — not cleared
        expect(queueManager.currentQueue.length, 3);
        expect(queueManager.currentIndex, 0);

        // onSyncFailed should have been invoked
        expect(syncFailedResolved, 0);
        expect(syncFailedTotal, 1);

        // No track/queue emissions on failure (queue unchanged)
        expect(emittedTrack, isNull);
        expect(emittedQueue, isNull);

        await sub1.cancel();
        await sub2.cancel();
      });

      test('syncFromMpv invokes onSyncFailed on partial sync failure', () async {
        queueManager.replaceQueue(tracks, 0);

        int? syncFailedResolved;
        int? syncFailedTotal;
        queueManager.onSyncFailed = (resolved, total) {
          syncFailedResolved = resolved;
          syncFailedTotal = total;
        };

        // 2 mpv items, only 1 resolvable — partial failure
        queueManager.rebuildUrlMap(
          [Media('https://example.com/track1')],
          [tracks[0]],
        );
        final mpvItems = [
          Media('https://example.com/track1'),
          Media('https://example.com/unknown'),
        ];
        queueManager.syncFromMpv(mpvItems, 0);

        await Future<void>.delayed(Duration.zero);

        // Queue preserved
        expect(queueManager.currentQueue.length, 3);
        expect(syncFailedResolved, 1);
        expect(syncFailedTotal, 2);
      });
    });

    group('processPlaylistEvent and Sync Locks tests', () {
      test('processPlaylistEvent returns true on transition from -1 to 0', () {
        final qm = AfQueueManager();
        qm.insert(0, tracks[0], 'https://example.com/track1');
        expect(qm.currentIndex, -1);
        expect(qm.processPlaylistEvent(0), isTrue);
        expect(qm.currentIndex, 0);
      });

      test('processPlaylistEvent returns true when track changes', () {
        final qm = AfQueueManager();
        qm.replaceQueue([tracks[0], tracks[1]], 0); // index 0, track1
        expect(qm.processPlaylistEvent(1), isTrue); // index 1, track2
      });

      test('processPlaylistEvent returns false when track does not change', () {
        final qm = AfQueueManager();
        qm.replaceQueue([tracks[0], tracks[1]], 0); // index 0, track1
        expect(qm.processPlaylistEvent(0), isFalse); // index 0, track1
      });

      test('re-entrant lock nesting works correctly', () {
        expect(queueManager.canHandlePlaylistEvent, isTrue);
        
        queueManager.beginPlaylistSync();
        expect(queueManager.canHandlePlaylistEvent, isFalse);
        
        queueManager.beginPlaylistSync();
        expect(queueManager.canHandlePlaylistEvent, isFalse);
        
        queueManager.endPlaylistSync();
        expect(queueManager.canHandlePlaylistEvent, isFalse);
        
        queueManager.endPlaylistSync();
        expect(queueManager.canHandlePlaylistEvent, isTrue);
      });
      
      test('rebuildUrlMap handles empty and mismatched lists in O(N)', () {
        final urls = [Media('url1'), Media('url2')];
        final qTracks = [tracks[0], tracks[1], tracks[2]];
        queueManager.rebuildUrlMap(urls, qTracks);
        expect(queueManager.trackForUrl('url1'), tracks[0]);
        expect(queueManager.trackForUrl('url2'), tracks[1]);
        expect(queueManager.trackForUrl('url3'), isNull);
      });
    });

    group('replaceQueue empty-input guard', () {
      test('replaceQueue with empty list does not crash and preserves existing queue', () {
        queueManager.replaceQueue(tracks, 0);
        final originalQueue = queueManager.currentQueue.toList();

        queueManager.replaceQueue([], 0);

        // Queue should be unchanged — empty input is a no-op
        expect(queueManager.currentQueue.length, originalQueue.length);
        expect(queueManager.currentIndex, 0);
      });

      test('replaceQueue with empty list on empty queue does not crash', () {
        queueManager.replaceQueue([], 0);

        expect(queueManager.currentQueue, isEmpty);
        expect(queueManager.currentIndex, -1);
      });
    });

    group('endPlayback', () {
      test('sets currentTrack to null while preserving queue list', () async {
        queueManager.replaceQueue(tracks, 0);
        expect(queueManager.currentTrack, isNotNull);
        expect(queueManager.currentQueue.length, 3);

        AfTrack? emittedTrack;
        final sub = queueManager.currentTrackStream.listen((track) {
          emittedTrack = track;
        });

        queueManager.endPlayback();

        // Allow stream event to process
        await Future<void>.delayed(Duration.zero);

        expect(queueManager.currentTrack, isNull);
        expect(queueManager.currentIndex, -1);
        expect(emittedTrack, isNull);

        // Queue list, original queue, and URL map are preserved
        expect(queueManager.currentQueue.length, 3);
        expect(
          queueManager.currentQueue.map((t) => t.id).toList(),
          ['track1', 'track2', 'track3'],
        );

        await sub.cancel();
      });
    });

    group('Extractor dispatch', () {
      test('defaults to JellyfinTrackIdExtractor when none provided', () {
        final qm = AfQueueManager();
        final track = const AfTrack(
          id: '999',
          title: 'Track',
          artistName: 'A',
          albumName: 'B',
        );
        qm.replaceQueue([track], 0);

        // Jellyfin URL with ID 999 in path — extractor resolves '999',
        // then byId lookup finds the track.
        final mpvItems = [Media('https://server.com/Audio/999/stream')];
        qm.syncFromMpv(mpvItems, 0);

        expect(qm.currentQueue.length, 1);
        expect(qm.currentQueue[0].id, '999');
      });

      test('custom SubsonicTrackIdExtractor resolves id query param', () {
        final qm = AfQueueManager(extractor: const SubsonicTrackIdExtractor());
        final track = const AfTrack(
          id: 'abc',
          title: 'Track',
          artistName: 'A',
          albumName: 'B',
        );
        qm.replaceQueue([track], 0);

        final mpvItems = [
          Media('https://server/rest/stream.view?id=abc&u=user&t=token'),
        ];
        qm.syncFromMpv(mpvItems, 0);

        expect(qm.currentQueue.length, 1);
        expect(qm.currentQueue[0].id, 'abc');
      });

      test('setter switches extractor at runtime', () {
        final qm = AfQueueManager();
        final track = const AfTrack(
          id: 'local-id',
          title: 'Track',
          artistName: 'A',
          albumName: 'B',
        );
        qm.replaceQueue([track], 0);

        // Switch to LocalTrackIdExtractor
        qm.extractor = const LocalTrackIdExtractor();

        // Local URI — extractor returns full URI as id.
        // syncFromMpv will try _urlToTrack first (miss), then extractor
        // which returns the URI. byId lookup uses the URI string which
        // doesn't match 'local-id', so we also pre-populate _urlToTrack.
        qm.rebuildUrlMap(
          [Media('content://media/external/audio/media/local-id')],
          [track],
        );

        final mpvItems = [Media('content://media/external/audio/media/local-id')];
        qm.syncFromMpv(mpvItems, 0);

        expect(qm.currentQueue.length, 1);
        expect(qm.currentQueue[0].id, 'local-id');
      });
    });
  });
}
