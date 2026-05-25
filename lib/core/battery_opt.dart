import 'package:flutter/services.dart';
import '../utils/log.dart';

/// Dart bridge to [BatteryOptPlugin] (aetherfin.battery_opt MethodChannel).
///
/// Used by HomeScreen to request battery-optimization exemption on first
/// visit — required for reliable auto-advance when the screen is off on
/// Samsung, Xiaomi, and other OEMs that aggressively enforce Doze.
abstract final class BatteryOpt {
  static const _channel = MethodChannel('aetherfin.battery_opt');

  /// Returns true if the app is already exempt from battery optimizations.
  static Future<bool> isIgnoring() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'isIgnoringBatteryOptimizations',
      );
      return result ?? false;
    } on PlatformException catch (e, stack) {
      afLog(
        'boot',
        'BatteryOpt.isIgnoring failed: ${e.message}',
        error: e,
        stackTrace: stack,
      );
      return false;
    }
  }

  /// Shows the system "Allow background activity?" dialog.
  ///
  /// Returns true if the intent was dispatched (user may still decline).
  /// Returns false if already exempt or the activity is unavailable.
  static Future<bool> requestIgnore() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'requestIgnoreBatteryOptimizations',
      );
      afLog('boot', 'BatteryOpt.requestIgnore dispatched=${result ?? false}');
      return result ?? false;
    } on PlatformException catch (e, stack) {
      afLog(
        'boot',
        'BatteryOpt.requestIgnore failed: ${e.message}',
        error: e,
        stackTrace: stack,
      );
      return false;
    }
  }
}
