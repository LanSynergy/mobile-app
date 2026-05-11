import 'dart:math' as math;
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../design_tokens/tokens.dart';

/// Combined waveform visualiser + progress scrubber.
///
/// The bars ARE the progress bar — no separate track underneath.
///
/// Layout:
///   • A single [CustomPaint] canvas draws all bars.
///   • Bars to the left of the playhead are filled with [playedColor]
///     (spectral.energy). Bars to the right are dim.
///   • A glowing vertical playhead line sits at the progress position.
///   • When [isPlaying] is true, each bar oscillates around its static
///     peak amplitude. The oscillation magnitude is proportional to the
///     bar's own peak value — loud bars pulse more, quiet bars barely
///     move — so the animation feels synced to the song's energy at
///     each position rather than being a uniform shimmer.
///   • Drag or tap anywhere to scrub.
///
/// Drop-in replacement for the previous two-layer Waveform widget.
/// Same constructor params, same callbacks.
class Waveform extends StatefulWidget {
  /// Per-bar peak amplitudes in [0, 100]. Server-provided when possible;
  /// otherwise a deterministic pattern seeded by the track ID.
  final List<int> peaks;

  /// Playback progress in [0.0, 1.0].
  final double progress;

  /// Colour for played bars and the playhead glow (spectral.energy).
  final Color playedColor;

  /// Colour for unplayed bars. Defaults to [AfColors.textTertiary].
  final Color unplayedColor;

  /// Total height of the widget in dp.
  final double height;

  /// Called continuously while the user drags. Value is in [0.0, 1.0].
  final ValueChanged<double>? onScrub;

  /// Called once when the drag ends. Value is the final progress.
  final ValueChanged<double>? onScrubEnd;

  /// Whether the player is currently playing. Controls bar animation.
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

  // Tracks whether the user is actively scrubbing so we can suppress
  // the playhead jump that would otherwise flicker during a drag.
  bool _dragging = false;
  double _dragProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(
      vsync: this,
      // One full oscillation cycle. The painter maps this 0→1 value to
      // a sine wave so bars pulse smoothly.
      duration: const Duration(milliseconds: 1600),
    );
    if (widget.isPlaying) _ctl.repeat();
  }

  @override
  void didUpdateWidget(covariant Waveform old) {
    super.didUpdateWidget(old);
    if (widget.isPlaying && !_ctl.isAnimating) {
      _ctl.repeat();
    } else if (!widget.isPlaying && _ctl.isAnimating) {
      // Snap to a neutral phase so bars don't freeze mid-oscillation at
      // an awkward height. Animating to 0 over `quick` keeps it smooth.
      _ctl.animateTo(
        0,
        duration: AfDurations.quick,
        curve: AfCurves.easeOut,
      );
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

  void _handleDragEnd(DragEndDetails _) {
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

    final peaks = widget.peaks.isEmpty
        ? List<int>.filled(64, 30)
        : widget.peaks;

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
          builder: (context, _) => CustomPaint(
            painter: _WaveformPainter(
              peaks: peaks,
              progress: displayProgress,
              playedColor: widget.playedColor,
              unplayedColor: widget.unplayedColor,
              t: _ctl.value,
              animate: widget.isPlaying,
              isDragging: _dragging,
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the combined waveform + scrubber on a single canvas.
///
/// Bar oscillation model:
///   amplitude(i, t) = peakAmp + peakAmp * jitterScale * sin(2π·t + phase(i))
///
/// The jitter scale is proportional to the bar's own peak amplitude so
/// loud bars (high energy) pulse more than quiet bars (low energy). This
/// makes the animation feel like it's reacting to the song's content at
/// each position rather than being a uniform shimmer.
///
/// Additionally, bars within a small window around the playhead get a
/// subtle extra boost (the "focal pulse") so the current position feels
/// alive even during quiet passages.
class _WaveformPainter extends CustomPainter {
  final List<int> peaks;
  final double progress;
  final Color playedColor;
  final Color unplayedColor;
  final double t; // 0..1, repeating
  final bool animate;
  final bool isDragging;

  static const double _barGapRatio = 0.5; // gap = barWidth * ratio
  static const double _minBarHeightFraction = 0.06;
  static const double _maxJitter = 0.28; // max oscillation as fraction of peak
  static const double _focalBoost = 0.12; // extra boost near playhead
  static const double _focalSigma = 8.0; // bars affected by focal boost
  static const double _playheadWidth = 2.0;
  static const double _playheadGlowRadius = 8.0;

  _WaveformPainter({
    required this.peaks,
    required this.progress,
    required this.playedColor,
    required this.unplayedColor,
    required this.t,
    required this.animate,
    required this.isDragging,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final barCount = peaks.length;
    // barWidth + gap = size.width / barCount  →  barWidth = size.width / (barCount * (1 + gapRatio))
    final barWidth =
        size.width / (barCount * (1 + _barGapRatio) - _barGapRatio);
    final gap = barWidth * _barGapRatio;
    final centerY = size.height / 2;
    final twoPi = 2 * math.pi;

    // Index of the bar that sits at the playhead.
    final headBarF = progress * barCount;
    final headX = progress * size.width;

    // Pre-compute paints.
    final playedPaint = Paint()
      ..color = playedColor
      ..style = PaintingStyle.fill;
    final unplayedPaint = Paint()
      ..color = unplayedColor.withValues(alpha: 0.28)
      ..style = PaintingStyle.fill;

    // ── Draw bars ────────────────────────────────────────────────────────
    for (var i = 0; i < barCount; i++) {
      final peakAmp = (peaks[i] / 100.0).clamp(_minBarHeightFraction, 1.0);

      double amp = peakAmp;
      if (animate) {
        // Energy-proportional jitter: loud bars pulse more.
        final jitterScale = peakAmp * _maxJitter;
        // Focal boost: bars near the playhead get extra energy.
        final distToHead = (i - headBarF).abs();
        final focal = _focalBoost * math.exp(-distToHead / _focalSigma);
        // Each bar has a unique phase offset so they don't all move in sync.
        final phase = twoPi * t + i * 0.55;
        amp = (peakAmp + jitterScale * math.sin(phase) + focal * math.sin(phase + 0.8))
            .clamp(_minBarHeightFraction, 1.0);
      }

      final h = (size.height * amp).clamp(2.0, size.height);
      final x = i * (barWidth + gap);
      final isPlayed = i < headBarF.floor();

      // Bars that straddle the playhead get a blended colour so the
      // transition isn't a hard jump between adjacent bars.
      final Paint paint;
      if (i == headBarF.floor()) {
        // Fractional bar: blend played/unplayed by how far the head is
        // into this bar.
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

    // ── Playhead ─────────────────────────────────────────────────────────
    // Soft glow halo first (behind the line).
    canvas.drawRect(
      Rect.fromLTWH(
        headX - _playheadGlowRadius,
        0,
        _playheadGlowRadius * 2,
        size.height,
      ),
      Paint()
        ..color = playedColor.withValues(alpha: isDragging ? 0.22 : 0.14)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // Playhead line.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          headX - _playheadWidth / 2,
          0,
          _playheadWidth,
          size.height,
        ),
        const Radius.circular(1),
      ),
      Paint()
        ..color = isDragging
            ? AfColors.textPrimary
            : playedColor.withValues(alpha: 0.9)
        ..style = PaintingStyle.fill,
    );

    // Thumb dot at the centre of the playhead — gives a clear grab target.
    canvas.drawCircle(
      Offset(headX, centerY),
      isDragging ? 7.0 : 5.0,
      Paint()
        ..color = AfColors.textPrimary
        ..style = PaintingStyle.fill,
    );

    // Glow ring around the thumb when dragging.
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
      old.t != t ||
      old.progress != progress ||
      old.isDragging != isDragging ||
      old.animate != animate ||
      !listEquals(old.peaks, peaks) ||
      old.playedColor != playedColor ||
      old.unplayedColor != unplayedColor;
}
