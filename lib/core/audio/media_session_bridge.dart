import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

import '../../utils/log.dart';

/// Immutable snapshot of playback state pushed to the Android native
/// [MediaSessionService] via [NativeMediaSessionBridge].
class MediaSessionState {
  const MediaSessionState({
    required this.playing,
    required this.buffering,
    required this.position,
    required this.duration,
    required this.speed,
    this.title,
    this.artist,
    this.album,
    this.artPath,
    this.queueIndex,
    required this.queueSize,
    this.needsArtworkDownload = false,
  });
  final bool playing;
  final bool buffering;
  final Duration position;
  final Duration duration;
  final double speed;
  final String? title;
  final String? artist;
  final String? album;
  final String? artPath;
  final int? queueIndex;
  final int queueSize;

  /// When `true` the bridge will fire [NativeMediaSessionBridge.onArtworkNeeded]
  /// so the owner can trigger remote artwork download for the current track.
  final bool needsArtworkDownload;
}

/// Owns the [MethodChannel] for `aetherfin.media_session` and handles all
/// communication with the Android native [MediaSessionService].
///
/// Responsibilities:
/// * Pushes playback state (track metadata, position, playback status) to the
///   native notification/lock-screen via `invokeMethod('updateState', …)`.
/// * Calls `invokeMethod('clear')` when there is no active track.
/// * Handles incoming platform method calls (`play`, `pause`, `seek`, …) by
///   dispatching to owner-provided callbacks.
/// * Debounces rapid `pushState` calls (throttled to ~100ms) so the relatively
///   slow Android notification pipeline is not overwhelmed.
///
/// The owner ([AfPlayerService]) creates the bridge, wires callbacks, and
/// calls [pushState] on every playback state change.
class NativeMediaSessionBridge {
  NativeMediaSessionBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('aetherfin.media_session') {
    _channel.setMethodCallHandler(_handleMethodCall);
  }
  final MethodChannel _channel;

  static const _throttleDuration = Duration(milliseconds: 100);

  DateTime _lastPush = DateTime.fromMillisecondsSinceEpoch(0);
  bool _lastPushedPlaying = false;
  bool _lastPushedBuffering = false;

  // ── Owner callbacks ──────────────────────────────────────────────
  // These are set by [AfPlayerService] to route platform-originated
  // media-session actions back to the mpv-based playback logic.

  VoidCallback? onPlay;
  VoidCallback? onPause;
  VoidCallback? onNext;
  VoidCallback? onPrevious;
  VoidCallback? onStop;
  void Function(Duration)? onSeek;
  void Function(int)? onSkipToQueueItem;
  void Function(double)? onDuck;
  VoidCallback? onUnduck;

  /// Fired by [pushState] when [MediaSessionState.artPath] is `null` and
  /// [MediaSessionState.needsArtworkDownload] is `true`. The owner should
  /// trigger a remote artwork download for the current track.
  VoidCallback? onArtworkNeeded;

  /// Push the current playback state to the native media session.
  ///
  /// Debounces rapid consecutive calls with identical playing/buffering
  /// state to at most one update per [_throttleDuration] (~100ms).
  void pushState(MediaSessionState state) {
    final now = DateTime.now();
    final stateChanged =
        _lastPushedPlaying != state.playing ||
        _lastPushedBuffering != state.buffering;

    if (!stateChanged && now.difference(_lastPush) < _throttleDuration) {
      return;
    }

    _lastPush = now;
    _lastPushedPlaying = state.playing;
    _lastPushedBuffering = state.buffering;

    // Fire artwork download trigger when the state indicates remote
    // artwork is needed but no local path is available.
    if (state.artPath == null && state.needsArtworkDownload) {
      onArtworkNeeded?.call();
    }

    final args = <String, dynamic>{
      'playing': state.playing,
      'buffering': state.buffering,
      'positionMs': state.position.inMilliseconds,
      'durationMs': state.duration.inMilliseconds,
      'speed': state.speed,
      'title': state.title,
      'artist': state.artist,
      'album': state.album,
      'artPath': state.artPath,
      'queueIndex': state.queueIndex,
      'queueSize': state.queueSize,
    };

    _channel.invokeMethod('updateState', args).catchError((Object e) {
      afLog('error', 'Failed to update native media state', error: e);
    });
  }

  /// Tell the native side to clear its media session (no active track).
  void clear() {
    _channel.invokeMethod('clear').catchError((Object e) {
      afLog('error', 'Failed to clear native media state', error: e);
    });
  }

  /// Tear down. Nulls the method call handler so no orphaned callbacks
  /// remain after the owning service is disposed.
  void dispose() {
    _channel.setMethodCallHandler(null);
  }

  /// Exposed for testing. Sends a simulated platform method call through
  /// the method call handler as if it came from the native side.
  @visibleForTesting
  Future<dynamic> handleMethodCall(MethodCall call) => _handleMethodCall(call);

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'play':
        onPlay?.call();
      case 'pause':
        onPause?.call();
      case 'next':
        onNext?.call();
      case 'previous':
        onPrevious?.call();
      case 'stop':
        onStop?.call();
      case 'seek':
        final positionMs = call.arguments['positionMs'] as int?;
        if (positionMs != null) {
          onSeek?.call(Duration(milliseconds: positionMs));
        }
      case 'skipTo':
        final queueIndex = call.arguments['queueIndex'] as int?;
        if (queueIndex != null) {
          onSkipToQueueItem?.call(queueIndex);
        }
      case 'duck':
        final volume = call.arguments?['volume'] as double? ?? 0.2;
        onDuck?.call(volume);
      case 'unduck':
        onUnduck?.call();
      default:
        throw PlatformException(
          code: 'Unimplemented',
          details: 'Method ${call.method} is not implemented',
        );
    }
  }
}
