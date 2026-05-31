import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aetherfin/core/local/playlist_undo_buffer.dart';
import 'package:aetherfin/state/playlist_undo_providers.dart';

void main() {
  group('PlaylistUndoBuffer', () {
    test('push and pop an undo action', () {
      final buffer = PlaylistUndoBuffer();
      buffer.pushRemove('pl-1', 'entry-1', 'track-1');
      final action = buffer.pop('pl-1');
      expect(action, isNotNull);
      expect(action!.playlistId, 'pl-1');
      expect(action.type, PlaylistUndoType.remove);
    });

    test('pop returns null for unknown playlist', () {
      final buffer = PlaylistUndoBuffer();
      expect(buffer.pop('unknown'), isNull);
    });

    test('pop removes the action from buffer', () {
      final buffer = PlaylistUndoBuffer();
      buffer.pushRemove('pl-1', 'entry-1', 'track-1');
      buffer.pop('pl-1');
      expect(buffer.pop('pl-1'), isNull);
    });

    test('pushRemove creates correct undo data', () {
      final buffer = PlaylistUndoBuffer();
      buffer.pushRemove('pl-1', 'entry-1', 'track-1');
      final action = buffer.pop('pl-1')!;
      expect(action.type, PlaylistUndoType.remove);
      expect(action.entryIds, ['entry-1']);
      expect(action.trackIds, ['track-1']);
    });

    test('pushAdd creates correct undo data', () {
      final buffer = PlaylistUndoBuffer();
      buffer.pushAdd('pl-1', ['track-1', 'track-2']);
      final action = buffer.pop('pl-1')!;
      expect(action.type, PlaylistUndoType.add);
      expect(action.entryIds, isEmpty);
      expect(action.trackIds, ['track-1', 'track-2']);
    });

    test('auto-clears after 8 seconds', () {
      fakeAsync((async) {
        final buffer = PlaylistUndoBuffer();
        buffer.pushRemove('pl-1', 'entry-1', 'track-1');
        async.elapse(const Duration(seconds: 9));
        expect(buffer.pop('pl-1'), isNull);
      });
    });

    test('newer action replaces older one for same playlist', () {
      final buffer = PlaylistUndoBuffer();
      buffer.pushRemove('pl-1', 'entry-1', 'track-1');
      buffer.pushRemove('pl-1', 'entry-2', 'track-2');
      final action = buffer.pop('pl-1')!;
      expect(action.entryIds, ['entry-2']);
      expect(action.trackIds, ['track-2']);
    });

    test('different playlists have independent actions', () {
      final buffer = PlaylistUndoBuffer();
      buffer.pushRemove('pl-1', 'e1', 't1');
      buffer.pushAdd('pl-2', ['t2']);
      expect(buffer.pop('pl-1')!.playlistId, 'pl-1');
      expect(buffer.pop('pl-2')!.playlistId, 'pl-2');
    });

    test('pushAdd with multiple track IDs', () {
      final buffer = PlaylistUndoBuffer();
      buffer.pushAdd('pl-1', ['t1', 't2', 't3']);
      final action = buffer.pop('pl-1')!;
      expect(action.trackIds, ['t1', 't2', 't3']);
    });

    test('pushRemove with multiple entry IDs', () {
      final buffer = PlaylistUndoBuffer();
      buffer.pushRemove('pl-1', ['e1', 'e2'], ['t1', 't2']);
      final action = buffer.pop('pl-1')!;
      expect(action.entryIds, ['e1', 'e2']);
      expect(action.trackIds, ['t1', 't2']);
    });
  });

  group('playlistUndoBufferProvider', () {
    test('provides a singleton PlaylistUndoBuffer instance', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final buffer1 = container.read(playlistUndoBufferProvider);
      final buffer2 = container.read(playlistUndoBufferProvider);

      expect(buffer1, isA<PlaylistUndoBuffer>());
      expect(buffer1, same(buffer2));
    });
  });
}
