import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show FftFrame;

import '../design_tokens/tokens.dart';
import '../state/providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FftWaveform — live FFT visualiser + progress scrubber
// ─────────────────────────────────────────────────────────────────────────────

/// Combined live FFT visualiser and progress scrubber for Now Playing.
///
/// ## How it works
///
/// mpv_audio_kit emits [FftFrame.bands] — 64 log-spaced perceptual bands
/// already normalised to [0, 1] with asymmetric EMA smoothing. We maintain
/// a parallel [_smoothed] array and lerp each bar toward the incoming FFT
/// value every frame. This gives us independent control over the visual
/// smoothing without fighting mpv's own EMA.
///
/// The static [peaks] array (track waveform envelope) is used only as a
/// **ceiling** — a bar can never exceed its recorded peak height. This
/// preserves the waveform shape while letting the FFT drive the actual
/// movement.
///
/// When no FFT data is available (paused / not started), bars decay to
/// the static peaks with a gentle sine-wave oscillation.
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
    this.playedColor = AfColors.indigo300,
    this.unplayedColor = AfColors.textTertiary,
    this.height = 72,
    this.onScrub,
    this.onScrubEnd,
    this.isPlaying = true,
  });

  @override
  ConsumerState<FftWaveform> createState() => _FftWaveformState();
}

class _FftWaveformState extends ConsumerState<FftWaveform>
    with SingleTickerProviderStateMixin {
  /// Drives repaints at ~60 fps so the smoothed bars animate continuously.
  late final AnimationController _ticker;

  bool _dragging = false;
  double _dragProgress = 0.0;

  /// Per-bar smoothed heights in [0, 1]. Updated every tick toward the
  /// latest FFT target.
  late Float32List _smoothed;

  /// Latest raw FFT bands from mpv. Null when stream hasn't started.
  Float32List? _fftTarget;

  /// Whether we have live FFT data this session.
  bool _hasFft = false;

  /// Fallback sine-wave phase (0..2π), advanced each tick when no FFT.
  double _fallbackPhase = 0.0;

  // Smoothing constants — tweak these to taste.
  /// How fast bars rise toward the FFT target (0 = instant, 1 = never).
  static const double _attackLerp = 0.4;
  /// How fast bars fall back when FFT drops (0 = instant, 1 = never).
  static const double _decayLerp = 0.12;
  /// Minimum bar height fraction so bars are always visible.
  static const double _minHeight = 0.04;
  /// Power curve exponent applied to raw FFT values.
  /// > 1.0 compresses quiet sounds down and lets loud beats spike high.
  /// 2.5 gives a good "quiet=low, loud=high" feel without clipping.
  static const double _powerCurve = 2.5;

  @override
  void initState() {
    super.initState();
    final barCount = widget.peaks.isEmpty ? 64 : widget.peaks.length;
    _smoothed = Float32List(barCount);
    // Seed smoothed values from static peaks so bars don't start at zero.
    for (var i = 0; i < barCount; i++) {
      _smoothed[i] = widget.peaks.isEmpty
          ? 0.3
          : (widget.peaks[i] / 100.0).clamp(_minHeight, 1.0) * 0.5;
    }
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_onTick);
    _ticker.repeat();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick() {
    if (!mounted) return;
    final peaks = widget.peaks.isEmpty
        ? List<int>.filled(_smoothed.length, 30)
        : widget.peaks;
    final barCount = _smoothed.length;

    if (_hasFft && _fftTarget != null) {
      final bands = _fftTarget!;
      for (var i = 0; i < barCount; i++) {
        final bandIdx = (i * bands.length / barCount)
            .clamp(0, bands.length - 1)
            .toInt();
        // Apply power curve: compresses quiet sounds, lets loud beats spike.
        // raw=0.3 (quiet) → 0.3^2.5 ≈ 0.049  (stays low)
        // raw=0.7 (medium) → 0.7^2.5 ≈ 0.41   (moderate)
        // raw=0.9 (loud)   → 0.9^2.5 ≈ 0.77   (high but not maxed)
        final raw = bands[bandIdx].clamp(0.0, 1.0);
        final target = math.pow(raw, _powerCurve).toDouble().clamp(_minHeight, 1.0);
        final current = _smoothed[i];
        final lerp = target > current ? _attackLerp : _decayLerp;
        _smoothed[i] = current + (target - current) * lerp;
      }
    } else {
      // Fallback: gentle sine-wave oscillation around the static peaks.
      _fallbackPhase += 0.04;
      if (_fallbackPhase > 2 * math.pi) _fallbackPhase -= 2 * math.pi;
      for (var i = 0; i < barCount; i++) {
        final peak = (peaks[i] / 100.0).clamp(_minHeight, 1.0);
        final target = peak * (0.4 + 0.3 * math.sin(_fallbackPhase + i * 0.3));
        _smoothed[i] = _smoothed[i] + (target - _smoothed[i]) * 0.15;
      }
    }
    // setState triggers a repaint via AnimatedBuilder below.
    setState(() {});
  }

  void _handleDragStart(DragStartDetails d) {
    setState(() {
      _dragging = true;
      _dragProgress = _toProgress(d.localPosition.dx);
    });
    widget.onScrub?.call(_dragProgress);
  }

  void _handleDragUpdate(DragUpdateDetails d) {
    final p = _toProgress(d.localPosition.dx);
    setState(() => _dragProgress = p);
    widget.onScrub?.call(p);
  }

  void _handleDragEnd(DragEndDetails details) {
    widget.onScrubEnd?.call(_dragProgress);
    setState(() => _dragging = false);
  }

  void _handleTap(TapDownDetails d) {
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
    ref.listen<AsyncValue<FftFrame>>(fftSpectrumProvider, (prev, next) {
      next.whenData((frame) {
        _fftTarget = frame.bands;
        _hasFft = true;
      });
    });

    final displayProgress =
        _dragging ? _dragProgress : widget.progress.clamp(0.0, 1.0);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: _handleDragStart,
      onHorizontalDragUpdate: _handleDragUpdate,
      onHorizontalDragEnd: _handleDragEnd,
      onTapDown: _handleTap,
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: CustomPaint(
          painter: _WaveformPainter(
            smoothed: Float32List.fromList(_smoothed),
            progress: displayProgress,
            playedColor: widget.playedColor,
            unplayedColor: widget.unplayedColor,
            isDragging: _dragging,
          ),
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final Float32List smoothed;
  final double progress;
  final Color playedColor;
  final Color unplayedColor;
  final bool isDragging;

  static const double _barGapRatio = 0.4;
  static const double _playheadWidth = 2.0;
  static const double _playheadGlowRadius = 8.0;

  _WaveformPainter({
    required this.smoothed,
    required this.progress,
    required this.playedColor,
    required this.unplayedColor,
    required this.isDragging,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || smoothed.isEmpty) return;

    final barCount = smoothed.length;
    final barWidth =
        size.width / (barCount * (1 + _barGapRatio) - _barGapRatio);
    final gap = barWidth * _barGapRatio;
    final centerY = size.height / 2;

    final headBarF = progress * barCount;
    final headX = progress * size.width;

    final playedPaint = Paint()
      ..color = playedColor
      ..style = PaintingStyle.fill;
    final unplayedPaint = Paint()
      ..color = unplayedColor.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    for (var i = 0; i < barCount; i++) {
      final amp = smoothed[i].clamp(0.05, 1.0);
      final h = (size.height * amp).clamp(3.0, size.height);
      final x = i * (barWidth + gap);
      final isPlayed = i < headBarF.floor();

      final Paint paint;
      if (i == headBarF.floor()) {
        final frac = headBarF - headBarF.floor();
        paint = Paint()
          ..color = Color.lerp(unplayedPaint.color, playedPaint.color, frac)!
          ..style = PaintingStyle.fill;
      } else {
        paint = isPlayed ? playedPaint : unplayedPaint;
      }

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, centerY - h / 2, barWidth, h),
          Radius.circular(barWidth / 2),
        ),
        paint,
      );
    }

    // Playhead glow.
    canvas.drawRect(
      Rect.fromLTWH(
        headX - _playheadGlowRadius,
        0,
        _playheadGlowRadius * 2,
        size.height,
      ),
      Paint()
        ..color = playedColor.withValues(alpha: isDragging ? 0.25 : 0.15)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // Playhead line.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(headX - _playheadWidth / 2, 0, _playheadWidth, size.height),
        const Radius.circular(1),
      ),
      Paint()
        ..color = isDragging
            ? AfColors.textPrimary
            : playedColor.withValues(alpha: 0.9)
        ..style = PaintingStyle.fill,
    );

    // Thumb dot.
    canvas.drawCircle(
      Offset(headX, centerY),
      isDragging ? 7.0 : 5.0,
      Paint()
        ..color = AfColors.textPrimary
        ..style = PaintingStyle.fill,
    );

    if (isDragging) {
      canvas.drawCircle(
        Offset(headX, centerY),
        14.0,
        Paint()
          ..color = playedColor.withValues(alpha: 0.28)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress ||
      old.isDragging != isDragging ||
      old.smoothed != smoothed ||
      old.playedColor != playedColor ||
      old.unplayedColor != unplayedColor;
}

// ─────────────────────────────────────────────────────────────────────────────
// Waveform — static peaks-only scrubber (used outside Now Playing)
// ─────────────────────────────────────────────────────────────────────────────

/// Static peaks-only waveform scrubber. No FFT dependency.
/// Used in Queue, mini-player ring, etc.
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
    this.playedColor = AfColors.indigo300,
    this.unplayedColor = AfColors.textTertiary,
    this.height = 72,
    this.onScrub,
    this.onScrubEnd,
    this.isPlaying = true,
  });

  @override
  State<Waveform> createState() => _WaveformState();
}

class _WaveformState extends State<Waveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;
  bool _dragging = false;
  double _dragProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600));
    if (widget.isPlaying) _ctl.repeat();
  }

  @override
  void didUpdateWidget(covariant Waveform old) {
    super.didUpdateWidget(old);
    if (widget.isPlaying && !_ctl.isAnimating) {
      _ctl.repeat();
    } else if (!widget.isPlaying && _ctl.isAnimating) {
      _ctl.animateTo(0, duration: AfDurations.quick, curve: AfCurves.easeOut);
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _handleDragStart(DragStartDetails d) {
    setState(() {
      _dragging = true;
      _dragProgress = _toProgress(d.localPosition.dx);
    });
    widget.onScrub?.call(_dragProgress);
  }

  void _handleDragUpdate(DragUpdateDetails d) {
    final p = _toProgress(d.localPosition.dx);
    setState(() => _dragProgress = p);
    widget.onScrub?.call(p);
  }

  void _handleDragEnd(DragEndDetails details) {
    widget.onScrubEnd?.call(_dragProgress);
    setState(() => _dragging = false);
  }

  void _handleTap(TapDownDetails d) {
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
    final displayProgress =
        _dragging ? _dragProgress : widget.progress.clamp(0.0, 1.0);
    final peaks =
        widget.peaks.isEmpty ? List<int>.filled(64, 30) : widget.peaks;
    final barCount = peaks.length;

    // Build a static smoothed array from peaks + sine jitter.
    final smoothed = Float32List(barCount);
    final t = _ctl.value;
    for (var i = 0; i < barCount; i++) {
      final peak = (peaks[i] / 100.0).clamp(0.05, 1.0);
      final jitter = peak * 0.25 * math.sin(2 * math.pi * t + i * 0.55);
      smoothed[i] = (peak + jitter).clamp(0.05, 1.0);
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: _handleDragStart,
      onHorizontalDragUpdate: _handleDragUpdate,
      onHorizontalDragEnd: _handleDragEnd,
      onTapDown: _handleTap,
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: AnimatedBuilder(
          animation: _ctl,
          builder: (context, child) => CustomPaint(
            painter: _WaveformPainter(
              smoothed: smoothed,
              progress: displayProgress,
              playedColor: widget.playedColor,
              unplayedColor: widget.unplayedColor,
              isDragging: _dragging,
            ),
          ),
        ),
      ),
    );
  }
}
