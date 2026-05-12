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
// • Single CustomPainter — the entire waveform is one paint pass.
//   No widget-per-bar, no ListView, no Opacity widgets.
//
// • FFT data is consumed via a direct StreamSubscription wired in
//   didChangeDependencies so frames are never dropped between rebuilds.
//
// • Asymmetric EMA smoothing: fast attack (bars snap to beats),
//   slow release (bars decay gracefully between beats).
//
// • Progress overlay: bars left of the playhead are painted with
//   playedColor; bars right use unplayedColor at reduced opacity.
//   The transition bar is lerped between the two colors.
//
// • Scrub thumb: circle + glow, haptic feedback on drag start.
//
// • Idle pose: when isPlaying=false and no FFT data, bars hold their
//   static peak heights with no animation — no jitter, no fake motion.
//
// Public API (unchanged from previous version):
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
  // ── 60 fps ticker ─────────────────────────────────────────────────────────
  late final AnimationController _ticker;

  // ── Scrub state ───────────────────────────────────────────────────────────
  bool   _dragging     = false;
  double _dragProgress = 0.0;

  // ── Per-bar smoothed heights [0, 1] ───────────────────────────────────────
  late Float32List _smoothed;

  // ── Latest raw FFT bands ──────────────────────────────────────────────────
  Float32List? _fftTarget;
  bool _hasFft = false;
  StreamSubscription<FftFrame>? _fftSub;

  // ── Smoothing constants ───────────────────────────────────────────────────
  /// Bars rise quickly toward the FFT target (snappy beat response).
  static const double _attackLerp  = 0.45;
  /// Bars fall slowly (smooth decay between beats).
  static const double _decayLerp   = 0.10;
  /// Minimum bar height so the waveform shape is always visible.
  static const double _minHeight   = 0.06;
  /// Power curve: compresses quiet signals, lets loud beats spike.
  /// 1.4 is mild — quiet passages stay visible, peaks still punch.
  static const double _powerCurve  = 1.4;

  // ── Idle fallback phase ───────────────────────────────────────────────────
  double _idlePhase = 0.0;

  @override
  void initState() {
    super.initState();
    _initSmoothed();
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_onTick);
    _ticker.repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe directly to the spectrum stream so we never miss a frame
    // between widget rebuilds (ref.listen in build() can drop frames).
    _fftSub?.cancel();
    final svc = ref.read(playerServiceProvider);
    _fftSub = svc.spectrumStream.listen((frame) {
      _fftTarget = frame.bands;
      _hasFft = true;
    });
  }

  @override
  void didUpdateWidget(FftWaveform old) {
    super.didUpdateWidget(old);
    // Re-seed if the peaks array changed (new track).
    if (old.peaks != widget.peaks) _initSmoothed();
  }

  @override
  void dispose() {
    _fftSub?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  void _initSmoothed() {
    final barCount = widget.peaks.isEmpty ? 64 : widget.peaks.length;
    _smoothed = Float32List(barCount);
    for (var i = 0; i < barCount; i++) {
      _smoothed[i] = widget.peaks.isEmpty
          ? _minHeight
          : (widget.peaks[i] / 100.0).clamp(_minHeight, 1.0) * 0.5;
    }
  }

  // ── Per-frame smoothing ───────────────────────────────────────────────────

  void _onTick() {
    if (!mounted) return;
    final barCount = _smoothed.length;
    final peaks = widget.peaks.isEmpty
        ? List<int>.filled(barCount, 30)
        : widget.peaks;

    if (_hasFft && _fftTarget != null) {
      final bands = _fftTarget!;
      for (var i = 0; i < barCount; i++) {
        final bandIdx = (i * bands.length / barCount)
            .clamp(0, bands.length - 1)
            .toInt();
        final raw    = bands[bandIdx].clamp(0.0, 1.0);
        final target = math.pow(raw, _powerCurve).toDouble().clamp(_minHeight, 1.0);
        final lerp   = target > _smoothed[i] ? _attackLerp : _decayLerp;
        _smoothed[i] = _smoothed[i] + (target - _smoothed[i]) * lerp;
      }
    } else if (widget.isPlaying) {
      // Idle animation: gentle sine-wave oscillation around static peaks.
      _idlePhase = (_idlePhase + 0.035) % (2 * math.pi);
      for (var i = 0; i < barCount; i++) {
        final peak   = (peaks[i] / 100.0).clamp(_minHeight, 1.0);
        final target = peak * (0.45 + 0.25 * math.sin(_idlePhase + i * 0.28));
        _smoothed[i] = _smoothed[i] + (target - _smoothed[i]) * 0.12;
      }
    }
    // When paused and no FFT: bars hold their current position — no jitter.

    setState(() {});
  }

  // ── Gesture handlers ──────────────────────────────────────────────────────

  void _handleDragStart(DragStartDetails d) {
    HapticFeedback.selectionClick();
    setState(() {
      _dragging     = true;
      _dragProgress = _toProgress(d.localPosition.dx);
    });
    widget.onScrub?.call(_dragProgress);
  }

  void _handleDragUpdate(DragUpdateDetails d) {
    final p = _toProgress(d.localPosition.dx);
    setState(() => _dragProgress = p);
    widget.onScrub?.call(p);
  }

  void _handleDragEnd(DragEndDetails _) {
    widget.onScrubEnd?.call(_dragProgress);
    setState(() => _dragging = false);
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

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
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
            smoothed:     Float32List.fromList(_smoothed),
            progress:     displayProgress,
            playedColor:  widget.playedColor,
            unplayedColor: widget.unplayedColor,
            isDragging:   _dragging,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _WaveformPainter
// ─────────────────────────────────────────────────────────────────────────────

class _WaveformPainter extends CustomPainter {
  final Float32List smoothed;
  final double      progress;
  final Color       playedColor;
  final Color       unplayedColor;
  final bool        isDragging;

  // Bar geometry
  static const double _barGapFraction = 0.35; // gap / barWidth
  static const double _minBarHeight   = 3.0;  // dp

  // Playhead
  static const double _headWidth      = 2.0;
  static const double _thumbRadius    = 5.0;
  static const double _thumbRadiusDrag = 7.5;
  static const double _glowRadius     = 10.0;

  const _WaveformPainter({
    required this.smoothed,
    required this.progress,
    required this.playedColor,
    required this.unplayedColor,
    required this.isDragging,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || smoothed.isEmpty) return;

    final barCount  = smoothed.length;
    final totalGaps = barCount - 1;
    // barWidth * barCount + gap * totalGaps = size.width
    // gap = barWidth * _barGapFraction
    // barWidth * (barCount + _barGapFraction * totalGaps) = size.width
    final barWidth  = size.width / (barCount + _barGapFraction * totalGaps);
    final gap       = barWidth * _barGapFraction;
    final centerY   = size.height / 2;

    final headBarF  = progress * barCount;
    final headX     = progress * size.width;

    final playedPaint = Paint()
      ..color = playedColor
      ..style = PaintingStyle.fill;
    final unplayedPaint = Paint()
      ..color = unplayedColor.withValues(alpha: 0.28)
      ..style = PaintingStyle.fill;
    final capRadius = Radius.circular(barWidth / 2);

    // ── Draw bars ────────────────────────────────────────────────────────
    for (var i = 0; i < barCount; i++) {
      final amp  = smoothed[i].clamp(_minBarHeight / size.height, 1.0);
      final h    = math.max(_minBarHeight, size.height * amp);
      final x    = i * (barWidth + gap);
      final rect = Rect.fromLTWH(x, centerY - h / 2, barWidth, h);

      final Paint paint;
      if (i < headBarF.floor()) {
        paint = playedPaint;
      } else if (i == headBarF.floor()) {
        // Transition bar: lerp color at sub-bar precision.
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
        ..color = playedColor.withValues(alpha: isDragging ? 0.22 : 0.12)
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
            : playedColor.withValues(alpha: 0.9)
        ..style = PaintingStyle.fill,
    );

    // ── Scrub thumb ──────────────────────────────────────────────────────
    final thumbR = isDragging ? _thumbRadiusDrag : _thumbRadius;
    if (isDragging) {
      // Outer glow ring when dragging.
      canvas.drawCircle(
        Offset(headX, centerY),
        thumbR + 7,
        Paint()
          ..color = playedColor.withValues(alpha: 0.22)
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
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress      != progress      ||
      old.isDragging    != isDragging    ||
      old.smoothed      != smoothed      ||
      old.playedColor   != playedColor   ||
      old.unplayedColor != unplayedColor;
}

// ─────────────────────────────────────────────────────────────────────────────
// Waveform — static peaks-only scrubber (Queue, mini-player, etc.)
//
// No FFT dependency. Animates with a gentle sine-wave jitter when playing,
// holds a clean static pose when paused.
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
  bool   _dragging     = false;
  double _dragProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
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
    HapticFeedback.selectionClick();
    setState(() {
      _dragging     = true;
      _dragProgress = _toProgress(d.localPosition.dx);
    });
    widget.onScrub?.call(_dragProgress);
  }

  void _handleDragUpdate(DragUpdateDetails d) {
    final p = _toProgress(d.localPosition.dx);
    setState(() => _dragProgress = p);
    widget.onScrub?.call(p);
  }

  void _handleDragEnd(DragEndDetails _) {
    widget.onScrubEnd?.call(_dragProgress);
    setState(() => _dragging = false);
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
    final displayProgress =
        _dragging ? _dragProgress : widget.progress.clamp(0.0, 1.0);
    final peaks    = widget.peaks.isEmpty
        ? List<int>.filled(64, 30)
        : widget.peaks;
    final barCount = peaks.length;

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
          builder: (context, _) {
            final t = _ctl.value;
            final smoothed = Float32List(barCount);
            for (var i = 0; i < barCount; i++) {
              final peak   = (peaks[i] / 100.0).clamp(0.06, 1.0);
              // Jitter only when playing; static pose when paused.
              final jitter = widget.isPlaying
                  ? peak * 0.22 * math.sin(2 * math.pi * t + i * 0.52)
                  : 0.0;
              smoothed[i] = (peak + jitter).clamp(0.06, 1.0);
            }
            return CustomPaint(
              painter: _WaveformPainter(
                smoothed:      smoothed,
                progress:      displayProgress,
                playedColor:   widget.playedColor,
                unplayedColor: widget.unplayedColor,
                isDragging:    _dragging,
              ),
            );
          },
        ),
      ),
    );
  }
}
