import 'dart:async';

import 'package:mpv_audio_kit/mpv_audio_kit.dart';

/// Manages loop mode state and its broadcast stream.
///
/// Encapsulates the [Loop] mode value and a [StreamController] so
/// consumers (UI, media session) can listen for changes without
/// touching the player service directly.
class LoopModeManager {
  LoopModeManager() : _controller = StreamController<Loop>.broadcast();

  final StreamController<Loop> _controller;
  Loop _mode = Loop.off;

  /// The current loop mode.
  Loop get mode => _mode;

  /// Broadcast stream of loop mode changes.
  Stream<Loop> get stream => _controller.stream;

  /// Set the loop mode and notify listeners.
  void setMode(Loop mode) {
    _mode = mode;
    _controller.add(mode);
  }

  /// Synchronously set loop mode to off without acquiring the queue lock.
  ///
  /// Use when exiting forNtimes to prevent stale [_mode] reads in
  /// concurrent [setMode] → media session update calls.
  void setOffSync() {
    _mode = Loop.off;
    _controller.add(Loop.off);
  }

  /// Close the stream controller.
  Future<void> dispose() => _controller.close();
}
