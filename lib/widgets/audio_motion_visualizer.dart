import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show FftFrame;

import '../state/providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AudioMotionVisualizer
//
// The player pipeline (mpv_audio_kit) already owns:
//   • perceptual band mapping (48 log-spaced bands)
//   • psychoacoustic amplitude scaling
//   • asymmetric EMA smoothing (attack 0.72 / release 0.16)
//   • fixed 60 fps cadence
//
// This widget is a topology renderer, not a signal processor.
// It applies one light transform — neighbor blending for lateral coherence —
// then paints. No EMA, no decay loop, no ticker, no synthetic animation.
//
// Signal path:
//   Player.stream.spectrum (48 bands, 60 fps, pre-smoothed)
//     → _AmaNotifier.ingest()   — neighbor blend only
//     → notifyListeners()       — triggers repaint
//     → _AmaPainter.paint()     — draws bars
//
// The stream cadence IS the animation loop. Removing the ticker eliminates
// synthetic frame pumping, reduces UI-thread wakeups, and cuts raster churn —
// especially important on OLED where unnecessary repaints cost battery.
// ─────────────────────────────────────────────────────────────────────────────

class AudioMotionVisualizer extends ConsumerStatefulWidget {
  final double height;
  final double barSpace;

  const AudioMotionVisualizer({
    super.key,
    this.height   = 96,
    this.barSpace = 0.18,
  });

  @override
  ConsumerState<AudioMotionVisualizer> createState() =>
      _AudioMotionVisualizerState();
}

class _AudioMotionVisualizerState extends ConsumerState<AudioMotionVisualizer> {
  final _notifier = _AmaNotifier();
  StreamSubscription<FftFrame>? _fftSub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _fftSub?.cancel();
    _fftSub = ref.read(playerServiceProvider).spectrumStream.listen(
      (frame) => _notifier.ingest(frame.bands),
    );
  }

  @override
  void dispose() {
    _fftSub?.cancel();
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
          painter: _AmaPainter(
            notifier:  _notifier,
            accent:    spectral.energy,
            barSpace:  widget.barSpace,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _AmaNotifier — topology transform only
//
// Neighbor blend: out[i] = src[i]*0.84 + src[i-1]*0.08 + src[i+1]*0.08
//
// This creates lateral wave propagation — a transient in bin 10 ripples
// into bins 9 and 11 — without adding any temporal smoothing on top of
// what the player already provides. Weights are tighter than before
// (0.84/0.08/0.08 vs 0.72/0.14/0.14) because upstream smoothing already
// exists; heavier blending would create gelatin motion.
// ─────────────────────────────────────────────────────────────────────────────

class _AmaNotifier extends ChangeNotifier {
  static const int _n = 48;

  final Float32List bars = Float32List(_n);

  void ingest(Float32List src) {
    // src is already 48 bands from the player (bandCount: 48 in configureSpectrum).
    // If the player emits a different length for any reason, clamp safely.
    final len = src.length < _n ? src.length : _n;

    for (var i = 0; i < len; i++) {
      final left  = src[(i - 1).clamp(0, len - 1)];
      final mid   = src[i].isFinite ? src[i] : 0.0;
      final right = src[(i + 1).clamp(0, len - 1)];
      bars[i] = mid * 0.84 + left * 0.08 + right * 0.08;
    }

    notifyListeners();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _AmaPainter
//
// Uniform bars, bottom-anchored, growing upward.
// Amplitude clamped to 72% of zone height — peaks have room to travel.
// Single accent color with vertical opacity fade (100% → 55%).
// Motion carries the visual identity; color just tints it.
// ─────────────────────────────────────────────────────────────────────────────

class _AmaPainter extends CustomPainter {
  final _AmaNotifier notifier;
  final Color        accent;
  final double       barSpace;

  static const int    _n       = _AmaNotifier._n;
  static const double _maxFill = 0.72;
  static const double _minPx   = 2.0;

  const _AmaPainter({
    required this.notifier,
    required this.accent,
    required this.barSpace,
  }) : super(repaint: notifier);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final zoneH   = size.height;
    final slotW   = size.width / _n;
    final barW    = slotW * (1.0 - barSpace.clamp(0.0, 0.9));
    final offsetX = (slotW - barW) / 2;
    final maxH    = zoneH * _maxFill;
    final capR    = Radius.circular(barW / 2);
    final paint   = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < _n; i++) {
      final level = notifier.bars[i];
      if (level < 0.002) continue;

      final barH = (level * maxH).clamp(_minPx, maxH);
      final x    = i * slotW + offsetX;
      final y    = zoneH - barH;

      // Vertical opacity fade: full at base, 55% at tip.
      paint.shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end:   Alignment.topCenter,
        colors: [accent, accent.withValues(alpha: 0.55)],
      ).createShader(Rect.fromLTWH(x, y, barW, barH));

      if (barH > barW) {
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTWH(x, y, barW, barH),
            topLeft:  capR,
            topRight: capR,
          ),
          paint,
        );
      } else {
        canvas.drawRect(Rect.fromLTWH(x, y, barW, barH), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_AmaPainter old) =>
      old.accent != accent || old.barSpace != barSpace;
}
