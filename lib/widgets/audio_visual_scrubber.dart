import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show FftFrame;

import '../design_tokens/tokens.dart';
import '../state/providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AudioVisualScrubber
//
// Combines the FFT spectrum visualizer and the progress scrubber into one
// widget. The visualizer bars are tinted by playhead position — played bars
// use playedColor, unplayed bars use unplayedColor. A thin track line and
// drag thumb overlay the bars.
//
// Architecture:
//   _BlockNotifier  — FFT state (instant attack, ×0.75 decay)
//   _ScrubNotifier  — drag state + display progress
//   _CombinedBlockPainter — bars + glow, repaints on both notifiers
//   _ScrubOverlayPainter  — track line + thumb, repaints on scrub only
//
// Two RepaintBoundary layers ensure FFT repaints don't invalidate the
// scrub overlay and vice versa.
// ─────────────────────────────────────────────────────────────────────────────

class AudioVisualScrubber extends ConsumerStatefulWidget {
  final double height;
  final double progress;
  final Color playedColor;
  final Color unplayedColor;
  final ValueChanged<double>? onScrub;
  final ValueChanged<double>? onScrubEnd;

  const AudioVisualScrubber({
    super.key,
    this.height       = 120,
    required this.progress,
    this.playedColor  = AfColors.indigo300,
    this.unplayedColor = AfColors.textTertiary,
    this.onScrub,
    this.onScrubEnd,
  });

  @override
  ConsumerState<AudioVisualScrubber> createState() =>
      _AudioVisualScrubberState();
}

class _AudioVisualScrubberState extends ConsumerState<AudioVisualScrubber>
    with SingleTickerProviderStateMixin {
  late final _BlockNotifier _fftNotifier;
  late final _ScrubNotifier _scrubNotifier;
  late final AnimationController _ticker;
  StreamSubscription<FftFrame>? _fftSub;

  @override
  void initState() {
    super.initState();
    _fftNotifier  = _BlockNotifier();
    _scrubNotifier = _ScrubNotifier(progress: widget.progress);

    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(() {
        if (mounted) _fftNotifier.tick();
      });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _fftSub = ref.read(playerServiceProvider).spectrumStream.listen(
        (frame) {
          _fftNotifier.ingest(frame.bands);
          if (!_ticker.isAnimating) _ticker.repeat();
        },
      );
    });
  }

  @override
  void didUpdateWidget(covariant AudioVisualScrubber old) {
    super.didUpdateWidget(old);
    _scrubNotifier.update(widget.progress);
  }

  @override
  void dispose() {
    _fftSub?.cancel();
    _ticker.dispose();
    _fftNotifier.dispose();
    _scrubNotifier.dispose();
    super.dispose();
  }

  double _toProgress(double dx) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || box.size.width <= 0) return 0;
    return (dx / box.size.width).clamp(0.0, 1.0);
  }

  void _handleDragUpdate(DragUpdateDetails d) {
    _scrubNotifier.setDrag(true, _toProgress(d.localPosition.dx));
    widget.onScrub?.call(_scrubNotifier.dragProgress);
  }

  void _handleDragEnd(DragEndDetails _) {
    widget.onScrubEnd?.call(_scrubNotifier.dragProgress);
    _scrubNotifier.setDrag(false, _scrubNotifier.dragProgress);
  }

  @override
  Widget build(BuildContext context) {
    final spectral = ref.watch(currentSpectralProvider);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (d) {
        HapticFeedback.selectionClick();
        _handleDragUpdate(DragUpdateDetails(
          globalPosition: d.globalPosition,
          localPosition:  d.localPosition,
        ));
      },
      onHorizontalDragUpdate: _handleDragUpdate,
      onHorizontalDragEnd:    _handleDragEnd,
      onTapDown: (d) {
        HapticFeedback.selectionClick();
        final p = _toProgress(d.localPosition.dx);
        widget.onScrub?.call(p);
        widget.onScrubEnd?.call(p);
      },
      child: SizedBox(
        height: widget.height,
        width:  double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Layer 1: FFT bars — repaints on both FFT ticks and scrub progress.
            RepaintBoundary(
              child: CustomPaint(
                painter: _CombinedBlockPainter(
                  fftNotifier:   _fftNotifier,
                  scrubNotifier: _scrubNotifier,
                  glow:          spectral.glow,
                  playedColor:   widget.playedColor,
                  unplayedColor: widget.unplayedColor,
                ),
              ),
            ),
            // Layer 2: Track line + thumb — repaints on scrub only.
            RepaintBoundary(
              child: CustomPaint(
                painter: _ScrubOverlayPainter(
                  notifier:      _scrubNotifier,
                  playedColor:   widget.playedColor,
                  unplayedColor: widget.unplayedColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Notifiers
// ─────────────────────────────────────────────────────────────────────────────

class _ScrubNotifier extends ChangeNotifier {
  double _progress;
  bool   _dragging     = false;
  double _dragProgress = 0.0;

  _ScrubNotifier({required double progress}) : _progress = progress;

  double get displayProgress =>
      _dragging ? _dragProgress : _progress.clamp(0.0, 1.0);
  bool   get dragging      => _dragging;
  double get dragProgress  => _dragProgress;

  void update(double progress) {
    _progress = progress;
    notifyListeners();
  }

  void setDrag(bool dragging, double progress) {
    _dragging     = dragging;
    _dragProgress = progress;
    notifyListeners();
  }
}

class _BlockNotifier extends ChangeNotifier {
  static const int bins = 64;

  final Float32List smoothed = Float32List(bins);
  double totalEnergy = 0.0;

  void ingest(Float32List src) {
    double sum = 0;
    for (var i = 0; i < bins && i < src.length; i++) {
      final v = src[i].isFinite ? src[i].clamp(0.0, 1.0) : 0.0;
      if (v > smoothed[i]) smoothed[i] = v; // instant attack
      sum += smoothed[i];
    }
    totalEnergy = sum / bins;
  }

  void tick() {
    for (var i = 0; i < bins; i++) {
      smoothed[i] *= 0.75;
    }
    notifyListeners();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Painters
// ─────────────────────────────────────────────────────────────────────────────

class _CombinedBlockPainter extends CustomPainter {
  final _BlockNotifier fftNotifier;
  final _ScrubNotifier scrubNotifier;
  final Color glow;
  final Color playedColor;
  final Color unplayedColor;

  _CombinedBlockPainter({
    required this.fftNotifier,
    required this.scrubNotifier,
    required this.glow,
    required this.playedColor,
    required this.unplayedColor,
  }) : super(repaint: Listenable.merge([fftNotifier, scrubNotifier]));

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final double midY  = size.height / 2;
    final double slotW = size.width / _BlockNotifier.bins;
    final double barW  = (slotW * 0.7).clamp(1.0, 8.0);
    final double fillX = scrubNotifier.displayProgress * size.width;

    const double segH = 4.0;
    const double gap  = 1.5;
    const double step = segH + gap;
    final int maxSegs  = (midY ~/ step);

    final paint = Paint()..style = PaintingStyle.fill;

    // Background radial glow.
    if (fftNotifier.totalEnergy > 0.05) {
      final rect = Rect.fromCenter(
        center: Offset(size.width / 2, midY),
        width:  size.width,
        height: size.height * 0.8,
      );
      paint.shader = RadialGradient(
        colors: [
          glow.withValues(alpha: fftNotifier.totalEnergy * 0.4),
          Colors.transparent,
        ],
      ).createShader(rect);
      canvas.drawRect(rect, paint);
      paint.shader = null;
    }

    // Bars.
    for (var i = 0; i < _BlockNotifier.bins; i++) {
      final level = fftNotifier.smoothed[i];
      if (level < 0.02) continue;

      final cx         = (i + 0.5) * slotW;
      final x          = cx - barW / 2;
      final activeSegs = (level * maxSegs).ceil();
      final baseColor  = cx <= fillX ? playedColor : unplayedColor;

      for (var s = 0; s < activeSegs; s++) {
        final offset   = s * step;
        final segAlpha = (1.0 - (s / maxSegs) * 0.3).clamp(0.4, 1.0);

        // Top half.
        paint.color = baseColor.withValues(alpha: segAlpha);
        canvas.drawRect(
          Rect.fromLTWH(x, midY - offset - segH, barW, segH),
          paint,
        );

        // Bottom half (reflection).
        paint.color = baseColor.withValues(
          alpha: segAlpha * 0.35 * (1.0 - (s / activeSegs)),
        );
        canvas.drawRect(
          Rect.fromLTWH(x, midY + offset + gap, barW, segH),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CombinedBlockPainter old) => true;
}

class _ScrubOverlayPainter extends CustomPainter {
  final _ScrubNotifier notifier;
  final Color playedColor;
  final Color unplayedColor;

  _ScrubOverlayPainter({
    required this.notifier,
    required this.playedColor,
    required this.unplayedColor,
  }) : super(repaint: notifier);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final midY  = size.height / 2;
    final fillW = notifier.displayProgress * size.width;

    // Track background.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, midY - 1.5, size.width, 3),
        const Radius.circular(1.5),
      ),
      Paint()..color = unplayedColor.withValues(alpha: 0.20),
    );

    // Played fill.
    if (fillW > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, midY - 1.5, fillW, 3),
          const Radius.circular(1.5),
        ),
        Paint()..color = playedColor,
      );
    }

    // Drag thumb.
    if (notifier.dragging) {
      final cx = fillW.clamp(6.0, size.width - 6.0);
      canvas.drawCircle(
        Offset(cx, midY),
        18.0,
        Paint()
          ..color = playedColor.withValues(alpha: 0.18)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
      canvas.drawCircle(
        Offset(cx, midY),
        6.0,
        Paint()..color = AfColors.textPrimary,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ScrubOverlayPainter old) => false;
}
