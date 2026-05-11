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
/// ## Permission
///
/// `RECORD_AUDIO` is required by the Android Visualizer API. This service
/// calls `requestPermission()` on the Kotlin side before attaching — the
/// plugin shows the system dialog if needed and resolves the future with
/// the result. If the user denies, [magnitudeStream] simply emits nothing
/// and the artwork falls back to a static scale.
///
/// ## Lifecycle
///
/// 1. Call [attach] once playback starts. Safe to call multiple times.
/// 2. Call [detach] on pause/stop to free the audio effect slot.
/// 3. Call [dispose] when the owning service is torn down.
class VisualizerService {
  static const _method = MethodChannel('aetherfin.visualizer');
  static const _event  = EventChannel('aetherfin.visualizer/fft');

  final AfPlayerService _player;

  StreamSubscription<dynamic>? _eventSub;
  StreamSubscription<dynamic>? _sessionSub;
  final _magnitudeController = StreamController<double>.broadcast();
  bool _attached = false;
  bool _permissionGranted = false;
  bool _permissionChecked = false;

  VisualizerService(this._player);

  /// Normalised FFT magnitude stream. Emits [double] in [0.0, 1.0] at
  /// ~60 Hz while the Visualizer is attached and playing.
  Stream<double> get magnitudeStream => _magnitudeController.stream;

  /// Request RECORD_AUDIO permission (if not already granted), then wire
  /// the Visualizer to the player's current audio session.
  Future<void> attach() async {
    // Ensure permission before doing anything else.
    if (!_permissionChecked) {
      _permissionChecked = true;
      _permissionGranted = await _requestPermission();
      if (!_permissionGranted) {
        afLog('audio', 'visualizer: RECORD_AUDIO denied — FFT disabled');
        return;
      }
    } else if (!_permissionGranted) {
      return;
    }

    // Subscribe to session ID changes so we re-attach if ExoPlayer
    // recreates its audio session mid-playback.
    _sessionSub ??= _player.audioSessionIdStream.listen((sessionId) async {
      if (sessionId != null && sessionId >= 0) {
        await _attachToSession(sessionId);
      }
    });

    // Try the current session ID immediately.
    final current = _player.audioSessionId;
    if (current != null && current >= 0) {
      await _attachToSession(current);
    }
  }

  /// Release the native Visualizer.
  Future<void> detach() async {
    if (!_attached) return;
    _attached = false;
    await _eventSub?.cancel();
    _eventSub = null;
    try {
      await _method.invokeMethod<void>('detach');
    } on MissingPluginException {
      // Non-Android / test environment.
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

  Future<bool> _requestPermission() async {
    try {
      // First check without showing a dialog.
      final has = await _method.invokeMethod<bool>('hasPermission');
      if (has == true) return true;
      // Not granted — show the system dialog.
      final granted = await _method.invokeMethod<bool>('requestPermission');
      return granted == true;
    } on MissingPluginException {
      return false;
    } catch (e, stack) {
      afLog('audio', 'visualizer permission check failed',
          error: e, stackTrace: stack);
      return false;
    }
  }

  Future<void> _attachToSession(int sessionId) async {
    if (_attached) await detach();
    try {
      final ok = await _method.invokeMethod<bool>('attach', sessionId);
      if (ok != true) {
        afLog('audio',
            'visualizer attach returned false for session=$sessionId');
        return;
      }
      _attached = true;
      afLog('audio', 'visualizer attached session=$sessionId');

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
      // Non-Android / test environment.
    } catch (e, stack) {
      afLog('audio', 'visualizer attach failed', error: e, stackTrace: stack);
    }
  }
}
