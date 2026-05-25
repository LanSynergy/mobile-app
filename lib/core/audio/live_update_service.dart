import 'package:flutter/services.dart';

/// Dart client wrapper for the native `LiveUpdatePlugin` implementing Android 16
/// (API 36) Promoted Ongoing Notifications (Live Updates) for playback tracking.
class LiveUpdateService {
  static const _channel = MethodChannel('aetherfin.live_update');
  static bool? _cachedIsSupported;

  /// Returns `true` if the device supports the Android 16 Live Updates API.
  static Future<bool> isSupported() async {
    if (_cachedIsSupported != null) return _cachedIsSupported!;
    try {
      final supported = await _channel.invokeMethod<bool>('isSupported') ?? false;
      _cachedIsSupported = supported;
      return supported;
    } catch (_) {
      return false;
    }
  }

  /// Returns `true` if the manufacturer is Samsung.
  static Future<bool> isSamsungDevice() async {
    try {
      return await _channel.invokeMethod<bool>('isSamsungDevice') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Requests notification posting permission (`POST_NOTIFICATIONS`) on Android 13+.
  /// Returns `true` if the permission is granted.
  static Future<bool> requestPermission() async {
    try {
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Posts a new ongoing progress notification for the current track.
  static Future<bool> start({
    required String title,
    required String artist,
    required int durationMs,
    required int positionMs,
    required bool isPlaying,
    required String shortCriticalText,
    String? artworkPath,
  }) async {
    try {
      return await _channel.invokeMethod<bool>('start', {
        'title': title,
        'artist': artist,
        'durationMs': durationMs,
        'positionMs': positionMs,
        'isPlaying': isPlaying,
        'shortCriticalText': shortCriticalText,
        'artworkPath': artworkPath,
      }) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Updates the progress of the active ongoing notification.
  static Future<bool> update({
    required String title,
    required String artist,
    required int durationMs,
    required int positionMs,
    required bool isPlaying,
    required String shortCriticalText,
    String? artworkPath,
  }) async {
    try {
      return await _channel.invokeMethod<bool>('update', {
        'title': title,
        'artist': artist,
        'durationMs': durationMs,
        'positionMs': positionMs,
        'isPlaying': isPlaying,
        'shortCriticalText': shortCriticalText,
        'artworkPath': artworkPath,
      }) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Cancels the live update notification.
  static Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
  }

  /// Formats duration milliseconds into "M:SS" string for the status-bar chip.
  static String formatDuration(int ms) {
    if (ms <= 0) return '0:00';
    final totalSeconds = ms ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
