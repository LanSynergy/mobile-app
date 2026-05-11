import 'dart:async';

import 'package:flutter/services.dart';

import '../../utils/log.dart';
import 'player_service.dart';

/// Dart bridge to [VisualizerPlugin] (Kotlin).
///
/// Attaches Android's `android.media.audiofx.Visualizer` to ExoPlayer's
/// audio session and exposes a [Stream<double>] of normalised FFT magnitude
/// values in [0.0, 1.0] at ~60 Hz.
///
/// ## Lifecycle
///
/// 1. Call [attach] once playback starts (or when the audio session ID
///    becomes available). Safe to call multiple times — re-attaches cleanly.
/// 2. Call [detach] on pause / stop to release the native Visualizer
///    resource (it holds a system-wide audio effect slot).
/// 3. Call [dispose] when the owning service is torn down.
///
/// ## Fallback
///
/// On non-Android platforms, in tests, or when the native plugin is absent,
/// every method is a no-op and [magnitudeStream] emits nothing. Callers
/// should fall back to a static animation in that case.
class VisualizerService {
  static const _method = MethodChannel('aetherfin.visualizer');
  static const _event  = EventChannel('aetherfin.visualizer/fft');

  final AfPlayerService _player;

  StreamSubscription<dynamic>? _eventSub;
  StreamSubscription<dynamic>? _sessionSub;
  final _magnitudeController = StreamController<double>.broadcast();
  bool _attached = false;

  VisualizerService(this._player);

  /// Normalised FFT magnitude stream. Emits [double] in [0.0, 1.0] at
  /// ~60 Hz while the Visualizer is attached and playing.
  Stream<double> get magnitudeStream => _magnitudeController.stream;

  /// Wire up the Visualizer to the player's current audio session.
  ///
  /// Subscribes to [AudioPlayer.androidAudioSessionIdStream] so the
  /// Visualizer automatically re-attaches when ExoPlayer recreates its
  /// audio session (e.g. after a seek on some devices).
  Future<void> attach() async {
    // Subscribe to session ID changes so we re-attach if ExoPlayer
    // recreates its audio session mid-playback.
    _sessionSub ??= _player.audioSessionIdStream.listen((sessionId) async {
      if (sessionId != null && sessionId >= 0) {
        await _attachToSession(sessionId);
      }
    });

    // Also try the current session ID immediately in case the stream
    // won't emit until the next change.
    final current = _player.audioSessionId;
    if (current != null && current >= 0) {
      await _attachToSession(current);
    }
  }

  /// Release the native Visualizer. Call on pause/stop to free the
  /// system audio effect slot.
  Future<void> detach() async {
    if (!_attached) return;
    _attached = false;
    await _eventSub?.cancel();
    _eventSub = null;
    try {
      await _method.invokeMethod<void>('detach');
    } on MissingPluginException {
      // Non-Android / test environment — ignore.
    } catch (e, stack) {
      afLog('audio', 'visualizer detach failed', error: e, stackTrace: stack);
    }
  }

  Future<void> dispose() async {
    await _sessionSub?.cancel();
    _sessionSub = null;
    await detach();
    await _magnitudeController.close();
  }

  // ---------------------------------------------------------------------------

  Future<void> _attachToSession(int sessionId) async {
    // Detach any existing Visualizer before re-attaching.
    if (_attached) await detach();

    try {
      final ok = await _method.invokeMethod<bool>('attach', sessionId);
      if (ok != true) {
        afLog('audio', 'visualizer attach returned false for session=$sessionId');
        return;
      }
      _attached = true;
      afLog('audio', 'visualizer attached session=$sessionId');

      // Subscribe to the FFT event stream.
      _eventSub = _event.receiveBroadcastStream().listen(
        (dynamic value) {
          if (value is double) {
            _magnitudeController.add(value);
          } else if (value is num) {
            _magnitudeController.add(value.toDouble());
          }
        },
        onError: (Object e) {
          afLog('audio', 'visualizer event error: $e');
        },
      );
    } on MissingPluginException {
      // Non-Android / test environment — silently skip.
    } catch (e, stack) {
      afLog('audio', 'visualizer attach failed', error: e, stackTrace: stack);
    }
  }
}
