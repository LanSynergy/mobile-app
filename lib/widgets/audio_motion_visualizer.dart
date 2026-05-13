import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show FftFrame;

import '../state/providers.dart';

class AudioMotionVisualizer extends ConsumerStatefulWidget {
  final double height;

  const AudioMotionVisualizer({super.key, this.height = 120});

  @override
  ConsumerState<AudioMotionVisualizer> createState() =>
      _AudioMotionVisualizerState();
}

class _AudioMotionVisualizerState extends ConsumerState<AudioMotionVisualizer>
    with SingleTickerProviderStateMixin {
  late final _BlockNotifier _notifier;
  late final AnimationController _ticker;
  StreamSubscription<FftFrame>? _fftSub;

  @override
  void initState() {
    super.initState();
    _notifier = _BlockNotifier();
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(() {
        if (mounted) _notifier.tick();
      });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _fftSub = ref.read(playerServiceProvider).spectrumStream.listen(
        (frame) {
          _notifier.ingest(frame.bands);
          if (!_ticker.isAnimating) _ticker.repeat();
        },
      );
    });
  }

  @override
  void dispose() {
    _fftSub?.cancel();
    _ticker.dispose();
    _notifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spectral = ref.watch(currentSpectralProvider);
    return RepaintBoundary(
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: CustomPaint(
          painter: _BlockPainter(
            notifier: _notifier,
            energy:   spectral.energy,
            glow:     spectral.glow,
          ),
        ),
      ),
    );
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
    var moving = false;
    for (var i = 0; i < bins; i++) {
      final next = smoothed[i] * 0.75;
      if ((smoothed[i] - next).abs() > 0.001) moving = true;
      smoothed[i] = next;
    }
    notifyListeners();
    if (!moving) {
      // Caller (ticker listener) will stop the ticker when nothing is moving.
    }
  }
}

class _BlockPainter extends CustomPainter {
  final _BlockNotifier notifier;
  final Color energy;
  final Color glow;

  const _BlockPainter({
    required this.notifier,
    required this.energy,
    required this.glow,
  }) : super(repaint: notifier);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    const int bins   = _BlockNotifier.bins;
    final double slotW = size.width / bins;
    final double barW  = (slotW * 0.7).clamp(1.0, 8.0);
    final double midY  = size.height / 2;

    const double segH = 4.0;
    const double gap  = 1.5;
    final double step = segH + gap;
    final int maxSegs  = (midY ~/ step);

    final paint = Paint()..style = PaintingStyle.fill;

    // Background radial glow.
    if (notifier.totalEnergy > 0.05) {
      final rect = Rect.fromCenter(
        center: Offset(size.width / 2, midY),
        width:  size.width,
        height: size.height * 0.8,
      );
      paint.shader = RadialGradient(
        colors: [
          glow.withValues(alpha: notifier.totalEnergy * 0.4),
          Colors.transparent,
        ],
      ).createShader(rect);
      canvas.drawRect(rect, paint);
      paint.shader = null;
    }

    // Bars.
    for (var i = 0; i < bins; i++) {
      final level = notifier.smoothed[i];
      if (level < 0.02) continue;

      final activeSegs = (level * maxSegs).ceil();
      final cx = (i + 0.5) * slotW;
      final x  = cx - barW / 2;

      for (var s = 0; s < activeSegs; s++) {
        final offset   = s * step;
        // Brighter at base, slight alpha drop toward peaks.
        final segAlpha = (1.0 - (s / maxSegs) * 0.3).clamp(0.4, 1.0);

        // Top half (main).
        paint.color = energy.withValues(alpha: segAlpha);
        canvas.drawRect(
          Rect.fromLTWH(x, midY - offset - segH, barW, segH),
          paint,
        );

        // Bottom half (reflection) — fades out quickly.
        final refAlpha = segAlpha * 0.35 * (1.0 - (s / activeSegs));
        paint.color = energy.withValues(alpha: refAlpha);
        canvas.drawRect(
          Rect.fromLTWH(x, midY + offset + gap, barW, segH),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BlockPainter old) =>
      old.energy != energy || old.glow != glow;
}
