import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show FftFrame;

import '../design_tokens/tokens.dart';
import '../state/providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FftWaveform — live FFT visualiser + progress scrubber
//
// Architecture
// ────────────
// • A [_WaveformNotifier] (ChangeNotifier) owns all animation state:
//   FFT smoothing, idle oscillation, drag progress.
//   It drives repaints via CustomPainter(repaint: notifier) — no setState.
//
// • The ticker only runs when playing or dragging. It stops automatically
//   when paused and no FFT frames are arriving.
//
// • The smoothed Float32List is mutated in-place — no per-frame allocation.
//   shouldRepaint() is always false because repaint is driven by the
//   Listenable, not structural comparison.
//
// • FFT values are validated (NaN/Infinity guard) before smoothing.
//
// • Reduced-motion accessibility: idle animation disabled when
//   MediaQuery.disableAnimations is true.
//
// Public API (unchanged):
//   peaks, progress, isPlaying, playedColor, unplayedColor,
//   height, onScrub, onScrubEnd
// ─────────────────────────────────────────────────────────────────────────────

class FftWaveform extends ConsumerStatefulWidget {
  final List<int> peaks;
  final double progress;
  final Color playedColor;
  final Color unplayedColor;
  final double height;
  final ValueChanged<double>? onScrub;
  final ValueChanged<double>? onScrubEnd;
  final bool isPlaying;

  const FftWaveform({
    super.key,
    required this.peaks,
    required this.progress,
    this.playedColor   = AfColors.indigo300,
    this.unplayedColor = AfColors.textTertiary,
    this.height        = 72,
    this.onScrub,
    this.onScrubEnd,
    this.isPlaying     = true,
  });

  @override
  ConsumerState<FftWaveform> createState() => _FftWaveformState();
}

class _FftWaveformState extends ConsumerState<FftWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;
  late final _WaveformNotifier _notifier;
  StreamSubscription<FftFrame>? _fftSub;

  @override
  void initState() {
    super.initState();
    _notifier = _WaveformNotifier(widget.peaks);
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_onTick);
    _maybeStartTicker();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _fftSub?.cancel();
    final svc = ref.read(playerServiceProvider);
    _fftSub = svc.spectrumStream.listen((frame) {
      _notifier._setFftTarget(frame.bands);
      _maybeStartTicker();
    });
  }

  @override
  void didUpdateWidget(FftWaveform old) {
    super.didUpdateWidget(old);
    if (old.peaks != widget.peaks) {
      _notifier._resetPeaks(widget.peaks);
    }
    if (old.isPlaying != widget.isPlaying) {
      _maybeStartTicker();
    }
    // Forward progress/color changes to notifier so painter sees them.
    _notifier._progress = widget.progress;
    _notifier._playedColor   = widget.playedColor;
    _notifier._unplayedColor = widget.unplayedColor;
  }

  @override
  void dispose() {
    _fftSub?.cancel();
    _ticker.dispose();
    _notifier.dispose();
    super.dispose();
  }

  void _maybeStartTicker() {
    if ((widget.isPlaying || _notifier._dragging) && !_ticker.isAnimating) {
      _ticker.repeat();
    }
  }

  void _onTick() {
    if (!mounted) return;
    final reducedMotion = MediaQuery.of(context).disableAnimations;
    final changed = _notifier._tick(
      isPlaying: widget.isPlaying,
      reducedMotion: reducedMotion,
    );
    // Stop ticker when paused and all bars have settled.
    if (!changed && !widget.isPlaying && !_notifier._dragging) {
      _ticker.stop();
    }
  }

  // ── Gesture handlers ──────────────────────────────────────────────────────

  void _handleDragStart(DragStartDetails d) {
    HapticFeedback.selectionClick();
    _notifier._setDrag(true, _toProgress(d.localPosition.dx));
    widget.onScrub?.call(_notifier._dragProgress);
    _maybeStartTicker();
  }

  void _handleDragUpdate(DragUpdateDetails d) {
    _notifier._setDrag(true, _toProgress(d.localPosition.dx));
    widget.onScrub?.call(_notifier._dragProgress);
  }

  void _handleDragEnd(DragEndDetails _) {
    widget.onScrubEnd?.call(_notifier._dragProgress);
    _notifier._setDrag(false, _notifier._dragProgress);
  }

  void _handleTap(TapDownDetails d) {
    HapticFeedback.selectionClick();
    final p = _toProgress(d.localPosition.dx);
    widget.onScrub?.call(p);
    widget.onScrubEnd?.call(p);
  }

  double _toProgress(double dx) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || box.size.width <= 0) return 0;
    return (dx / box.size.width).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    // Sync progress/colors on every build (cheap field writes).
    _notifier._progress      = widget.progress;
    _notifier._playedColor   = widget.playedColor;
    _notifier._unplayedColor = widget.unplayedColor;

    return RepaintBoundary(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: _handleDragStart,
        onHorizontalDragUpdate: _handleDragUpdate,
        onHorizontalDragEnd: _handleDragEnd,
        onTapDown: _handleTap,
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: CustomPaint(
            painter: _WaveformPainter(notifier: _notifier),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _WaveformNotifier — owns all mutable animation state.
// Drives repaints via ChangeNotifier (repaint: notifier in CustomPainter).
// No per-frame allocation — all buffers are pre-allocated.
//
// Architecture
// ────────────
// Layer 1 — Raw FFT truth (never mutated between frames)
//   _fftTarget: the latest FFT snapshot from mpv. Treated as immutable
//   instantaneous truth. Bars chase this, not the other way around.
//
// Layer 2 — Independent visual envelopes
//   Each bar owns its own value + velocity. Attack and decay are
//   frequency-dependent so bass moves heavy and treble flickers.
//   This is what makes bars feel independent instead of "one organism."
//
// Layer 3 — Psychoacoustic weighting
//   Bass bins are amplified and decay slowly (human hearing is bass-heavy).
//   Treble bins decay fast and flicker. Mid bins are neutral.
// ─────────────────────────────────────────────────────────────────────────────

class _WaveformNotifier extends ChangeNotifier {
  // ── Layer 1: Raw FFT truth ────────────────────────────────────────────────
  // Written by the FFT stream, read by _tick(). Never smoothed in-place.
  Float32List? _fftTarget;
  bool _hasFft = false;

  // ── Layer 2: Independent visual envelopes ─────────────────────────────────
  // smoothed[i] = current visual height of bar i, in [0, 1].
  // Mutated in-place each tick — no allocation.
  late Float32List smoothed;

  // Per-bar attack lerp — pre-computed once in _initEnvelopes.
  late Float32List _attack;
  // Per-bar decay lerp — pre-computed once in _initEnvelopes.
  late Float32List _decay;

  // ── Idle animation phase ──────────────────────────────────────────────────
  double _idlePhase = 0.0;

  // ── Drag state ────────────────────────────────────────────────────────────
  bool   _dragging     = false;
  double _dragProgress = 0.0;

  // ── Display state (written by widget, read by painter) ───────────────────
  double _progress      = 0.0;
  Color  _playedColor   = AfColors.indigo300;
  Color  _unplayedColor = AfColors.textTertiary;

  // ── Global constants ──────────────────────────────────────────────────────
  static const double _minHeight    = 0.05;
  static const double _settleThresh = 0.0008;

  // ── FFT topology ──────────────────────────────────────────────────────────
  // Always 64 bars = FFT band count. Bar i = FFT bin i.
  static const int _barCount = 64;

  // Frequency region boundaries (bin indices):
  //   bass:   0–7   (~20–250 Hz)   — heavy, slow decay
  //   low-mid: 8–15  (~250–500 Hz)  — medium
  //   mid:    16–31  (~500 Hz–4 kHz) — neutral
  //   treble: 32–63  (~4–20 kHz)   — fast flicker
  static const int _bassEnd    = 8;
  static const int _lowMidEnd  = 16;
  static const int _midEnd     = 32;

  _WaveformNotifier(List<int> peaks) {
    _initEnvelopes(peaks);
  }

  void _initEnvelopes(List<int> peaks) {
    smoothed = Float32List(_barCount);
    _attack  = Float32List(_barCount);
    _decay   = Float32List(_barCount);

    for (var i = 0; i < _barCount; i++) {
      // Seed visual height from peaks if available.
      final peakVal = (i < peaks.length)
          ? (peaks[i] / 100.0).clamp(_minHeight, 1.0) * 0.5
          : _minHeight;
      smoothed[i] = peakVal;

      // ── Layer 3: Psychoacoustic per-bar envelope parameters ──────────────
      // Bass: slow attack (weight builds), very slow decay (sustain).
      // Low-mid: medium.
      // Mid: neutral.
      // Treble: fast attack + fast decay = flicker/sparkle.
      if (i < _bassEnd) {
        _attack[i] = 0.65;
        _decay[i]  = 0.08;
      } else if (i < _lowMidEnd) {
        _attack[i] = 0.72;
        _decay[i]  = 0.14;
      } else if (i < _midEnd) {
        _attack[i] = 0.78;
        _decay[i]  = 0.20;
      } else {
        // Treble: snappy attack, fast decay — hi-hats flicker independently.
        _attack[i] = 0.88;
        _decay[i]  = 0.32;
      }
    }
  }

  void _resetPeaks(List<int> peaks) => _initEnvelopes(peaks);

  void _setFftTarget(Float32List bands) {
    _fftTarget = bands;
    _hasFft = true;
  }

  void _setDrag(bool dragging, double progress) {
    _dragging     = dragging;
    _dragProgress = progress;
    notifyListeners();
  }

  double get displayProgress =>
      _dragging ? _dragProgress : _progress.clamp(0.0, 1.0);

  /// Advance one frame. Returns true if any bar is still moving.
  bool _tick({required bool isPlaying, required bool reducedMotion}) {
    var anyMoving = false;

    if (_hasFft && _fftTarget != null) {
      final bands = _fftTarget!;

      for (var i = 0; i < _barCount; i++) {
        // ── Layer 1: Raw FFT truth ──────────────────────────────────────────
        // Direct 1:1 mapping: bar i = FFT bin i. No resampling.
        final raw = i < bands.length ? bands[i] : 0.0;
        final safeRaw = raw.isFinite ? raw.clamp(0.0, 1.0) : 0.0;

        // ── Layer 3: Psychoacoustic amplitude weighting ─────────────────────
        // Bass bins are amplified (human hearing is bass-heavy).
        // Treble bins are slightly attenuated to prevent harsh spikes.
        final double weighted;
        if (i < _bassEnd) {
          weighted = (safeRaw * 1.6).clamp(0.0, 1.0);
        } else if (i < _lowMidEnd) {
          weighted = (safeRaw * 1.2).clamp(0.0, 1.0);
        } else if (i < _midEnd) {
          weighted = safeRaw;
        } else {
          weighted = (safeRaw * 0.85).clamp(0.0, 1.0);
        }

        final target = weighted.clamp(_minHeight, 1.0);

        // ── Layer 2: Independent per-bar envelope ───────────────────────────
        // Each bar uses its own attack/decay — NOT a shared global lerp.
        // This is what makes bass move heavy and treble flicker independently.
        final lerp = target > smoothed[i] ? _attack[i] : _decay[i];
        final next = smoothed[i] + (target - smoothed[i]) * lerp;
        if ((next - smoothed[i]).abs() > _settleThresh) anyMoving = true;
        smoothed[i] = next;
      }
    } else if (isPlaying && !reducedMotion) {
      // Idle: gentle sine-wave oscillation. Each bar still uses its own
      // decay so the idle animation also feels frequency-differentiated.
      _idlePhase = (_idlePhase + 0.03) % (6.2832); // 2π
      for (var i = 0; i < _barCount; i++) {
        final peak   = smoothed[i].clamp(_minHeight, 1.0);
        final target = peak * (0.4 + 0.22 * math.sin(_idlePhase + i * 0.25));
        final next   = smoothed[i] + (target - smoothed[i]) * _decay[i];
        if ((next - smoothed[i]).abs() > _settleThresh) anyMoving = true;
        smoothed[i] = next;
      }
    }
    // Paused + no FFT: bars hold position. No animation.

    notifyListeners();
    return anyMoving;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _WaveformPainter
//
// Repaint is driven by _WaveformNotifier (Listenable).
// shouldRepaint() always returns false — structural comparison is unnecessary
// because the Listenable handles invalidation.
// ─────────────────────────────────────────────────────────────────────────────

class _WaveformPainter extends CustomPainter {
  final _WaveformNotifier notifier;

  static const double _barGapFraction  = 0.35;
  static const double _minBarHeight    = 3.0;
  static const double _headWidth       = 2.0;
  static const double _thumbRadius     = 5.0;
  static const double _thumbRadiusDrag = 7.5;
  static const double _glowRadius      = 10.0;

  _WaveformPainter({required this.notifier}) : super(repaint: notifier);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final smoothed = notifier.smoothed;
    if (smoothed.isEmpty) return;

    final barCount  = smoothed.length;
    final barWidth  = size.width / (barCount + _barGapFraction * (barCount - 1));
    final gap       = barWidth * _barGapFraction;
    final centerY   = size.height / 2;
    final progress  = notifier.displayProgress;
    final headBarF  = progress * barCount;
    final headX     = progress * size.width;
    final isDragging = notifier._dragging;

    final playedPaint = Paint()
      ..color = notifier._playedColor
      ..style = PaintingStyle.fill;
    final unplayedPaint = Paint()
      ..color = notifier._unplayedColor.withValues(alpha: 0.28)
      ..style = PaintingStyle.fill;
    final capRadius = Radius.circular(barWidth / 2);

    // ── Bars ─────────────────────────────────────────────────────────────
    for (var i = 0; i < barCount; i++) {
      final amp  = smoothed[i].clamp(_minBarHeight / size.height, 1.0);
      final h    = math.max(_minBarHeight, size.height * amp);
      final x    = i * (barWidth + gap);
      final rect = Rect.fromLTWH(x, centerY - h / 2, barWidth, h);

      final Paint paint;
      if (i < headBarF.floor()) {
        paint = playedPaint;
      } else if (i == headBarF.floor()) {
        final frac = headBarF - headBarF.floor();
        paint = Paint()
          ..color = Color.lerp(unplayedPaint.color, playedPaint.color, frac)!
          ..style = PaintingStyle.fill;
      } else {
        paint = unplayedPaint;
      }

      canvas.drawRRect(RRect.fromRectAndRadius(rect, capRadius), paint);
    }

    // ── Playhead glow ────────────────────────────────────────────────────
    canvas.drawRect(
      Rect.fromLTWH(headX - _glowRadius, 0, _glowRadius * 2, size.height),
      Paint()
        ..color = notifier._playedColor
            .withValues(alpha: isDragging ? 0.22 : 0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // ── Playhead line ────────────────────────────────────────────────────
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(headX - _headWidth / 2, 0, _headWidth, size.height),
        const Radius.circular(1),
      ),
      Paint()
        ..color = isDragging
            ? AfColors.textPrimary
            : notifier._playedColor.withValues(alpha: 0.9)
        ..style = PaintingStyle.fill,
    );

    // ── Scrub thumb ──────────────────────────────────────────────────────
    final thumbR = isDragging ? _thumbRadiusDrag : _thumbRadius;
    if (isDragging) {
      canvas.drawCircle(
        Offset(headX, centerY),
        thumbR + 7,
        Paint()
          ..color = notifier._playedColor.withValues(alpha: 0.22)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
    canvas.drawCircle(
      Offset(headX, centerY),
      thumbR,
      Paint()
        ..color = AfColors.textPrimary
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_WaveformPainter _) => false;
  // Repaint is driven by the Listenable (notifier) — structural comparison
  // is unnecessary and would break if we ever stop allocating per frame.
}

// ─────────────────────────────────────────────────────────────────────────────
// Waveform — static peaks-only scrubber (Queue, mini-player, etc.)
//
// Same architecture: ChangeNotifier drives repaints, no setState.
// Ticker stops when paused and bars have settled.
// ─────────────────────────────────────────────────────────────────────────────

class Waveform extends StatefulWidget {
  final List<int> peaks;
  final double progress;
  final Color playedColor;
  final Color unplayedColor;
  final double height;
  final ValueChanged<double>? onScrub;
  final ValueChanged<double>? onScrubEnd;
  final bool isPlaying;

  const Waveform({
    super.key,
    required this.peaks,
    required this.progress,
    this.playedColor   = AfColors.indigo300,
    this.unplayedColor = AfColors.textTertiary,
    this.height        = 72,
    this.onScrub,
    this.onScrubEnd,
    this.isPlaying     = true,
  });

  @override
  State<Waveform> createState() => _WaveformState();
}

class _WaveformState extends State<Waveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;
  late final _WaveformNotifier _notifier;

  @override
  void initState() {
    super.initState();
    _notifier = _WaveformNotifier(widget.peaks);
    _notifier._progress      = widget.progress;
    _notifier._playedColor   = widget.playedColor;
    _notifier._unplayedColor = widget.unplayedColor;
    _ctl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_onTick);
    if (widget.isPlaying) _ctl.repeat();
  }

  @override
  void didUpdateWidget(covariant Waveform old) {
    super.didUpdateWidget(old);
    if (old.peaks != widget.peaks) _notifier._resetPeaks(widget.peaks);
    _notifier._progress      = widget.progress;
    _notifier._playedColor   = widget.playedColor;
    _notifier._unplayedColor = widget.unplayedColor;
    if (widget.isPlaying && !_ctl.isAnimating) {
      _ctl.repeat();
    } else if (!widget.isPlaying && _ctl.isAnimating) {
      // Let bars settle before stopping.
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    _notifier.dispose();
    super.dispose();
  }

  void _onTick() {
    if (!mounted) return;
    final reducedMotion = MediaQuery.of(context).disableAnimations;
    final changed = _notifier._tick(
      isPlaying: widget.isPlaying,
      reducedMotion: reducedMotion,
    );
    if (!changed && !widget.isPlaying && !_notifier._dragging) {
      _ctl.stop();
    }
  }

  void _handleDragStart(DragStartDetails d) {
    HapticFeedback.selectionClick();
    _notifier._setDrag(true, _toProgress(d.localPosition.dx));
    widget.onScrub?.call(_notifier._dragProgress);
    if (!_ctl.isAnimating) _ctl.repeat();
  }

  void _handleDragUpdate(DragUpdateDetails d) {
    _notifier._setDrag(true, _toProgress(d.localPosition.dx));
    widget.onScrub?.call(_notifier._dragProgress);
  }

  void _handleDragEnd(DragEndDetails _) {
    widget.onScrubEnd?.call(_notifier._dragProgress);
    _notifier._setDrag(false, _notifier._dragProgress);
  }

  void _handleTap(TapDownDetails d) {
    HapticFeedback.selectionClick();
    final p = _toProgress(d.localPosition.dx);
    widget.onScrub?.call(p);
    widget.onScrubEnd?.call(p);
  }

  double _toProgress(double dx) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || box.size.width <= 0) return 0;
    return (dx / box.size.width).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    _notifier._progress      = widget.progress;
    _notifier._playedColor   = widget.playedColor;
    _notifier._unplayedColor = widget.unplayedColor;

    return RepaintBoundary(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: _handleDragStart,
        onHorizontalDragUpdate: _handleDragUpdate,
        onHorizontalDragEnd: _handleDragEnd,
        onTapDown: _handleTap,
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: CustomPaint(
            painter: _WaveformPainter(notifier: _notifier),
          ),
        ),
      ),
    );
  }
}
