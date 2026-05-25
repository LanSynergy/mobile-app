import 'dart:async';

/// Type of playlist operation that can be undone.
enum PlaylistUndoType { add, remove }

/// An undoable action stored in the buffer.
class PlaylistUndoAction {
  const PlaylistUndoAction({
    required this.playlistId,
    required this.type,
    this.entryIds = const [],
    this.trackIds = const [],
  });

  final String playlistId;
  final PlaylistUndoType type;
  final List<String> entryIds;
  final List<String> trackIds;
}

/// Ephemeral undo buffer for playlist operations.
///
/// Holds at most one undo action per playlist. Actions auto-expire
/// after 8 seconds. When a new action is pushed for the same playlist,
/// it replaces the old one.
class PlaylistUndoBuffer {
  final Map<String, _BufferedAction> _buffer = {};
  static const Duration _expiry = Duration(seconds: 8);

  /// Push an undo action for a "remove track(s) from playlist" operation.
  void pushRemove(
    String playlistId,
    dynamic entryIds,
    dynamic trackIds, {
    String Function()? makeEntryId,
  }) {
    _push(
      playlistId,
      PlaylistUndoAction(
        playlistId: playlistId,
        type: PlaylistUndoType.remove,
        entryIds: entryIds is List<String> ? entryIds : [entryIds.toString()],
        trackIds: trackIds is List<String> ? trackIds : [trackIds.toString()],
      ),
    );
  }

  /// Push an undo action for an "add track(s) to playlist" operation.
  void pushAdd(String playlistId, List<String> trackIds) {
    _push(
      playlistId,
      PlaylistUndoAction(
        playlistId: playlistId,
        type: PlaylistUndoType.add,
        trackIds: trackIds,
      ),
    );
  }

  /// Pop and return the undo action for [playlistId], or null if none.
  PlaylistUndoAction? pop(String playlistId) {
    final entry = _buffer.remove(playlistId);
    entry?.timer.cancel();
    return entry?.action;
  }

  void _push(String playlistId, PlaylistUndoAction action) {
    // Cancel existing timer for this playlist
    _buffer.remove(playlistId)?.timer.cancel();

    final timer = Timer(_expiry, () {
      _buffer.remove(playlistId);
    });

    _buffer[playlistId] = _BufferedAction(action: action, timer: timer);
  }
}

class _BufferedAction {
  _BufferedAction({required this.action, required this.timer});
  final PlaylistUndoAction action;
  final Timer timer;
}
