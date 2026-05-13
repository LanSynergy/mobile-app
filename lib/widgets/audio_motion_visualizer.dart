import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show FftFrame;

import '../state/providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AudioMotionVisualizer — one interacting spectral field
//
// Three species coexist in the SAME canvas space. Zones define motion law,
// not territory. Every bin can draw anywhere.
//
// Bass   (bins 0–7):   thick arcs, bottom-anchored, full-width spread,
//                      slow decay. Pressure glow bleeds upward.
// Mids   (bins 8–31):  thin segments, center-anchored, full-width spread,
//                      medium decay. Slightly jittered horizontal position.
// Treble (bins 32–47): small dots, scattered across full height and width,
//                      no decay. Occasionally drift into mid territory.
//
// Spatial rules:
//   - No hard zone boundaries. All three layers draw on the full canvas.
//   - Horizontal positions are log-spaced across full width with per-bin
//     deterministic jitter — breaks grid identity without chaos.
//   - Bass glow extends upward as a soft bloom, bleeding into mid space.
//   - Treble dots scatter vertically across the full zone height.
//
// Motion semantics (unchanged):
//   Bass   — instant attack, slow decay (×0.82). Lingers.
//   Mids   — instant attack, medium decay (×0.68). Articulates.
//   Treble — raw player output, no decay. Evaporates.
//
// Cross-region coupling (perceptual):
//   Bass peak → amplifies mid arm height slightly.
//   Treble burst → brightens mid opacity slightly.
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

class _AudioMotionVisualizerState extends ConsumerState<AudioMotionVisualizer>
    with SingleTickerProviderStateMixin {
  late final _SpectralNotifier _notifier;
  late final AnimationController _ticker;
  StreamSubscription<FftFrame>? _fftSub;

  @override
  void initState() {
    super.initState();
    _notifier = _SpectralNotifier();
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
// ─────────────────────────────────────────────────────────────────────────────

class _SpectralNotifier extends ChangeNotifier {
  static const int _n     = 48;
  static const int _nBass = 8;
  static const int _nMid  = 24;
  static const int _nTreb = 16;

  final Float32List bassSmoothed = Float32List(_nBass);
  final Float32List midSmoothed  = Float32List(_nMid);
  final Float32List trebRaw      = Float32List(_nTreb);

  double _bassPresence = 0.0;
  double _trebBurst    = 0.0;
  double get bassPresence => _bassPresence;
  double get trebBurst    => _trebBurst;

  // Per-bin horizontal jitter: small deterministic offset from the
  // log-spaced center position. Breaks grid identity.
  late final Float32List bassJitter; // fraction of slot width, [-0.3, 0.3]
  late final Float32List midJitter;
  late final Float32List trebJitter;

  // Treble directional signs for vertical scatter.
  late final Int8List _trebSign;

  static const double _settleThresh = 0.0004;

  _SpectralNotifier() {
    final rng = math.Random(0xAF5EC);

    _trebSign  = Int8List(_nTreb);
    bassJitter = Float32List(_nBass);
    midJitter  = Float32List(_nMid);
    trebJitter = Float32List(_nTreb);

    for (var i = 0; i < _nBass; i++) {
      bassJitter[i] = (rng.nextDouble() - 0.5) * 0.30;
    }
    for (var i = 0; i < _nMid; i++) {
      midJitter[i] = (rng.nextDouble() - 0.5) * 0.20;
    }
    for (var i = 0; i < _nTreb; i++) {
      _trebSign[i]  = rng.nextBool() ? 1 : -1;
      trebJitter[i] = (rng.nextDouble() - 0.5) * 0.40;
    }
  }

  int trebSign(int i) => _trebSign[i.clamp(0, _nTreb - 1)];

  void ingest(Float32List src) {
    final len = src.length < _n ? src.length : _n;

    for (var i = 0; i < _nBass && i < len; i++) {
      final v = src[i].isFinite ? src[i].clamp(0.0, 1.0) : 0.0;
      if (v > bassSmoothed[i]) bassSmoothed[i] = v;
    }
    for (var i = 0; i < _nMid; i++) {
      final srcIdx = _nBass + i;
      final v = srcIdx < len && src[srcIdx].isFinite
          ? src[srcIdx].clamp(0.0, 1.0) : 0.0;
      if (v > midSmoothed[i]) midSmoothed[i] = v;
    }
    for (var i = 0; i < _nTreb; i++) {
      final srcIdx = _nBass + _nMid + i;
      trebRaw[i] = srcIdx < len && src[srcIdx].isFinite
          ? src[srcIdx].clamp(0.0, 1.0) : 0.0;
    }

    // Cross-region coupling signals.
    var bassSum = 0.0;
    for (var i = _nBass - 4; i < _nBass; i++) { bassSum += bassSmoothed[i]; }
    _bassPresence = bassSum / 4;

    var trebSum = 0.0;
    for (var i = 0; i < 4; i++) { trebSum += trebRaw[i]; }
    _trebBurst = trebSum / 4;
  }

  void tick() {
    var anyMoving = false;
    for (var i = 0; i < _nBass; i++) {
      final next = bassSmoothed[i] * 0.82;
      if ((bassSmoothed[i] - next).abs() > _settleThresh) anyMoving = true;
      bassSmoothed[i] = next;
    }
    for (var i = 0; i < _nMid; i++) {
      final next = midSmoothed[i] * 0.68;
      if ((midSmoothed[i] - next).abs() > _settleThresh) anyMoving = true;
      midSmoothed[i] = next;
    }
    notifyListeners();
    if (!anyMoving) _ticker?.stop();
  }

  // Ticker reference for self-stopping — set by the state.
  AnimationController? _ticker;
}

// ─────────────────────────────────────────────────────────────────────────────
// _SpectralPainter
//
// All three layers draw on the full canvas. Horizontal positions are
// log-spaced across the full width with per-bin jitter.
//
// Rendering order: bass (bottom) → mid (middle) → treble (top).
// Layers overlap — treble dots can appear over mid segments, bass glow
// bleeds into mid territory. This creates field depth, not segmentation.
// ─────────────────────────────────────────────────────────────────────────────

class _SpectralPainter extends CustomPainter {
  final _SpectralNotifier notifier;
  final Color energy;
  final Color glow;
  final Color shadow;

  static const int _nBass = _SpectralNotifier._nBass;
  static const int _nMid  = _SpectralNotifier._nMid;
  static const int _nTreb = _SpectralNotifier._nTreb;

  // Geometry constants.
  static const double _bassBarW    = 7.0;  // base bar width dp
  static const double _bassMaxFill = 0.82;
  static const double _midBarW     = 2.5;  // thin segments
  static const double _midMaxArm   = 0.44; // fraction of half-height
  static const double _trebMaxR    = 3.0;
  static const double _trebScatter = 0.42; // vertical scatter fraction

  // Silence thresholds.
  static const double _bassThresh = 0.018;
  static const double _midThresh  = 0.012;
  static const double _trebThresh = 0.022;

  const _SpectralPainter({
    required this.notifier,
    required this.energy,
    required this.glow,
    required this.shadow,
  }) : super(repaint: notifier);

  /// Log-spaced x position for bin [i] out of [n] across [width].
  /// Gives more horizontal space to low-frequency bins (perceptually wider).
  double _logX(int i, int n, double width) {
    // Map i → [0,1] on a log scale so low bins are spread wider.
    final t = math.log(1 + i) / math.log(1 + n);
    return t * width;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final W = size.width;
    final H = size.height;

    // Cross-region coupling.
    final bassLift  = notifier.bassPresence * 0.22;
    final trebShine = notifier.trebBurst    * 0.25;

    final paint = Paint()..style = PaintingStyle.fill;

    // ── Layer 1: Bass ──────────────────────────────────────────────────────
    // Bottom-anchored arcs spread across full width (log-spaced).
    // Glow bloom extends upward, bleeding into mid territory.
    for (var i = 0; i < _nBass; i++) {
      final level = notifier.bassSmoothed[i];
      if (level < _bassThresh) continue;

      // Log-spaced center + jitter.
      final cx   = _logX(i, _nBass, W) + notifier.bassJitter[i] * (W / _nBass);
      final barW = (_bassBarW * (0.5 + level * 0.5)).clamp(2.0, _bassBarW * 1.4);
      final x    = cx - barW / 2;
      final barH = (level * H * _bassMaxFill).clamp(2.0, H * _bassMaxFill);
      final y    = H - barH;
      final r    = Radius.circular(barW / 2);

      // Bar body.
      paint.color = Color.lerp(shadow, energy, level)!
          .withValues(alpha: 0.55 + level * 0.45);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(x, y, barW, barH),
          topLeft: r, topRight: r,
        ),
        paint,
      );

      // Upward pressure glow — bleeds into mid space.
      if (level > 0.25) {
        final glowH = barH * 0.55 * level;
        canvas.drawRect(
          Rect.fromLTWH(cx - barW * 2, y - glowH, barW * 4, glowH),
          Paint()
            ..color = energy.withValues(alpha: level * 0.12)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
        );
      }
    }

    // ── Layer 2: Mids ──────────────────────────────────────────────────────
    // Center-anchored segments spread across full width (linear-spaced).
    for (var i = 0; i < _nMid; i++) {
      final level = notifier.midSmoothed[i];
      if (level < _midThresh) continue;

      // Linear spacing across full width + jitter.
      final slotW = W / _nMid;
      final cx    = (i + 0.5) * slotW + notifier.midJitter[i] * slotW;
      final x     = cx - _midBarW / 2;
      final midY  = H / 2;
      final maxArm = H / 2 * _midMaxArm;
      final arm   = ((level + bassLift) * maxArm).clamp(1.5, maxArm * 1.22);
      final r     = const Radius.circular(_midBarW / 2);

      paint.color = energy.withValues(
        alpha: (0.30 + level * 0.60 + trebShine).clamp(0.0, 1.0),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, midY - arm, _midBarW, arm * 2),
          r,
        ),
        paint,
      );
    }

    // ── Layer 3: Treble ────────────────────────────────────────────────────
    // Dots scattered across full width AND full height.
    // Vertical position: sign × energy × scatter (energy-reactive, not sine).
    for (var i = 0; i < _nTreb; i++) {
      final level = notifier.trebRaw[i];
      if (level < _trebThresh) continue;

      // Spread across full width with jitter — treble invades mid territory.
      final slotW  = W / _nTreb;
      final cx     = (i + 0.5) * slotW + notifier.trebJitter[i] * slotW;
      final midY   = H / 2;
      final scatter = H * _trebScatter;
      final sign   = notifier.trebSign(i).toDouble();
      final cy     = midY + sign * level * scatter;
      final radius = (_trebMaxR * level).clamp(0.5, _trebMaxR);

      paint.color = glow.withValues(alpha: 0.28 + level * 0.72);
      canvas.drawCircle(Offset(cx, cy), radius, paint);
    }
  }

  @override
  bool shouldRepaint(_SpectralPainter old) =>
      old.energy != energy || old.glow != glow || old.shadow != shadow;
}
