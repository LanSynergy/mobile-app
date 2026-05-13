import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show FftFrame;

import '../state/providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AudioMotionVisualizer — three spectral actors with distinct motion semantics
//
// Regions:
//   Bass   (bins 0–7):   thick arcs, bottom-anchored, slow temporal decay
//   Mids   (bins 8–31):  thin segments, center-anchored, medium decay
//   Treble (bins 32–47): scattered dots, volatile vertical position, instant decay
//
// Motion semantics:
//   Bass   — lingers. Energy accumulates and releases slowly. Feels heavy.
//   Mids   — articulates. Tracks signal with moderate inertia. Feels structured.
//   Treble — evaporates. No decay — raw player output only. Feels unstable.
//
// Cross-region coupling (perceptual, not signal):
//   Bass peak energy → slightly amplifies mid arm height (pressure bleeds up)
//   Treble burst energy → slightly brightens mid opacity (shimmer bleeds down)
//
// Treble instability:
//   Dot vertical position is driven by the bin's own energy × a fixed
//   directional sign (up or down, seeded per bin). When energy spikes,
//   the dot jumps in its assigned direction. When energy drops, it returns
//   to center. No sine oscillation — position is purely energy-reactive.
//
// Silence contrast:
//   Each region has a minimum energy threshold below which it draws nothing.
//   The field breathes — silence looks like silence.
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

    // Ticker drives the decay loop for bass and mid temporal memory.
    // Treble has no decay — it reads raw player output directly.
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
//
// Owns three separate state layers with different temporal behavior:
//
//   bassSmoothed[i]  — slow decay (×0.82/frame). Bass lingers.
//   midSmoothed[i]   — medium decay (×0.68/frame). Mids articulate.
//   trebRaw[i]       — no decay. Raw player output. Treble evaporates.
//
// Cross-region coupling:
//   _bassPresence  — mean of top-4 bass bins. Bleeds into mid arm height.
//   _trebBurst     — mean of top-4 treble bins. Bleeds into mid opacity.
//
// Treble dot positions:
//   Each bin has a fixed directional sign (+1 or -1, seeded per bin).
//   Vertical offset = sign × energy × scatter amplitude.
//   No sine, no oscillation — purely energy-reactive.
// ─────────────────────────────────────────────────────────────────────────────

class _SpectralNotifier extends ChangeNotifier {
  static const int _n     = 48;
  static const int _nBass = 8;
  static const int _nMid  = 24;
  static const int _nTreb = 16;

  // Per-region smoothed state.
  final Float32List bassSmoothed = Float32List(_nBass);
  final Float32List midSmoothed  = Float32List(_nMid);
  final Float32List trebRaw      = Float32List(_nTreb); // no decay

  // Cross-region coupling signals.
  double _bassPresence = 0.0; // top-4 bass mean → mid arm amplifier
  double _trebBurst    = 0.0; // top-4 treble mean → mid opacity amplifier

  double get bassPresence => _bassPresence;
  double get trebBurst    => _trebBurst;

  // Treble directional signs — seeded once, deterministic per bin.
  // +1 = dot jumps upward on energy spike, -1 = downward.
  late final Int8List _trebSign;

  static const double _settleThresh = 0.0004;

  _SpectralNotifier() {
    final rng = math.Random(0xAF5EC);
    _trebSign = Int8List(_nTreb);
    for (var i = 0; i < _nTreb; i++) {
      _trebSign[i] = rng.nextBool() ? 1 : -1;
    }
  }

  int trebSign(int i) => _trebSign[i.clamp(0, _nTreb - 1)];

  void ingest(Float32List src) {
    final len = src.length < _n ? src.length : _n;

    // Bass: attack toward new value (fast up, slow down handled in tick).
    for (var i = 0; i < _nBass && i < len; i++) {
      final v = src[i].isFinite ? src[i].clamp(0.0, 1.0) : 0.0;
      if (v > bassSmoothed[i]) bassSmoothed[i] = v; // instant attack
    }

    // Mid: attack toward new value.
    for (var i = 0; i < _nMid; i++) {
      final srcIdx = _nBass + i;
      final v = srcIdx < len && src[srcIdx].isFinite
          ? src[srcIdx].clamp(0.0, 1.0)
          : 0.0;
      if (v > midSmoothed[i]) midSmoothed[i] = v; // instant attack
    }

    // Treble: raw, no smoothing.
    for (var i = 0; i < _nTreb; i++) {
      final srcIdx = _nBass + _nMid + i;
      trebRaw[i] = srcIdx < len && src[srcIdx].isFinite
          ? src[srcIdx].clamp(0.0, 1.0)
          : 0.0;
    }

    // Cross-region coupling: top-4 bass and treble means.
    var bassSum = 0.0;
    for (var i = _nBass - 4; i < _nBass; i++) { bassSum += bassSmoothed[i]; }
    _bassPresence = bassSum / 4;

    var trebSum = 0.0;
    for (var i = 0; i < 4; i++) { trebSum += trebRaw[i]; }
    _trebBurst = trebSum / 4;
  }

  /// Advance decay for bass and mid. Called every frame by the ticker.
  void tick() {
    var anyMoving = false;

    // Bass: slow decay — lingers.
    for (var i = 0; i < _nBass; i++) {
      final next = bassSmoothed[i] * 0.82;
      if ((bassSmoothed[i] - next).abs() > _settleThresh) anyMoving = true;
      bassSmoothed[i] = next;
    }

    // Mid: medium decay — articulates.
    for (var i = 0; i < _nMid; i++) {
      final next = midSmoothed[i] * 0.68;
      if ((midSmoothed[i] - next).abs() > _settleThresh) anyMoving = true;
      midSmoothed[i] = next;
    }

    notifyListeners();
    // Stop ticker when everything has settled (treble is raw — always settles
    // on its own when the stream stops emitting).
    if (!anyMoving) {
      // Ticker will be restarted on next ingest().
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SpectralPainter
// ─────────────────────────────────────────────────────────────────────────────

class _SpectralPainter extends CustomPainter {
  final _SpectralNotifier notifier;
  final Color energy;
  final Color glow;
  final Color shadow;

  static const int _nBass = _SpectralNotifier._nBass;
  static const int _nMid  = _SpectralNotifier._nMid;
  static const int _nTreb = _SpectralNotifier._nTreb;

  static const double _bassZoneW = 0.28;
  static const double _midZoneW  = 0.46;
  static const double _trebZoneW = 0.26;

  // Bass geometry.
  static const double _bassGap     = 0.42;
  static const double _bassMaxFill = 0.82;

  // Mid geometry.
  static const double _midGap     = 0.22;
  static const double _midMaxArm  = 0.44; // fraction of half-height

  // Treble geometry.
  static const double _trebMaxR    = 3.2;
  static const double _trebScatter = 0.40;

  // Silence thresholds — below these, nothing is drawn.
  static const double _bassThresh = 0.018;
  static const double _midThresh  = 0.012;
  static const double _trebThresh = 0.025;

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
    final bassZW = W * _bassZoneW;
    final midX0  = bassZW;
    final midZW  = W * _midZoneW;
    final trebX0 = bassZW + midZW;
    final trebZW = W * _trebZoneW;

    _paintBass(canvas, bassX0, bassZW, H);
    _paintMid(canvas, midX0, midZW, H);
    _paintTreble(canvas, trebX0, trebZW, H);
  }

  // ── Bass ────────────────────────────────────────────────────────────────

  void _paintBass(Canvas canvas, double x0, double zoneW, double H) {
    final slotW = zoneW / _nBass;
    final paint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < _nBass; i++) {
      final level = notifier.bassSmoothed[i];
      if (level < _bassThresh) continue;

      // Width expands with energy — mass, not just height.
      final widthFrac = 0.30 + level * 0.70;
      final barW = slotW * (1.0 - _bassGap) * widthFrac;
      final x    = x0 + i * slotW + (slotW - barW) / 2;
      final barH = (level * H * _bassMaxFill).clamp(2.0, H * _bassMaxFill);
      final y    = H - barH;
      final r    = Radius.circular(barW / 2);

      paint.color = Color.lerp(shadow, energy, level)!
          .withValues(alpha: 0.50 + level * 0.50);

      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(x, y, barW, barH),
          topLeft: r, topRight: r,
        ),
        paint,
      );
    }
  }

  // ── Mids ────────────────────────────────────────────────────────────────

  void _paintMid(Canvas canvas, double x0, double zoneW, double H) {
    final slotW  = zoneW / _nMid;
    final midY   = H / 2;
    final maxArm = H / 2 * _midMaxArm;
    final paint  = Paint()..style = PaintingStyle.fill;

    // Cross-region coupling: bass presence amplifies arm height slightly.
    // Treble burst brightens opacity slightly.
    final bassLift  = notifier.bassPresence * 0.22; // 0–0.22 extra arm fraction
    final trebShine = notifier.trebBurst    * 0.25; // 0–0.25 extra opacity

    for (var i = 0; i < _nMid; i++) {
      final level = notifier.midSmoothed[i];
      if (level < _midThresh) continue;

      final barW = slotW * (1.0 - _midGap);
      final x    = x0 + i * slotW + (slotW - barW) / 2;
      final arm  = ((level + bassLift) * maxArm).clamp(1.5, maxArm * 1.22);
      final r    = Radius.circular(barW / 2);

      paint.color = energy.withValues(
        alpha: (0.35 + level * 0.55 + trebShine).clamp(0.0, 1.0),
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, midY - arm, barW, arm * 2),
          r,
        ),
        paint,
      );
    }
  }

  // ── Treble ──────────────────────────────────────────────────────────────

  void _paintTreble(Canvas canvas, double x0, double zoneW, double H) {
    final slotW   = zoneW / _nTreb;
    final midY    = H / 2;
    final scatter = H * _trebScatter;
    final paint   = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < _nTreb; i++) {
      final level = notifier.trebRaw[i];
      if (level < _trebThresh) continue;

      // Vertical position: fixed directional sign × energy × scatter.
      // No sine — purely energy-reactive. Dot jumps in its assigned
      // direction when energy spikes, returns to center when it drops.
      final sign   = notifier.trebSign(i).toDouble();
      final cy     = midY + sign * level * scatter;
      final cx     = x0 + i * slotW + slotW / 2;
      final radius = (_trebMaxR * level).clamp(0.6, _trebMaxR);

      paint.color = glow.withValues(alpha: 0.30 + level * 0.70);

      canvas.drawCircle(Offset(cx, cy), radius, paint);
    }
  }

  @override
  bool shouldRepaint(_SpectralPainter old) =>
      old.energy != energy || old.glow != glow || old.shadow != shadow;
}
