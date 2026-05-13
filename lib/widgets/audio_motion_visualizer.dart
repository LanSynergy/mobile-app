import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show FftFrame;

import '../state/providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AudioMotionVisualizer — three spectral actors
//
// Each frequency region owns its own motion law, geometry, and visual language.
// No shared rendering. No neighbor blending. No global gradient.
//
// Bass   (bins 0–7):   thick arcs, bottom-anchored, wide, heavy
// Mids   (bins 8–31):  vertical segments, center-anchored, structured
// Treble (bins 32–47): scattered dots, random vertical scatter, fast flicker
//
// The player pipeline owns all temporal smoothing (attack 0.72 / release 0.08).
// This renderer owns only geometry and paint — no DSP.
//
// Stream lifecycle: subscribed once in initState via addPostFrameCallback.
// The stream cadence (60 fps) drives repaints directly — no ticker.
// ─────────────────────────────────────────────────────────────────────────────

class AudioMotionVisualizer extends ConsumerStatefulWidget {
  final double height;

  const AudioMotionVisualizer({
    super.key,
    this.height = 96,
  });

  @override
  ConsumerState<AudioMotionVisualizer> createState() =>
      _AudioMotionVisualizerState();
}

class _AudioMotionVisualizerState extends ConsumerState<AudioMotionVisualizer> {
  final _notifier = _SpectralNotifier();
  StreamSubscription<FftFrame>? _fftSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _fftSub = ref.read(playerServiceProvider).spectrumStream.listen(
        (frame) => _notifier.ingest(frame.bands),
      );
    });
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
          painter: _SpectralPainter(
            notifier: _notifier,
            energy:   spectral.energy,
            glow:     spectral.glow,
            shadow:   spectral.shadow,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SpectralNotifier
//
// Stores the raw band values from the player. No processing — the player
// already applied attack/release smoothing. The notifier just holds state
// and notifies the painter on each new frame.
//
// Treble dot positions are seeded deterministically per bin so they don't
// jump on every frame — only their vertical scatter amplitude changes with
// energy.
// ─────────────────────────────────────────────────────────────────────────────

class _SpectralNotifier extends ChangeNotifier {
  static const int _n      = 48;
  static const int _nBass  = 8;   // bins 0–7
  static const int _nMid   = 24;  // bins 8–31
  static const int _nTreb  = 16;  // bins 32–47

  final Float32List bands = Float32List(_n);

  // Treble dot vertical offsets — seeded once, deterministic per bin.
  // Each treble bin gets a fixed horizontal sub-position within its slot
  // and a fixed phase offset for its scatter animation.
  late final Float32List _trebPhase;

  _SpectralNotifier() {
    final rng = math.Random(0xAF5EC); // deterministic seed
    _trebPhase = Float32List(_nTreb);
    for (var i = 0; i < _nTreb; i++) {
      _trebPhase[i] = rng.nextDouble() * math.pi * 2;
    }
  }

  void ingest(Float32List src) {
    final len = src.length < _n ? src.length : _n;
    for (var i = 0; i < len; i++) {
      bands[i] = src[i].isFinite ? src[i].clamp(0.0, 1.0) : 0.0;
    }
    notifyListeners();
  }

  double bassAt(int i)  => bands[i.clamp(0, _nBass - 1)];
  double midAt(int i)   => bands[(_nBass + i).clamp(0, _nBass + _nMid - 1)];
  double trebAt(int i)  => bands[(_nBass + _nMid + i).clamp(0, _n - 1)];
  double trebPhase(int i) => _trebPhase[i.clamp(0, _nTreb - 1)];
}

// ─────────────────────────────────────────────────────────────────────────────
// _SpectralPainter — three distinct rendering regions
//
// Bass region (left ~25% of width):
//   Thick rounded rectangles, bottom-anchored.
//   Width scales with energy — wide at full energy, narrow at low.
//   Color: shadow → energy gradient, local per-bar.
//   Gap between bars is large (0.45) so each arc reads as a distinct mass.
//
// Mid region (center ~50% of width):
//   Thin vertical segments, center-anchored (grow up AND down from midline).
//   Uniform width. Color: energy at full opacity.
//   Tight spacing (0.15 gap) — reads as a structured field.
//
// Treble region (right ~25% of width):
//   Small circles scattered vertically within the zone.
//   Vertical position = midline ± (energy × scatter amplitude × phase offset).
//   Radius scales with energy. Color: glow.
//   No alignment — deliberately unstable.
// ─────────────────────────────────────────────────────────────────────────────

class _SpectralPainter extends CustomPainter {
  final _SpectralNotifier notifier;
  final Color energy;
  final Color glow;
  final Color shadow;

  static const int _nBass = _SpectralNotifier._nBass;
  static const int _nMid  = _SpectralNotifier._nMid;
  static const int _nTreb = _SpectralNotifier._nTreb;

  // Zone width fractions.
  static const double _bassW = 0.28;
  static const double _midW  = 0.46;
  static const double _trebW = 0.26;

  // Bass geometry.
  static const double _bassGap     = 0.45; // fraction of slot
  static const double _bassMaxFill = 0.80; // max height fraction of zone

  // Mid geometry.
  static const double _midGap     = 0.20;
  static const double _midMaxFill = 0.90; // half-height each direction

  // Treble geometry.
  static const double _trebMaxR    = 3.5;  // max dot radius dp
  static const double _trebScatter = 0.38; // vertical scatter as fraction of zone

  const _SpectralPainter({
    required this.notifier,
    required this.energy,
    required this.glow,
    required this.shadow,
  }) : super(repaint: notifier);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final W = size.width;
    final H = size.height;

    final bassX0 = 0.0;
    final bassW  = W * _bassW;
    final midX0  = bassW;
    final midW   = W * _midW;
    final trebX0 = bassW + midW;

    _paintBass(canvas, bassX0, bassW, H);
    _paintMid(canvas, midX0, midW, H);
    _paintTreble(canvas, trebX0, W * _trebW, H);
  }

  // ── Bass: thick bottom-anchored arcs ────────────────────────────────────

  void _paintBass(Canvas canvas, double x0, double zoneW, double H) {
    final slotW = zoneW / _nBass;
    final paint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < _nBass; i++) {
      final level = notifier.bassAt(i);
      if (level < 0.01) continue;

      // Width scales with energy: full energy = full slot width minus gap.
      // Low energy = narrower bar — creates visual mass differentiation.
      final widthFrac = 0.35 + level * 0.65; // 35%–100% of (slot - gap)
      final barW = slotW * (1.0 - _bassGap) * widthFrac;
      final x    = x0 + i * slotW + (slotW - barW) / 2;
      final barH = (level * H * _bassMaxFill).clamp(2.0, H * _bassMaxFill);
      final y    = H - barH;
      final r    = Radius.circular(barW / 2);

      // Per-bar color: low energy = shadow, high energy = energy color.
      paint.color = Color.lerp(shadow, energy, level)!
          .withValues(alpha: 0.55 + level * 0.45);

      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(x, y, barW, barH),
          topLeft: r, topRight: r,
        ),
        paint,
      );
    }
  }

  // ── Mids: thin center-anchored segments ─────────────────────────────────

  void _paintMid(Canvas canvas, double x0, double zoneW, double H) {
    final slotW  = zoneW / _nMid;
    final midY   = H / 2;
    final maxArm = H / 2 * _midMaxFill; // max half-height
    final paint  = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < _nMid; i++) {
      final level = notifier.midAt(i);
      if (level < 0.015) continue;

      final barW = slotW * (1.0 - _midGap);
      final x    = x0 + i * slotW + (slotW - barW) / 2;
      final arm  = (level * maxArm).clamp(1.5, maxArm);
      final r    = Radius.circular(barW / 2);

      paint.color = energy.withValues(alpha: 0.40 + level * 0.60);

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, midY - arm, barW, arm * 2),
          r,
        ),
        paint,
      );
    }
  }

  // ── Treble: scattered dots ───────────────────────────────────────────────

  void _paintTreble(Canvas canvas, double x0, double zoneW, double H) {
    final slotW  = zoneW / _nTreb;
    final midY   = H / 2;
    final scatter = H * _trebScatter;
    final paint  = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < _nTreb; i++) {
      final level = notifier.trebAt(i);
      if (level < 0.02) continue;

      // Dot center: midline ± scatter driven by energy × phase.
      // Phase is fixed per bin — the dot doesn't jump randomly each frame,
      // it oscillates at a fixed position scaled by energy.
      final phase  = notifier.trebPhase(i);
      final cy     = midY + math.sin(phase) * scatter * level;
      final cx     = x0 + i * slotW + slotW / 2;
      final radius = (_trebMaxR * level).clamp(0.8, _trebMaxR);

      paint.color = glow.withValues(alpha: 0.35 + level * 0.65);

      canvas.drawCircle(Offset(cx, cy), radius, paint);
    }
  }

  @override
  bool shouldRepaint(_SpectralPainter old) =>
      old.energy != energy || old.glow != glow || old.shadow != shadow;
}
