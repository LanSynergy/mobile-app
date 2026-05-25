import 'dart:math';
import '../jellyfin/models/items.dart';

/// Single source of truth for queue state.
///
/// Pure Dart — no mpv dependency, no streams, no Flutter imports.
/// Owns the full track list, current index, and shuffle index mapping.
/// All queue mutations (reorder, remove, insert, shuffle) are pure Dart.
///
/// Shuffle design: Fisher-Yates index mapping.
/// - Shuffle OFF: _shuffleOrder is null, direct index access.
/// - Shuffle ON: _shuffleOrder[i] = original index in _tracks.
/// - queue[i] = _tracks[_shuffleOrder[i]]
///
/// Window tracking: _windowStart is the _tracks index of mpv slot 0.
/// Slot 0 = tracks[_windowStart], Slot 1 = tracks[_windowStart + 1].
class AfQueueEngine {
  AfQueueEngine({Random? random}) : _random = random ?? Random();

  List<AfTrack> _tracks = <AfTrack>[];
  int _currentIndex = -1;
  List<int>? _shuffleOrder;
  int _windowStart = 0;
  bool _playbackEnded = false;

  // ── forNtimes loop mode fields ────────────────────────────────────
  bool _isForNtimes = false;
  int _remainingRepeats = 0;
  int _ntimesCount = 2;
  bool _isTailShuffle = false;

  final Random _random;

  // ── Query helpers ──────────────────────────────────────────────────

  List<AfTrack> get tracks {
    if (_shuffleOrder == null) return List<AfTrack>.unmodifiable(_tracks);
    return List<AfTrack>.unmodifiable(_shuffleOrder!.map((i) => _tracks[i]));
  }

  int get currentIndex {
    if (_shuffleOrder == null) return _currentIndex;
    if (_currentIndex == -1) return -1;
    return _shuffleOrder!.indexOf(_currentIndex);
  }

  int get windowStart => _windowStart;
  bool get isShuffleEnabled => _shuffleOrder != null;
  bool get playbackEnded => _playbackEnded;
  bool get isForNtimes => _isForNtimes;
  int get remainingRepeats => _remainingRepeats;
  int get ntimesCount => _ntimesCount;
  bool get isNtimesModeActive => _isForNtimes && _remainingRepeats > 0;
  bool get isTailShuffle => _isTailShuffle;

  AfTrack? get currentTrack =>
      (_currentIndex >= 0 && _currentIndex < _tracks.length)
      ? _tracks[_currentIndex]
      : null;

  /// Track at mpv slot 0 (the currently-playing slot).
  AfTrack? get windowSlot0 {
    if (_windowStart < 0 || _windowStart >= _tracks.length) return null;
    return trackAt(_windowStart);
  }

  /// Track at mpv slot 1 (the pre-decoded next track).
  AfTrack? get windowSlot1 {
    final idx = _windowStart + 1;
    if (idx < 0 || idx >= _tracks.length) return null;
    return trackAt(idx);
  }

  /// The next track that should be loaded into mpv after the current one.
  AfTrack? get nextTrack {
    final nextIdx = currentIndex + 1;
    if (nextIdx < 0 || nextIdx >= _tracks.length) return null;
    return trackAt(nextIdx);
  }

  /// The index in [_tracks] of the "next next" track (for window replacement).
  int get nextNextIndex => _windowStart + 2;

  AfTrack? get nextNextTrack {
    final idx = nextNextIndex;
    if (idx < 0 || idx >= _tracks.length) return null;
    return trackAt(idx);
  }

  bool get isAtQueueEnd {
    if (_tracks.isEmpty) return true;
    return currentIndex >= _tracks.length - 1;
  }

  bool get isEmpty => _tracks.isEmpty;
  int get length => _tracks.length;

  // ── Lifecycle ──────────────────────────────────────────────────────

  /// Replace the entire queue with [tracks] starting at [startIndex].
  void replaceAll(List<AfTrack> tracks, int startIndex) {
    _tracks = List<AfTrack>.of(tracks);
    if (_tracks.isEmpty) {
      _currentIndex = -1;
      _windowStart = 0;
    } else {
      _currentIndex = startIndex.clamp(0, _tracks.length - 1);
      _windowStart = _currentIndex;
    }
    _playbackEnded = false;
    _isTailShuffle = false;
    _shuffleOrder = null;
  }

  /// End playback: set currentIndex to -1 without clearing the queue.
  void endPlayback() {
    _currentIndex = -1;
    _playbackEnded = true;
    _isForNtimes = false;
    _remainingRepeats = 0;
  }

  /// Clear all state.
  void clear() {
    _tracks = <AfTrack>[];
    _currentIndex = -1;
    _windowStart = 0;
    _shuffleOrder = null;
    _playbackEnded = false;
    _isForNtimes = false;
    _remainingRepeats = 0;
    _isTailShuffle = false;
  }

  // ── Shuffle (Fisher-Yates index mapping) ───────────────────────────

  /// Enable or disable shuffle.
  ///
  /// When enabling: builds a Fisher-Yates shuffled index list.
  /// When disabling: nulls out the shuffle order (pure Dart, 0 mpv calls).
  void setShuffle(bool enabled) {
    if (enabled == isShuffleEnabled) return;
    if (enabled) {
      _shuffleOrder = List<int>.generate(_tracks.length, (i) => i);
      _fisherYatesShuffle();
      _windowStart = 0;
    } else {
      _windowStart = _currentIndex >= 0 ? _currentIndex : 0;
      _shuffleOrder = null;
      _isTailShuffle = false;
    }
  }

  /// Activate or deactivate forNtimes loop mode.
  void setForNtimes(bool enabled) {
    _isForNtimes = enabled;
    _remainingRepeats = enabled ? _ntimesCount : 0;
  }

  /// Set the N value (how many repeats per track).
  void setNtimesCount(int count) {
    _ntimesCount = count > 0 ? count : 2;
    if (_isForNtimes && _remainingRepeats > 0) {
      _remainingRepeats = _ntimesCount;
    }
  }

  /// Decrement remaining repeats (called on track completion).
  void decrementRepeats() {
    if (_remainingRepeats > 0) {
      _remainingRepeats--;
    }
  }

  /// Reset repeats counter to the configured N value.
  void resetRepeats() {
    if (_isForNtimes) {
      _remainingRepeats = _ntimesCount;
    }
  }

  /// Fisher-Yates shuffle of the current [_shuffleOrder].
  /// Preserves the current track's position so playback isn't interrupted.
  void _fisherYatesShuffle() {
    if (_shuffleOrder == null || _tracks.isEmpty) return;

    // Remove current track from the pool, shuffle the rest, then reinsert.
    final currentTrackId = _currentIndex >= 0 && _currentIndex < _tracks.length
        ? _tracks[_currentIndex].id
        : null;

    // Build the mapping: shuffled position → original index.
    // The current track stays at its current position (index 0 of window).
    final indices = List<int>.generate(_tracks.length, (i) => i);
    if (currentTrackId != null) {
      // Swap current track to front, shuffle the rest.
      indices.remove(_currentIndex);
      indices.shuffle(_random);
      indices.insert(0, _currentIndex);
    } else {
      indices.shuffle(_random);
    }
    _shuffleOrder = indices;
  }

  /// Shuffle only the tail — everything after the current logical position.
  void shuffleTail() {
    if (_tracks.isEmpty) return;

    final logicalCurrent = currentIndex;
    if (logicalCurrent < 0 || logicalCurrent >= _tracks.length - 1) return;

    final tailStart = logicalCurrent + 1;
    final tailLength = _tracks.length - tailStart;

    _isTailShuffle = true;

    if (_shuffleOrder == null) {
      _shuffleOrder = List<int>.generate(_tracks.length, (i) => i);
      final tail = _shuffleOrder!.sublist(tailStart);
      tail.shuffle(_random);
      _shuffleOrder = [
        ..._shuffleOrder!.sublist(0, tailStart),
        ...tail,
      ];
    } else {
      final head = _shuffleOrder!.sublist(0, tailStart);
      final tail = _shuffleOrder!.sublist(tailStart);
      tail.shuffle(_random);
      _shuffleOrder = [...head, ...tail];
    }
  }

  /// Reset forNtimes repeats counter on track jump.
  void _resetRepeatsOnJump() {
    if (_isForNtimes) {
      _remainingRepeats = _ntimesCount;
    }
  }

  /// Map a logical queue index to the actual track.
  AfTrack trackAt(int logicalIndex) {
    final actualIndex = _shuffleOrder != null
        ? _shuffleOrder![logicalIndex]
        : logicalIndex;
    return _tracks[actualIndex];
  }

  /// Convert a logical index to physical (_tracks) index.
  int physicalIndex(int logicalIndex) {
    return _shuffleOrder != null ? _shuffleOrder![logicalIndex] : logicalIndex;
  }

  /// Convert a physical (_tracks) index to logical (queue) index.
  int logicalIndex(int physicalIndex) {
    if (_shuffleOrder == null) return physicalIndex;
    return _shuffleOrder!.indexOf(physicalIndex);
  }

  // ── Track transitions ──────────────────────────────────────────────

  /// Advance to the next track. Returns new currentIndex.
  int advanceIndex() {
    if (_tracks.isEmpty) return currentIndex;
    final logicalIdx = currentIndex;
    if (logicalIdx < _tracks.length - 1) {
      _currentIndex = physicalIndex(logicalIdx + 1);
      resetRepeats();
    }
    return currentIndex;
  }

  /// Retreat to the previous track. Returns new currentIndex.
  int retreatIndex() {
    if (_tracks.isEmpty) return currentIndex;
    final logicalIdx = currentIndex;
    if (logicalIdx > 0) {
      _currentIndex = physicalIndex(logicalIdx - 1);
      resetRepeats();
    }
    return currentIndex;
  }

  /// Jump to a specific logical index. Returns new currentIndex.
  int jumpTo(int logicalIndex) {
    if (_tracks.isEmpty) return currentIndex;
    final clamped = logicalIndex.clamp(0, _tracks.length - 1);
    _currentIndex = physicalIndex(clamped);
    _resetRepeatsOnJump();
    _windowStart = clamped;
    return currentIndex;
  }

  /// Advance the window start by 1 (called after a track completes).
  /// Returns the new window start index.
  int advanceWindow() {
    if (_windowStart < _tracks.length - 1) {
      _windowStart++;
    }
    return _windowStart;
  }

  // ── Queue mutations (all pure Dart, 0 mpv calls) ───────────────────

  bool canReorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _tracks.length) return false;
    if (newIndex < 0 || newIndex > _tracks.length) return false;
    return oldIndex != newIndex;
  }

  /// Reorder a track from [oldIndex] to [newIndex].
  /// Returns the adjusted insertion index.
  int reorder(int oldIndex, int newIndex) {
    if (_shuffleOrder == null) {
      final track = _tracks.removeAt(oldIndex);
      final insertIdx = newIndex > oldIndex ? newIndex - 1 : newIndex;
      _tracks.insert(insertIdx, track);

      // Track where the current track moved to after reorder
      if (_currentIndex == oldIndex) {
        _currentIndex = insertIdx;
      } else if (oldIndex < _currentIndex && insertIdx >= _currentIndex) {
        _currentIndex -= 1;
      } else if (oldIndex > _currentIndex && insertIdx <= _currentIndex) {
        _currentIndex += 1;
      }
      // WindowStart follows the same logic as currentIndex for reorder
      if (_windowStart == oldIndex) {
        _windowStart = insertIdx;
      } else if (oldIndex < _windowStart && insertIdx >= _windowStart) {
        _windowStart -= 1;
      } else if (oldIndex > _windowStart && insertIdx <= _windowStart) {
        _windowStart += 1;
      }

      return insertIdx;
    } else {
      final physicalIdx = _shuffleOrder!.removeAt(oldIndex);
      final insertIdx = newIndex > oldIndex ? newIndex - 1 : newIndex;
      _shuffleOrder!.insert(insertIdx, physicalIdx);

      // Adjust _windowStart (logical)
      if (_windowStart == oldIndex) {
        _windowStart = insertIdx;
      } else if (oldIndex < _windowStart && insertIdx >= _windowStart) {
        _windowStart -= 1;
      } else if (oldIndex > _windowStart && insertIdx <= _windowStart) {
        _windowStart += 1;
      }

      return insertIdx;
    }
  }

  bool canRemove(int index) {
    if (index < 0 || index >= _tracks.length) return false;
    return index != currentIndex;
  }

  /// Remove a track at [index].
  void remove(int index) {
    if (_shuffleOrder == null) {
      _tracks.removeAt(index);
      _adjustIndicesAfterRemove(index, null);
    } else {
      final physicalIdx = _shuffleOrder![index];
      _tracks.removeAt(physicalIdx);
      _shuffleOrder!.removeAt(index);

      // Adjust any physical indices in _shuffleOrder that were after the removed physical index
      for (var i = 0; i < _shuffleOrder!.length; i++) {
        if (_shuffleOrder![i] > physicalIdx) {
          _shuffleOrder![i]--;
        }
      }

      // Adjust _currentIndex (physical)
      if (_currentIndex > physicalIdx) {
        _currentIndex--;
      }

      // Adjust _windowStart (logical)
      final logicalCurrentIndex = _shuffleOrder!.indexOf(_currentIndex);
      if (_windowStart > index) {
        _windowStart--;
      } else if (_windowStart == index) {
        _windowStart = logicalCurrentIndex.clamp(0, _shuffleOrder!.length - 1);
      }
    }
  }

  /// Insert [track] at [index].
  void insert(int index, AfTrack track) {
    if (_shuffleOrder == null) {
      final clamped = index.clamp(0, _tracks.length);
      _tracks.insert(clamped, track);
      if (clamped <= _currentIndex) {
        _currentIndex++;
      }
      if (clamped <= _windowStart) {
        _windowStart++;
      }
    } else {
      final clampedLogical = index.clamp(0, _shuffleOrder!.length);
      _tracks.add(track);
      final newPhysicalIndex = _tracks.length - 1;
      _shuffleOrder!.insert(clampedLogical, newPhysicalIndex);

      if (clampedLogical <= _windowStart) {
        _windowStart++;
      }
    }
  }

  /// Append [track] to the end of the queue.
  void append(AfTrack track) {
    _tracks.add(track);
    if (_shuffleOrder != null) {
      _shuffleOrder!.add(_tracks.length - 1);
    }
  }

  /// Call when the slot to replace on track completion changes.
  /// Returns the index of the track that should replace the finished slot.
  int slotToReplace(int mpvPlayingSlotIndex) {
    // mpvPlayingSlotIndex is 0 or 1 (the slot mpv is currently playing).
    // Replace the OTHER slot.
    return 1 - mpvPlayingSlotIndex;
  }

  // ── Internal helpers ───────────────────────────────────────────────

  void _adjustIndicesAfterRemove(int removedIndex, int? insertedAt) {
    if (_currentIndex > removedIndex) {
      _currentIndex--;
    } else if (_currentIndex == removedIndex) {
      // Can't remove current track — this shouldn't happen with canRemove guard.
    }
    if (_windowStart > removedIndex) {
      _windowStart--;
    } else if (_windowStart == removedIndex) {
      _windowStart = _currentIndex.clamp(0, _tracks.length - 1);
    }
  }
}
