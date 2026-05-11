import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show FftFrame;

import '../design_tokens/tokens.dart';
import '../state/providers.dart';

/// Combined FFT visualiser + progress scrubber.
///
/// ## Layout
/// A single [CustomPaint] canvas draws all bars. Bars to the left of the
/// playhead are filled with [playedColor]; bars to the right are dim.
/// A glowing vertical playhead line sits at the progress position.
/// Drag or tap anywhere to scrub.
///
/// ## Bar heights
/// When [fftSpectrumProvider] is emitting (i.e. mpv is playing), each
/// bar's height is driven by the **live FFT magnitude** for that frequency
/// band, multiplied by the static [peaks] envelope so the shape still
/// reflects the track's waveform. This gives a real-time visualizer that
/// also encodes the song's loudness profile.
///
/// When no FFT data is available (paused, stream not started), the bars
/// fall back to the static [peaks] envelope with a gentle sine-wave
/// oscillation — the same behaviour as before.
///
/// ## Design token compliance
/// Audio-coupled animations use [AfCurves.linear] (raw FFT values, no
/// easing applied on top of the data).
class FftWaveform extends ConsumerStatefulWidget {
  /// Per-bar peak amplitudes in [0, 100]. Used as the static envelope
  /// and as the fallback when no FFT data is available.
  final List<int> peaks;

  /// Playback progress in [0.0, 1.0].
  final double progress;

  /// Colour for played bars and the playhead glow (spectral.energy).
  final Color playedColor;

  /// Colour for unplayed bars.
  final Color unplayedColor;

  /// Total height of the widget in dp.
  final double height;

  /// Called continuously while the user drags.
  final ValueChanged<double>? onScrub;

  /// Called once when the drag ends.
  final ValueChanged<double>? onScrubEnd;

  /// Whether the player is currently playing. Controls fallback animation.
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
  /// Fallback animation controller — only runs when no FFT data is
  /// available (paused / stream not started).
  late final AnimationController _fallbackCtl;

  bool _dragging = false;
  double _dragProgress = 0.0;

  /// Latest FFT bands received from [fftSpectrumProvider].
  /// Null when no data has arrived yet (paused / stream not started).
  Float32List? _fftBands;

  @override
  void initState() {
    super.initState();
    _fallbackCtl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    if (widget.isPlaying) _fallbackCtl.repeat();
  }

  @override
  void didUpdateWidget(covariant FftWaveform old) {
    super.didUpdateWidget(old);
    // Only run the fallback animation when there's no live FFT data.
    final needsFallback = widget.isPlaying && _fftBands == null;
    if (needsFallback && !_fallbackCtl.isAnimating) {
      _fallbackCtl.repeat();
    } else if (!needsFallback && _fallbackCtl.isAnimating) {
      _fallbackCtl.animateTo(0,
          duration: AfDurations.quick, curve: AfCurves.easeOut);
    }
  }

  @override
  void dispose() {
    _fallbackCtl.dispose();
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
    // Subscribe to the FFT stream. Each new frame updates _fftBands and
    // triggers a repaint via setState. When the stream stops emitting
    // (pause), _fftBands retains the last frame — the painter will decay
    // it toward the static envelope on the next fallback tick.
    ref.listen<AsyncValue<FftFrame>>(fftSpectrumProvider, (prev, next) {
      next.whenData((frame) {
        if (!mounted) return;
        setState(() {
          _fftBands = frame.bands;
          // Stop the fallback animation — live FFT is driving the bars.
          if (_fallbackCtl.isAnimating) {
            _fallbackCtl.stop();
          }
        });
      });
      // Stream ended (paused / disposed) — restart fallback if playing.
      if (next is AsyncError || (next is AsyncLoading && prev?.hasValue == true)) {
        if (mounted && widget.isPlaying && !_fallbackCtl.isAnimating) {
          _fallbackCtl.repeat();
        }
      }
    });

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
          // Rebuild on both the fallback controller tick AND on FFT data
          // changes (which come via setState above).
          animation: _fallbackCtl,
          builder: (context, child) => CustomPaint(
            painter: _FftWaveformPainter(
              peaks: peaks,
              fftBands: _fftBands,
              progress: displayProgress,
              playedColor: widget.playedColor,
              unplayedColor: widget.unplayedColor,
              fallbackT: _fallbackCtl.value,
              useFallback: _fftBands == null,
              isDragging: _dragging,
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the combined FFT visualiser + scrubber on a single canvas.
///
/// ## Bar height model
///
/// **Live FFT mode** (fftBands != null):
///   The 64 FFT bands are resampled to match [peaks.length] bars.
///   Each bar's height = lerp(staticPeak, fftMagnitude, 0.7) so the
///   waveform shape is still visible but the live energy dominates.
///   This gives a visualizer that "breathes" with the music while
///   retaining the track's loudness profile as a skeleton.
///
/// **Fallback mode** (fftBands == null, isPlaying):
///   Classic sine-wave jitter proportional to each bar's peak amplitude.
///   Same as the original Waveform widget.
class _FftWaveformPainter extends CustomPainter {
  final List<int> peaks;
  final Float32List? fftBands;
  final double progress;
  final Color playedColor;
  final Color unplayedColor;
  final double fallbackT;
  final bool useFallback;
  final bool isDragging;

  static const double _barGapRatio = 0.5;
  static const double _minBarHeightFraction = 0.06;
  static const double _maxJitter = 0.28;
  static const double _focalBoost = 0.12;
  static const double _focalSigma = 8.0;
  static const double _playheadWidth = 2.0;
  static const double _playheadGlowRadius = 8.0;

  /// How much the live FFT dominates over the static peak envelope.
  /// 0.45 = 45% FFT, 55% static peak. Lower values keep the waveform
  /// shape more visible; higher values make bars react more to the music.
  static const double _fftBlend = 0.45;

  _FftWaveformPainter({
    required this.peaks,
    required this.fftBands,
    required this.progress,
    required this.playedColor,
    required this.unplayedColor,
    required this.fallbackT,
    required this.useFallback,
    required this.isDragging,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final barCount = peaks.length;
    final barWidth =
        size.width / (barCount * (1 + _barGapRatio) - _barGapRatio);
    final gap = barWidth * _barGapRatio;
    final centerY = size.height / 2;
    final twoPi = 2 * math.pi;

    final headBarF = progress * barCount;
    final headX = progress * size.width;

    final playedPaint = Paint()
      ..color = playedColor
      ..style = PaintingStyle.fill;
    final unplayedPaint = Paint()
      ..color = unplayedColor.withValues(alpha: 0.28)
      ..style = PaintingStyle.fill;

    // Pre-resample FFT bands to barCount if available.
    final bands = fftBands;

    for (var i = 0; i < barCount; i++) {
      final staticPeak =
          (peaks[i] / 100.0).clamp(_minBarHeightFraction, 1.0);

      double amp;
      if (!useFallback && bands != null && bands.isNotEmpty) {
        // Map bar index to FFT band index (linear resample).
        final fftIdx = (i / barCount * bands.length).clamp(0, bands.length - 1).toInt();
        // Apply sqrt curve to compress loud transients — raw FFT magnitudes
        // spike to 1.0 on beats which pushes every bar to full height.
        final fftMag = math.sqrt(bands[fftIdx].clamp(0.0, 1.0));
        // Blend: static peak gives the waveform shape, FFT gives the energy.
        amp = (staticPeak * (1 - _fftBlend) + fftMag * _fftBlend)
            .clamp(_minBarHeightFraction, 1.0);
      } else {
        // Fallback: sine-wave jitter proportional to peak amplitude.
        final jitterScale = staticPeak * _maxJitter;
        final distToHead = (i - headBarF).abs();
        final focal = _focalBoost * math.exp(-distToHead / _focalSigma);
        final phase = twoPi * fallbackT + i * 0.55;
        amp = (staticPeak +
                jitterScale * math.sin(phase) +
                focal * math.sin(phase + 0.8))
            .clamp(_minBarHeightFraction, 1.0);
      }

      final h = (size.height * amp).clamp(2.0, size.height);
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

    // ── Playhead ─────────────────────────────────────────────────────────
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
  bool shouldRepaint(_FftWaveformPainter old) =>
      old.fallbackT != fallbackT ||
      old.progress != progress ||
      old.isDragging != isDragging ||
      old.useFallback != useFallback ||
      old.fftBands != fftBands ||
      !listEquals(old.peaks, peaks) ||
      old.playedColor != playedColor ||
      old.unplayedColor != unplayedColor;
}

// ---------------------------------------------------------------------------
// Keep the old Waveform class as a thin alias so other screens that import
// it (queue, mini-player ring, etc.) don't break. It uses the static
// peaks-only path — no FFT dependency outside Now Playing.
// ---------------------------------------------------------------------------

/// Static peaks-only waveform scrubber. Used outside Now Playing where
/// the FFT stream is not needed. For the live FFT version see [FftWaveform].
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
      _ctl.animateTo(0,
          duration: AfDurations.quick, curve: AfCurves.easeOut);
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
            painter: _FftWaveformPainter(
              peaks: peaks,
              fftBands: null,
              progress: displayProgress,
              playedColor: widget.playedColor,
              unplayedColor: widget.unplayedColor,
              fallbackT: _ctl.value,
              useFallback: true,
              isDragging: _dragging,
            ),
          ),
        ),
      ),
    );
  }
}
