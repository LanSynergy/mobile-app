import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/services.dart';

import '../../utils/log.dart';
import '../jellyfin/models/items.dart';
import 'player_service.dart';

/// Bridges [AfPlayerService] state into the native Android 16 "Live
/// Updates" / Promoted Ongoing Notifications system via the
/// `aetherfin.live_update` MethodChannel.
///
/// On Android 16+ (API 36): publishes a [Notification.ProgressStyle]
/// notification that the OS surfaces as a status-bar chip and
/// lock-screen tile while playback is ongoing.
///
/// On Android ≤15, iOS, or anywhere else: every method is a no-op.
/// The existing `audio_service` `MediaStyle` notification continues to
/// handle lock-screen media controls unchanged on those targets.
///
/// Why a separate notification (and not extending audio_service's)?
/// Per the Live Updates docs, only Standard / BigTextStyle / CallStyle
/// / ProgressStyle / MetricStyle notifications qualify for promotion.
/// `MediaStyle` is intentionally not in that list, and a notification
/// can only carry one Style. So this service publishes a parallel
/// ProgressStyle notification dedicated to the chip surface; the
/// audio_service media notification keeps owning the transport
/// controls.
class LiveUpdateService {
  static const _channel = MethodChannel('aetherfin.live_update');

  /// Don't push position updates more often than this — matches the
  /// platform's recommended rate cap. The native side throttles too,
  /// but coalescing here cuts MethodChannel chatter.
  static const _minUpdateInterval = Duration(seconds: 5);

  final AfPlayerService _player;
  bool _supported = false;
  bool _live = false;
  bool _disposed = false;
  /// In-flight guard: prevents concurrent MethodChannel calls from
  /// overlapping when rapid position events arrive faster than the
  /// native side can process them.
  bool _updating = false;
  AfTrack? _track;
  Duration _lastPositionPushed = Duration.zero;
  DateTime _lastPushAt = DateTime.fromMillisecondsSinceEpoch(0);
  final List<StreamSubscription<void>> _subs = [];

  LiveUpdateService(this._player);

  /// Call once during app boot — probes the native side for support,
  /// then wires up listeners on the player streams. Cheap on
  /// unsupported platforms (a single MethodChannel round-trip + an
  /// early return).
  Future<void> attach() async {
    if (!_isAndroid()) return;

    // Samsung One UI already promotes the audio_service MediaStyle
    // notification to a status-bar chip natively. Posting a second
    // ProgressStyle notification just creates a duplicate in the shade.
    if (await _checkIsSamsung()) {
      _log('Samsung detected — skipping LiveUpdate (One UI handles chip)');
      return;
    }

    try {
      final ok = await _channel.invokeMethod<bool>('isSupported');
      _supported = ok ?? false;
    } on PlatformException catch (e) {
      _supported = false;
      _log('isSupported failed: $e');
    } on MissingPluginException {
      _supported = false;
    }
    if (!_supported) return;

    // Request POST_NOTIFICATIONS permission on Android 13+.
    // Stock Android shows a dialog; if denied, the live update won't post.
    unawaited(_requestPermission());

    _subs.add(_player.currentTrackStream.listen((t) {
      _track = t;
      if (t == null) {
        unawaited(stop());
      } else {
        unawaited(_startOrUpdate(force: true));
      }
    }));
    _subs.add(_player.positionStream.listen((_) {
      unawaited(_startOrUpdate());
    }));
    _subs.add(_player.playingStream.listen((_) {
      // State transitions are the user's signal that something
      // changed; flush immediately rather than wait out the 5s window.
      unawaited(_startOrUpdate(force: true));
    }));
    // When artwork becomes available (async download), refresh the chip.
    _subs.add(_player.mediaItem.listen((item) {
      if (item?.artUri != null && item!.artUri!.scheme == 'file') {
        unawaited(_startOrUpdate(force: true));
      }
    }));
  }

  /// Tear down listeners and cancel the notification.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await stop();
  }

  /// Immediately cancel the live-update notification, if any.
  Future<void> stop() async {
    if (!_supported || !_live) return;
    _live = false;
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException catch (e) {
      _log('stop failed: $e');
    } on MissingPluginException {
      // pass
    }
  }

  // -------------------------------------------------------------------------
  // Internals
  // -------------------------------------------------------------------------

  /// Request POST_NOTIFICATIONS permission. On Samsung this is auto-granted;
  /// on stock Android 13+ it shows a system dialog. If denied, the live
  /// update notification simply won't appear — playback is unaffected.
  Future<void> _requestPermission() async {
    try {
      final granted =
          await _channel.invokeMethod<bool>('requestPermission') ?? false;
      _log('requestPermission result=$granted');
    } on PlatformException catch (e) {
      _log('requestPermission failed: $e');
    } on MissingPluginException {
      // pass
    }
  }

  bool _isAndroid() {
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  /// Samsung One UI already promotes MediaStyle notifications to a
  /// status-bar chip. Posting a ProgressStyle duplicate is redundant.
  /// Checks via MethodChannel since Dart can't read Build.MANUFACTURER.
  Future<bool> _checkIsSamsung() async {
    try {
      final result = await _channel.invokeMethod<bool>('isSamsungDevice');
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Returns the local file path of the current artwork, if available.
  /// Checks the player's mediaItem artUri for a file:// URI.
  String? _resolveArtworkPath() {
    try {
      final item = _player.mediaItem.value;
      final uri = item?.artUri;
      if (uri != null && uri.scheme == 'file') {
        return uri.toFilePath();
      }
    } catch (_) {}
    return null;
  }

  Future<void> _startOrUpdate({bool force = false}) async {
    if (!_supported || _disposed) return;
    // Serialize: skip if a previous update is still in flight.
    // This prevents MethodChannel call pileups from rapid position events.
    if (_updating) return;
    final track = _track ?? _player.currentTrack;
    if (track == null) return;
    final duration = track.duration;
    if (duration <= Duration.zero) return;

    final now = DateTime.now();
    final position = _player.position;
    if (!force &&
        now.difference(_lastPushAt) < _minUpdateInterval &&
        (position - _lastPositionPushed).abs() < _minUpdateInterval) {
      return;
    }
    _lastPushAt = now;
    _lastPositionPushed = position;

    final clampedPos =
        position < Duration.zero ? Duration.zero : (position > duration ? duration : position);

    final args = <String, Object?>{
      'title': track.title,
      'artist': track.artistName,
      'durationMs': duration.inMilliseconds,
      'positionMs': clampedPos.inMilliseconds,
      'isPlaying': _isPlaying(),
      'shortCriticalText': '${_fmtClock(clampedPos)} / ${_fmtClock(duration)}',
      'artworkPath': _resolveArtworkPath(),
    };

    _updating = true;
    try {
      final method = _live ? 'update' : 'start';
      final ok = await _channel.invokeMethod<bool>(method, args);
      if (ok == true) {
        _live = true;
      } else if (method == 'start') {
        _log('start returned false — likely missing POST_NOTIFICATIONS');
      }
    } on PlatformException catch (e) {
      _log('$_live ? update : start failed: $e');
    } on MissingPluginException {
      _supported = false;
      _live = false;
    } finally {
      _updating = false;
    }
  }

  bool _isPlaying() => _player.isPlaying;

  String _fmtClock(Duration d) {
    if (d.isNegative) d = Duration.zero;
    final s = d.inSeconds;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final ss = s % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    if (h > 0) return '$h:${two(m)}:${two(ss)}';
    return '$m:${two(ss)}';
  }

  void _log(String msg) {
    if (!kDebugMode) return;
    afLog('live_update', msg);
  }
}
