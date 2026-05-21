import 'dart:async';

import 'package:mpv_audio_kit/mpv_audio_kit.dart' show Player;

import '../../utils/log.dart';

/// Stores a snapshot of playback position for elapsed-time extrapolation.
/// Used when mpv's observe_property/getRawProperty for time-pos stalls.
class _PositionAnchor {
  Duration lastKnownPos = Duration.zero;
  DateTime lastUpdateTime = DateTime.now();
  bool wasPlaying = false;
}

/// Manages position polling, extrapolation, and stale detection.
///
/// Polls mpv at 200ms intervals. Falls back to Dart-side elapsed-time
/// extrapolation when mpv returns 0 or when the same non-zero position
/// repeats across several ticks (Samsung One UI freeze workaround).
class AfPositionTracker {
  final Player _player;
  final bool Function() _shouldAdvancePosition;

  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  Stream<Duration> get positionStream => _positionController.stream;

  final _positionAnchor = _PositionAnchor();
  Timer? _positionPollTimer;
  bool _isSeeking = false;
  Timer? _seekResetTimer;
  bool _isPolling = false;

  Duration? _lastRawPolledPos;
  int _staleRawPollTicks = 0;
  static const _rawStaleTolerance = Duration(milliseconds: 250);
  static const _rawStaleAfterTicks = 4;

  bool _disposed = false;

  AfPositionTracker({
    required Player player,
    required bool Function() shouldAdvancePosition,
  })  : _player = player,
        _shouldAdvancePosition = shouldAdvancePosition;

  void start() {
    _positionPollTimer =
        Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (_disposed) return;
      _pollAndEmitPosition();
    });
  }

  void stop() {
    _positionPollTimer?.cancel();
    _positionPollTimer = null;
  }

  bool get isSeeking => _isSeeking;
  Duration get lastKnownPosition => _positionAnchor.lastKnownPos;

  void onSeek(Duration position) {
    _isSeeking = true;
    final now = DateTime.now();
    _positionAnchor.lastKnownPos = position;
    _positionAnchor.lastUpdateTime = now;
    _resetRawPositionStaleDetector(position);
    _positionController.add(position);

    _seekResetTimer?.cancel();
    _seekResetTimer = Timer(const Duration(milliseconds: 300), () {
      if (!_disposed) _isSeeking = false;
    });
  }

  void onTrackChanged() {
    _positionAnchor.lastKnownPos = Duration.zero;
    _positionAnchor.lastUpdateTime = DateTime.now();
    _positionAnchor.wasPlaying = false;
    _positionController.add(Duration.zero);
    _resetRawPositionStaleDetector(Duration.zero);
  }

  void onPlay() {
    _positionAnchor.wasPlaying = true;
  }

  void updateKnownPosition(Duration pos) {
    _positionAnchor.lastKnownPos = pos;
    _positionAnchor.lastUpdateTime = DateTime.now();
  }

  void onPause() {
    _positionAnchor.wasPlaying = false;
  }

  void onStop() {
    _positionAnchor.wasPlaying = false;
    _positionAnchor.lastKnownPos = Duration.zero;
    _positionAnchor.lastUpdateTime = DateTime.now();
    _resetRawPositionStaleDetector(Duration.zero);
    _positionController.add(Duration.zero);
  }

  Future<Duration> getRawPosition() async {
    try {
      final raw = await _player.getRawProperty('time-pos');
      if (raw == null) return Duration.zero;
      final secs = double.tryParse(raw);
      if (secs == null || secs < 0) return Duration.zero;
      return Duration(milliseconds: (secs * 1000).round());
    } catch (_) {
      return Duration.zero;
    }
  }

  Future<Duration> getRawDuration() async {
    try {
      final raw = await _player.getRawProperty('duration');
      if (raw == null) return Duration.zero;
      final secs = double.tryParse(raw);
      if (secs == null || secs <= 0) return Duration.zero;
      return Duration(milliseconds: (secs * 1000).round());
    } catch (_) {
      return Duration.zero;
    }
  }

  void _resetRawPositionStaleDetector([Duration? seed]) {
    _lastRawPolledPos = seed;
    _staleRawPollTicks = 0;
  }

  bool _isRawPositionStale(Duration rawPos) {
    final previous = _lastRawPolledPos;
    _lastRawPolledPos = rawPos;

    if (previous == null) {
      _staleRawPollTicks = 0;
      return false;
    }

    final deltaMs = (rawPos - previous).inMilliseconds.abs();
    if (deltaMs <= _rawStaleTolerance.inMilliseconds) {
      _staleRawPollTicks++;
    } else {
      _staleRawPollTicks = 0;
    }

    return _staleRawPollTicks >= _rawStaleAfterTicks;
  }

  Future<void> _pollAndEmitPosition() async {
    if (_isSeeking || _isPolling) return;
    _isPolling = true;

    try {
      final rawPos = await getRawPosition();
      final now = DateTime.now();
      final playing = _player.state.playing;
      final shouldAdvance = playing || _shouldAdvancePosition();

      if (rawPos > Duration.zero) {
        final behind = rawPos.inMilliseconds + 1000 <
            _positionAnchor.lastKnownPos.inMilliseconds;
        final rawBehindAnchor =
            shouldAdvance && behind;
        final rawStale =
            shouldAdvance && (_isRawPositionStale(rawPos) || rawBehindAnchor);

        if (!rawStale && (!behind || shouldAdvance)) {
          _positionAnchor.lastKnownPos = rawPos;
          _positionAnchor.lastUpdateTime = now;
          _positionAnchor.wasPlaying = playing;
          _positionController.add(rawPos);
          return;
        }

        if (_staleRawPollTicks == _rawStaleAfterTicks || rawBehindAnchor) {
          afLog('audio',
              'raw time-pos stale at ${rawPos.inMilliseconds}ms; using extrapolated position');
        }
      }

      if (shouldAdvance) {
        final dur = _player.state.duration;
        if (dur > Duration.zero && _positionAnchor.lastKnownPos >= dur) {
          _positionAnchor.lastKnownPos = dur;
          _positionController.add(dur);
          return;
        }

        final elapsed = now.difference(_positionAnchor.lastUpdateTime);
        final speed = _player.state.rate;
        final extrapolated = _positionAnchor.lastKnownPos +
            Duration(milliseconds: (elapsed.inMilliseconds * speed).round());
        final durCap = dur > Duration.zero ? dur : const Duration(hours: 1);
        final capped = extrapolated > durCap ? durCap : extrapolated;
        _positionAnchor.lastKnownPos = capped;
        _positionAnchor.lastUpdateTime = now;
        _positionAnchor.wasPlaying = true;
        _positionController.add(capped);
      } else if (rawPos == Duration.zero) {
        _resetRawPositionStaleDetector(Duration.zero);
      }
    } finally {
      _isPolling = false;
    }
  }

  void dispose() {
    _disposed = true;
    _positionPollTimer?.cancel();
    _seekResetTimer?.cancel();
    _positionController.close();
  }
}
