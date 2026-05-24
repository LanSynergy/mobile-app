import 'dart:async';
import 'dart:collection';

import 'package:mpv_audio_kit/mpv_audio_kit.dart' show Media;

import '../../utils/log.dart';
import '../jellyfin/models/items.dart';
import 'track_id_extractor.dart';

/// Manages the playback queue, track index, shuffle state, and URL→track
/// mapping. Owns the queue/track/shuffle broadcast streams so the UI
/// (via [AfPlayerService]) always sees a consistent view.
///
/// This is a pure-data manager — it holds state and emits events but
/// does not touch [Player] directly. The owning service calls these
/// methods and is responsible for keeping mpv's playlist in sync.
class AfQueueManager {

  AfQueueManager({TrackIdExtractor? extractor})
      : _extractor = extractor ?? const JellyfinTrackIdExtractor();
  final List<AfTrack> _trackQueue = <AfTrack>[];
  int _currentIndex = -1;
  List<AfTrack> _originalQueue = <AfTrack>[];
  final Map<String, AfTrack> _urlToTrack = <String, AfTrack>{};

  bool _shuffleEnabled = false;
  final _shuffleController = StreamController<bool>.broadcast();
  final _trackController = StreamController<AfTrack?>.broadcast();
  final _queueController = StreamController<List<AfTrack>>.broadcast();

  int _activePlaylistSyncs = 0;
  bool _playbackEnded = false;
  late TrackIdExtractor _extractor;

  // ── Streams ────────────────────────────────────────────────────────

  Stream<AfTrack?> get currentTrackStream => _trackController.stream;
  Stream<List<AfTrack>> get queueStream => _queueController.stream;
  Stream<bool> get shuffleModeStream => _shuffleController.stream;

  // ── State queries ──────────────────────────────────────────────────

  bool get isShuffleEnabled => _shuffleEnabled;
  List<AfTrack> get currentQueue => UnmodifiableListView(_trackQueue);
  int get currentIndex => _currentIndex;

  AfTrack? get currentTrack =>
      (_currentIndex >= 0 && _currentIndex < _trackQueue.length)
          ? _trackQueue[_currentIndex]
          : null;

  bool get isAtQueueEnd =>
      _currentIndex >= _trackQueue.length - 1;

  bool get isSyncingPlaylist => _activePlaylistSyncs != 0;
  bool get playbackEnded => _playbackEnded;

  /// Returns `true` if the queue is not currently being modified by
  /// the owning service (playlist sync is inactive). The service sets
  /// [beginPlaylistSync]/[endPlaylistSync] around batch operations so
  /// the playlist listener does not re-enter.
  bool get canHandlePlaylistEvent =>
      _activePlaylistSyncs == 0;

  set extractor(TrackIdExtractor extractor) {
    _extractor = extractor;
  }

  // ── URL↔track mapping ──────────────────────────────────────────────

  AfTrack? trackForUrl(String url) => _urlToTrack[url];

  void rebuildUrlMap(Iterable<Media> medias, Iterable<AfTrack> tracks) {
    _urlToTrack.clear();
    final mediaIter = medias.iterator;
    final trackIter = tracks.iterator;
    while (mediaIter.moveNext() && trackIter.moveNext()) {
      _urlToTrack[mediaIter.current.uri] = trackIter.current;
    }
  }

  // ── Queue lifecycle ────────────────────────────────────────────────

  void replaceQueue(List<AfTrack> tracks, int startIndex) {
    if (tracks.isEmpty) return;
    _trackQueue
      ..clear()
      ..addAll(tracks);
    _currentIndex = startIndex.clamp(0, tracks.length - 1);
    _playbackEnded = false;
    _queueController.add(List<AfTrack>.unmodifiable(_trackQueue));
  }

  void setOriginalQueue(List<AfTrack> tracks) {
    _originalQueue = tracks;
  }

  void clearOriginalQueue() {
    _originalQueue = <AfTrack>[];
  }

  // ── Track change ───────────────────────────────────────────────────

  void emitCurrentTrack(AfTrack track) {
    _trackController.add(track);
  }

  void emitQueue() {
    _queueController.add(List<AfTrack>.unmodifiable(_trackQueue));
  }

  // ── Shuffle ────────────────────────────────────────────────────────

  void beginPlaylistSync() {
    _activePlaylistSyncs++;
  }

  void endPlaylistSync() {
    if (_activePlaylistSyncs > 0) {
      _activePlaylistSyncs--;
    }
  }

  void setShuffleEnabled(bool enabled) {
    _shuffleEnabled = enabled;
    _shuffleController.add(enabled);
    if (enabled && _originalQueue.isEmpty) {
      _originalQueue = List<AfTrack>.of(_trackQueue);
    }
    // When disabling shuffle, do NOT clear _originalQueue here.
    // syncFromMpv() needs it as a fallback for byId lookups. The caller
    // must call clearOriginalQueueAfterSync() after the sync completes.
    _queueController.add(List<AfTrack>.unmodifiable(_trackQueue));
  }

  /// Clear the original (pre-shuffle) queue snapshot. Call this AFTER
  /// [syncFromMpv] has finished when disabling shuffle, so the sync can
  /// use the original queue as a fallback lookup source.
  void clearOriginalQueueAfterSync() {
    _originalQueue = <AfTrack>[];
  }

  // ── Playlist event processing ──────────────────────────────────────

  /// Update internal queue state from an mpv playlist event.
  /// Returns true if the active track changed, false otherwise.
  /// Returns false immediately when playback has ended so deferred
  /// playlist events from mpv's stop() cannot reinstate the track.
  bool processPlaylistEvent(int newIndex) {
    if (_playbackEnded) return false;
    if (newIndex < 0 || newIndex >= _trackQueue.length) return false;

    final previousTrackId =
        (_currentIndex >= 0 && _currentIndex < _trackQueue.length)
            ? _trackQueue[_currentIndex].id
            : null;

    _currentIndex = newIndex;

    final track = _trackQueue[newIndex];
    final trackChanged = track.id != previousTrackId;

    return trackChanged;
  }

  /// Callback invoked when [syncFromMpv] fails to resolve tracks.
  /// The [resolveCount]/[totalCount] ratio indicates severity.
  void Function(int resolveCount, int totalCount)? onSyncFailed;

  /// Reconcile the Dart queue order with mpv's (post-shuffle).
  ///
  /// On **full resolution** (all mpv items matched): the queue is replaced
  /// with the reordered tracks. On **partial resolution** (some items
  /// matched): the existing queue is preserved and a warning is logged to
  /// avoid silent truncation. On **full failure** (zero items matched): the
  /// existing queue is preserved and [onSyncFailed] is invoked so the
  /// service can surface the error to the UI.
  void syncFromMpv(List<Media> mpvItems, int newIdx) {
    if (mpvItems.isEmpty) return;

    final byId = <String, AfTrack>{};
    for (final t in _trackQueue) {
      byId[t.id] = t;
    }
    for (final t in _originalQueue) {
      byId[t.id] = t;
    }

    final reordered = <AfTrack>[];
    for (final media in mpvItems) {
      var track = _urlToTrack[media.uri];
      if (track == null) {
        final id = _extractor.extractId(media.uri);
        track = id != null ? byId[id] : null;
      }
      if (track != null) reordered.add(track);
    }

    if (reordered.length == mpvItems.length) {
      _trackQueue
        ..clear()
        ..addAll(reordered);
      _currentIndex = newIdx.clamp(0, _trackQueue.length - 1);
    } else if (reordered.isNotEmpty) {
      // Partial sync — preserve existing queue to prevent silent truncation.
      // The mpv-side playlist may have URLs we can't map back to AfTracks,
      // but losing those tracks from the UI is worse than a stale order.
      afLog(
        'audio',
        '_syncTrackQueueFromMpv partial sync: '
            'resolved ${reordered.length}/${mpvItems.length} tracks, '
            'preserving existing queue',
      );
      onSyncFailed?.call(reordered.length, mpvItems.length);
    } else {
      afLog(
        'audio',
        '_syncTrackQueueFromMpv full sync failure: '
            'resolved 0/${mpvItems.length} tracks, '
            'preserving existing queue',
      );
      onSyncFailed?.call(0, mpvItems.length);
    }
  }

  // ── Queue manipulation ─────────────────────────────────────────────

  bool canReorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _trackQueue.length) return false;
    if (newIndex < 0 || newIndex > _trackQueue.length) return false;
    return oldIndex != newIndex;
  }

  /// Returns the adjusted insertion index after removal (`newIndex > oldIndex`
  /// shifts down by one). Caller should update the mpv playlist first.
  int reorder(int oldIndex, int newIndex) {
    final track = _trackQueue.removeAt(oldIndex);
    final insertIdx = newIndex > oldIndex ? newIndex - 1 : newIndex;
    _trackQueue.insert(insertIdx, track);

    if (_currentIndex == oldIndex) {
      _currentIndex = insertIdx;
    } else if (oldIndex < _currentIndex && insertIdx >= _currentIndex) {
      _currentIndex -= 1;
    } else if (oldIndex > _currentIndex && insertIdx <= _currentIndex) {
      _currentIndex += 1;
    }

    _queueController.add(List<AfTrack>.unmodifiable(_trackQueue));
    return insertIdx;
  }

  bool canRemove(int index) =>
      index >= 0 &&
      index < _trackQueue.length &&
      index != _currentIndex;

  void remove(int index) {
    _trackQueue.removeAt(index);
    if (index < _currentIndex) {
      _currentIndex -= 1;
    }
    _queueController.add(List<AfTrack>.unmodifiable(_trackQueue));
  }

  void insert(int index, AfTrack track, String url) {
    final clamped = index.clamp(0, _trackQueue.length);
    _trackQueue.insert(clamped, track);
    _urlToTrack[url] = track;
    if (clamped <= _currentIndex) {
      _currentIndex += 1;
    }
    _queueController.add(List<AfTrack>.unmodifiable(_trackQueue));
  }

  void append(AfTrack track, String url) {
    _trackQueue.add(track);
    _urlToTrack[url] = track;
    _queueController.add(List<AfTrack>.unmodifiable(_trackQueue));
  }

  void clear() {
    _playbackEnded = false;
    _trackQueue.clear();
    _currentIndex = -1;
    _originalQueue = <AfTrack>[];
    _urlToTrack.clear();
    _shuffleEnabled = false;
    _queueController.add(const <AfTrack>[]);
    _trackController.add(null);
  }

  /// End playback without clearing the queue or shuffle state.
  ///
  /// Sets `_currentIndex = -1` and emits `null` on the track stream so the
  /// native session sends `clear` instead of a paused notification. The
  /// queue list, original queue, and URL→track map are preserved so the
  /// UI can still show the queue history and the user can restart playback.
  ///
  /// Contrast with [clear] which destroys all state (queue, shuffle,
  /// original queue, URL map).
  void endPlayback() {
    _currentIndex = -1;
    _playbackEnded = true;
    _trackController.add(null);
  }

  // ── Lifecycle ──────────────────────────────────────────────────────

  void dispose() {
    _trackController.close();
    _queueController.close();
    _shuffleController.close();
  }
}
