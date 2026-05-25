import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aetherfin/core/local/playlist_undo_buffer.dart';
import 'package:aetherfin/state/playlist_undo_providers.dart';

void main() {
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
