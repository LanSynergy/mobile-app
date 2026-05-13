import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show FftFrame;

import '../state/providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AudioMotionVisualizer
//
// A single coherent spectrum renderer. Disciplined reduction over complexity.
//
// Design principles:
//   • One motion system. All bars share the same baseline and grow upward.
//   • Neighbor smoothing creates lateral wave propagation — bars feel
//     physically connected, not independently chaotic.
//   • Single accent color with vertical opacity fade — motion carries the
//     visual identity, not gradients.
//   • Restrained amplitude (72% of zone height max) — peaks feel impactful
//     because they have room to travel.
//   • No reflex, no peak dots, no jitter, no variable widths.
//
// Signal pipeline:
//   Raw FFT (48 bins resampled from 64) →
//   A-weighting (bass boost, treble cut) →
//   EMA smoothing (0.75) →
//   Neighbor blend (center 72%, left 14%, right 14%) →
//   Painter
//
// Architecture:
//   _AmaNotifier (ChangeNotifier) — signal processing, drives repaints
//   _AmaPainter  (CustomPainter, repaint: notifier) — pure rendering
//   Ticker stops when all bars have settled below threshold.
// ─────────────────────────────────────────────────────────────────────────────

class AudioMotionVisualizer extends ConsumerStatefulWidget {
  final double height;

  /// Gap between bars as a fraction of bar slot width [0, 1).
  final double barSpace;

  const AudioMotionVisualizer({
    super.key,
    this.height = 96,
    this.barSpace = 0.18,
  });

  @override
  ConsumerState<AudioMotionVisualizer> createState() =>
      _AudioMotionVisualizerState();
}

class _AudioMotionVisualizerState extends ConsumerState<AudioMotionVisualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;
  late final _AmaNotifier _notifier;
  StreamSubscription<FftFrame>? _fftSub;

  @override
  void initState() {
    super.initState();
    _notifier = _AmaNotifier();
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_onTick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _fftSub?.cancel();
    final svc = ref.read(playerServiceProvider);
    _fftSub = svc.spectrumStream.listen((frame) {
      _notifier.ingest(frame.bands);
      if (!_ticker.isAnimating) _ticker.repeat();
    });
  }

  @override
  void dispose() {
    _fftSub?.cancel();
    _ticker.dispose();
    _notifier.dispose();
    super.dispose();
  }

  void _onTick() {
    if (!mounted) return;
    if (!_notifier.tick()) _ticker.stop();
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
            notifier: _notifier,
            accent: spectral.energy,
            barSpace: widget.barSpace,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _AmaNotifier
//
// Two-stage smoothing:
//   Stage 1 — per-bar EMA: bars[i] = bars[i]*α + input[i]*(1-α)
//   Stage 2 — neighbor blend applied once per tick:
//              out[i] = bars[i]*0.72 + bars[i-1]*0.14 + bars[i+1]*0.14
//
// The neighbor blend is what creates lateral wave propagation — a kick
// drum doesn't just spike bar 3, it ripples into bars 2 and 4. This is
// the "inertia-based motion" that makes the renderer feel musically fluid
// rather than analytically precise.
// ─────────────────────────────────────────────────────────────────────────────

class _AmaNotifier extends ChangeNotifier {
  static const int _barCount = 48;

  // EMA smoothing coefficient. Higher = smoother, slower response.
  static const double _smoothing = 0.75;

  // Neighbor blend weights. Must sum to 1.0.
  static const double _wCenter = 0.72;
  static const double _wSide   = 0.14; // applied to both left and right

  static const double _settleThresh = 0.0006;

  // Stage-1 EMA output.
  final Float32List _ema = Float32List(_barCount);
  // Stage-2 neighbor-blended output — what the painter reads.
  final Float32List bars = Float32List(_barCount);

  /// Ingest one FFT frame (64 bins → resampled to 48).
  void ingest(Float32List fft) {
    final srcLen = fft.length; // 64

    for (var i = 0; i < _barCount; i++) {
      // Resample: map bar i to a fractional position in the 64-bin FFT.
      final srcF = i * (srcLen - 1) / (_barCount - 1);
      final lo   = srcF.floor().clamp(0, srcLen - 1);
      final hi   = (lo + 1).clamp(0, srcLen - 1);
      final frac = srcF - lo;
      final raw  = fft[lo] * (1.0 - frac) + fft[hi] * frac;
      final safe = raw.isFinite ? raw.clamp(0.0, 1.0) : 0.0;

      // A-weighting approximation: boost bass, attenuate treble.
      final t = i / (_barCount - 1); // 0=bass, 1=treble
      final double weighted;
      if (i < 5) {
        // Sub-bass: moderate sqrt boost.
        weighted = (safe < 0.0001 ? 0.0 : (safe * safe + safe) * 0.5 * 1.5)
            .clamp(0.0, 1.0);
      } else if (i < 12) {
        weighted = (safe * 1.25).clamp(0.0, 1.0);
      } else if (i < 24) {
        weighted = safe;
      } else {
        // Treble: gentle linear attenuation.
        weighted = (safe * (1.0 - t * 0.28)).clamp(0.0, 1.0);
      }

      // Stage 1: EMA per bar.
      _ema[i] = _ema[i] * _smoothing + weighted * (1.0 - _smoothing);
    }
  }

  /// Advance one frame. Returns true if any bar is still moving.
  bool tick() {
    var anyMoving = false;

    // Decay EMA toward zero (handles the "no FFT" / paused case).
    for (var i = 0; i < _barCount; i++) {
      _ema[i] *= _smoothing;
    }

    // Stage 2: neighbor blend → bars[].
    for (var i = 0; i < _barCount; i++) {
      final left  = i > 0              ? _ema[i - 1] : _ema[i];
      final right = i < _barCount - 1  ? _ema[i + 1] : _ema[i];
      final blended = _ema[i] * _wCenter + left * _wSide + right * _wSide;
      final prev = bars[i];
      bars[i] = blended;
      if ((bars[i] - prev).abs() > _settleThresh) anyMoving = true;
    }

    notifyListeners();
    return anyMoving;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _AmaPainter
//
// All bars share the same bottom baseline and grow upward.
// Amplitude is clamped to 72% of zone height — peaks have room to travel.
//
// Color: single accent, opacity modulated by height.
//   Bottom of bar: accent at full opacity.
//   Top of bar:    accent at 55% opacity.
// This creates a subtle vertical fade without a multi-stop gradient.
// ─────────────────────────────────────────────────────────────────────────────

class _AmaPainter extends CustomPainter {
  final _AmaNotifier notifier;
  final Color accent;
  final double barSpace;

  static const int    _barCount  = _AmaNotifier._barCount;
  static const double _maxFill   = 0.72; // max bar height as fraction of zone
  static const double _minBarPx  = 2.0;  // minimum visible bar height

  const _AmaPainter({
    required this.notifier,
    required this.accent,
    required this.barSpace,
  }) : super(repaint: notifier);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final zoneH    = size.height;
    final slotW    = size.width / _barCount;
    final barW     = slotW * (1.0 - barSpace.clamp(0.0, 0.9));
    final barOffX  = (slotW - barW) / 2;
    final maxBarH  = zoneH * _maxFill;
    final capR     = Radius.circular(barW / 2);

    final paint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < _barCount; i++) {
      final level = notifier.bars[i];
      if (level < 0.002) continue;

      final barH = (level * maxBarH).clamp(_minBarPx, maxBarH);
      final x    = i * slotW + barOffX;
      final y    = zoneH - barH;

      // Vertical opacity fade: bottom full, top 55%.
      // Implemented as a per-bar LinearGradient shader.
      final shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          accent,
          accent.withValues(alpha: 0.55),
        ],
      ).createShader(Rect.fromLTWH(x, y, barW, barH));

      paint.shader = shader;

      if (barH > barW) {
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTWH(x, y, barW, barH),
            topLeft: capR,
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
