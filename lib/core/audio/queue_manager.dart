import 'dart:async';

import 'package:mpv_audio_kit/mpv_audio_kit.dart' show Media;

import '../../utils/log.dart';
import '../jellyfin/models/items.dart';

/// Manages the playback queue, track index, shuffle state, and URL→track
/// mapping. Owns the queue/track/shuffle broadcast streams so the UI
/// (via [AfPlayerService]) always sees a consistent view.
///
/// This is a pure-data manager — it holds state and emits events but
/// does not touch [Player] directly. The owning service calls these
/// methods and is responsible for keeping mpv's playlist in sync.
class AfQueueManager {
  final List<AfTrack> _trackQueue = <AfTrack>[];
  int _currentIndex = -1;
  List<AfTrack> _originalQueue = <AfTrack>[];
  final Map<String, AfTrack> _urlToTrack = <String, AfTrack>{};

  bool _shuffleEnabled = false;
  final _shuffleController = StreamController<bool>.broadcast();
  final _trackController = StreamController<AfTrack?>.broadcast();
  final _queueController = StreamController<List<AfTrack>>.broadcast();

  int _suppressPlaylistSyncGen = 0;
  int _activePlaylistSyncGen = 0;

  // ── Streams ────────────────────────────────────────────────────────

  Stream<AfTrack?> get currentTrackStream => _trackController.stream;
  Stream<List<AfTrack>> get queueStream => _queueController.stream;
  Stream<bool> get shuffleModeStream => _shuffleController.stream;

  // ── State queries ──────────────────────────────────────────────────

  bool get isShuffleEnabled => _shuffleEnabled;
  List<AfTrack> get currentQueue => List<AfTrack>.unmodifiable(_trackQueue);
  int get currentIndex => _currentIndex;

  AfTrack? get currentTrack =>
      (_currentIndex >= 0 && _currentIndex < _trackQueue.length)
          ? _trackQueue[_currentIndex]
          : null;

  bool get isAtQueueEnd =>
      _currentIndex >= _trackQueue.length - 1;

  bool get isSyncingPlaylist => _activePlaylistSyncGen != 0;

  /// Returns `true` if the queue is not currently being modified by
  /// the owning service (playlist sync is inactive). The service sets
  /// [beginPlaylistSync]/[endPlaylistSync] around batch operations so
  /// the playlist listener does not re-enter.
  bool get canHandlePlaylistEvent =>
      _activePlaylistSyncGen == 0;

  // ── URL↔track mapping ──────────────────────────────────────────────

  AfTrack? trackForUrl(String url) => _urlToTrack[url];

  void rebuildUrlMap(Iterable<Media> medias, Iterable<AfTrack> tracks) {
    _urlToTrack.clear();
    for (var i = 0; i < tracks.length && i < medias.length; i++) {
      _urlToTrack[medias.elementAt(i).uri] = tracks.elementAt(i);
    }
  }

  // ── Queue lifecycle ────────────────────────────────────────────────

  void replaceQueue(List<AfTrack> tracks, int startIndex) {
    _trackQueue
      ..clear()
      ..addAll(tracks);
    _currentIndex = startIndex.clamp(0, tracks.length - 1);
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
    _suppressPlaylistSyncGen++;
    _activePlaylistSyncGen = _suppressPlaylistSyncGen;
  }

  void endPlaylistSync() {
    _activePlaylistSyncGen = 0;
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
  /// Returns the previous track id if the index changed, null otherwise.
  String? processPlaylistEvent(int newIndex) {
    if (newIndex < 0 || newIndex >= _trackQueue.length) return null;

    final indexChanged = newIndex != _currentIndex;
    final previousTrackId =
        (_currentIndex >= 0 && _currentIndex < _trackQueue.length)
            ? _trackQueue[_currentIndex].id
            : null;

    _currentIndex = newIndex;

    if (!indexChanged) return null;
    final track = _trackQueue[newIndex];
    if (track.id == previousTrackId) return null;

    return previousTrackId;
  }

  /// Reconcile the Dart queue order with mpv's (post-shuffle).
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
        final id = _extractTrackId(media.uri);
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
      afLog(
        'audio',
        '_syncTrackQueueFromMpv partial sync: '
            'resolved ${reordered.length}/${mpvItems.length} tracks, '
            'updating with resolved subset',
      );
      _trackQueue
        ..clear()
        ..addAll(reordered);
      _currentIndex = newIdx.clamp(0, _trackQueue.length - 1);
    } else {
      afLog(
        'audio',
        '_syncTrackQueueFromMpv full sync failure: '
            'resolved 0/${mpvItems.length} tracks, clearing queue',
      );
      _trackQueue.clear();
      _currentIndex = 0;
      _trackController.add(null);
      _queueController.add(const <AfTrack>[]);
    }
  }

  static String? _extractTrackId(String uri) {
    final parsed = Uri.tryParse(uri);
    if (parsed == null) return null;

    final segments = parsed.pathSegments;
    for (var i = 0; i < segments.length - 1; i++) {
      if (segments[i].toLowerCase() == 'audio') {
        return segments[i + 1];
      }
    }

    final queryId = parsed.queryParameters['id'];
    if (queryId != null && queryId.isNotEmpty) return queryId;
    return null;
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
    _trackQueue.clear();
    _currentIndex = -1;
    _originalQueue = <AfTrack>[];
    _urlToTrack.clear();
    _shuffleEnabled = false;
    _queueController.add(const <AfTrack>[]);
    _trackController.add(null);
  }

  // ── Lifecycle ──────────────────────────────────────────────────────

  void dispose() {
    _trackController.close();
    _queueController.close();
    _shuffleController.close();
  }
}
