import 'dart:async';

import 'package:mpv_audio_kit/mpv_audio_kit.dart' show PlayerApi;

import '../../utils/log.dart';

/// Manages audio device routing, nudge logic, and effect re-application
/// after output-device changes.
///
/// On some Android audio outputs (USB DAC, certain Bluetooth codecs)
/// the mpv `af` filter chain detaches from the output pipeline when
/// mpv rebuilds it. Re-issuing the current effects re-attaches the
/// chain.
class AfAudioDeviceManager {

  AfAudioDeviceManager({required PlayerApi player}) : _player = player;
  final PlayerApi _player;
  bool _disposed = false;

  int _nudgeGen = 0;

  /// Last `audio-device` name observed from mpv. Skips duplicate emissions
  /// (mpv re-emits the same device on some property polls).
  String? _lastObservedAudioDevice;

  static const _nudgeDelaysMs = [300, 1000, 2500];

  /// Returns `true` when [deviceName] represents a *real* device change
  /// (not a duplicate emission from mpv polling).
  bool isRealDeviceChange(String deviceName) {
    if (deviceName == _lastObservedAudioDevice) return false;
    _lastObservedAudioDevice = deviceName;
    return true;
  }

  /// Re-apply the current in-memory audio effects to mpv after an
  /// output-device change.
  Future<void> reapplyPersistedEffects() async {
    if (_disposed) return;
    try {
      final current = _player.state.audioEffects;
      await _player.setAudioEffects(current);
      afLog('audio', 're-applied audio effects after device change');
    } catch (e) {
      afLog('audio', 'reapplyPersistedEffects failed', error: e);
    }
  }

  /// Nudge the audio device to recover from Samsung One UI freezes.
  /// Switches briefly to a specific device then back, which forces mpv
  /// to rebuild the audio pipeline and unstick time-pos.
  void nudge() {
    _nudgeGen++;
    unawaited(_nudgeAudioDeviceWithRetry(0, _nudgeGen));
  }

  Future<void> _nudgeAudioDeviceWithRetry(int attempt, int gen) async {
    if (attempt >= _nudgeDelaysMs.length || _disposed) return;

    await Future.delayed(Duration(milliseconds: _nudgeDelaysMs[attempt]));
    if (_disposed || gen != _nudgeGen) return;

    try {
      var current = _player.state.audioDevice;

      if (current.name == 'auto') {
        final devices = _player.state.audioDevices;
        final preferred = devices.where((d) => d.name != 'auto').toList();
        if (preferred.isNotEmpty) {
          current = preferred.firstWhere(
            (d) => d.name == 'aaudio',
            orElse: () => preferred.first,
          );
        }
      }

      await _player.setAudioDevice(current);
      afLog('audio', 'nudged audioDevice: ${current.name} (attempt $attempt)');

      if (attempt == 0 && _player.state.playing) {
        afLog('audio', 'nudge succeeded on first attempt, skipping retries');
        return;
      }
    } catch (e) {
      afLog('audio', 'nudgeAudioDevice attempt $attempt failed', error: e);
    }

    unawaited(_nudgeAudioDeviceWithRetry(attempt + 1, gen));
  }

  void dispose() {
    _disposed = true;
  }
}
