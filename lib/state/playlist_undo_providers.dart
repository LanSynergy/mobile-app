import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/local/playlist_undo_buffer.dart';

/// Singleton provider for the playlist undo buffer.
final playlistUndoBufferProvider = Provider<PlaylistUndoBuffer>((ref) {
  final buffer = PlaylistUndoBuffer();
  ref.onDispose(() {
    // No explicit cleanup needed — Timer callbacks are no-ops
    // after ref is disposed
  });
  return buffer;
});
