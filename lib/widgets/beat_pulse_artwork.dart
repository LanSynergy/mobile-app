import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import 'artwork.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BeatPulseArtwork
//
// Album artwork surrounded by three reactive radial layers driven by the
// live FFT spectrum:
//
//   • Inner core  — bass energy  (bands 0–7,   ~20–250 Hz)
//     Drives a subtle scale pulse on the artwork itself (1.0 → 1.06).
//
//   • Mid ring    — mid energy   (bands 8–31,  ~250 Hz–4 kHz)
//     A thin ring that expands outward and fades on beats.
//
//   • Outer halo  — treble energy (bands 32–63, ~4–20 kHz)
//     A soft bloom painted with a radial gradient; opacity tracks treble.
//
// All three layers use independent attack/release envelopes so bass
// punches fast while treble shimmers slowly.
//
// Static pose (no audio): all layers at rest, no animation running.
// ─────────────────────────────────────────────────────────────────────────────

class BeatPulseArtwork extends ConsumerStatefulWidget {
  final String? imageUrl;
  final double size;
  final BorderRadius radius;

  const BeatPulseArtwork({
    super.key,
    required this.imageUrl,
    required this.size,
    required this.radius,
  });

  @override
  ConsumerState<BeatPulseArtwork> createState() => _BeatPulseArtworkState();
}

class _BeatPulseArtworkState extends ConsumerState<BeatPulseArtwork>
    with SingleTickerProviderStateMixin {
  // ── Animation controller drives 60 fps repaints ──────────────────────────
  late final AnimationController _ticker;

  // ── Per-band-group smoothed energy [0, 1] ────────────────────────────────
  double _bass = 0.0;   // inner core / scale
  double _mid  = 0.0;   // mid ring
  double _treble = 0.0; // outer halo

  // ── Attack / release lerp constants ──────────────────────────────────────
  // Bass: fast attack so kick drums feel snappy.
  static const double _bassAttack   = 0.55;
  static const double _bassRelease  = 0.10;
  // Mid: medium — snare / guitar transients.
  static const double _midAttack    = 0.40;
  static const double _midRelease   = 0.08;
  // Treble: slow shimmer — cymbals / hi-hats linger.
  static const double _trebleAttack  = 0.25;
  static const double _trebleRelease = 0.05;

  // ── Visual limits ─────────────────────────────────────────────────────────
  static const double _maxScale      = 1.06;  // artwork scale at full bass
  static const double _ringMaxRadius = 0.12;  // ring expansion as fraction of size
  static const double _haloMaxAlpha  = 0.45;  // outer halo max opacity

  // ── Latest raw bands from the FFT stream ─────────────────────────────────
  Float32List? _bands;
  bool _hasFft = false;
  StreamSubscription<dynamic>? _fftSub;

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_onTick);
    // Don't start the ticker until we have FFT data — saves battery when idle.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _fftSub?.cancel();
    final svc = ref.read(playerServiceProvider);
    _fftSub = svc.spectrumStream.listen((frame) {
      _bands = frame.bands;
      if (!_hasFft) {
        _hasFft = true;
        _ticker.repeat();
      }
    });
  }

  @override
  void dispose() {
    _fftSub?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  // ── Per-frame update ──────────────────────────────────────────────────────

  void _onTick() {
    if (!mounted) return;
    final bands = _bands;
    if (bands == null || bands.isEmpty) return;

    final n = bands.length; // 64

    // Bass: bands 0–7 (first 12.5 %)
    final bassEnd  = (n * 0.125).round().clamp(1, n);
    // Mid:  bands 8–31 (next 37.5 %)
    final midEnd   = (n * 0.50).round().clamp(bassEnd + 1, n);
    // Treble: bands 32–63 (remaining 50 %)

    final bassRms   = _rms(bands, 0, bassEnd);
    final midRms    = _rms(bands, bassEnd, midEnd);
    final trebleRms = _rms(bands, midEnd, n);

    // Apply a mild power curve so quiet passages don't saturate.
    final bassTarget   = math.pow(bassRms,   1.6).toDouble();
    final midTarget    = math.pow(midRms,    1.4).toDouble();
    final trebleTarget = math.pow(trebleRms, 1.2).toDouble();

    final newBass   = _lerp(_bass,   bassTarget,   bassTarget   > _bass   ? _bassAttack   : _bassRelease);
    final newMid    = _lerp(_mid,    midTarget,    midTarget    > _mid    ? _midAttack    : _midRelease);
    final newTreble = _lerp(_treble, trebleTarget, trebleTarget > _treble ? _trebleAttack : _trebleRelease);

    if ((newBass - _bass).abs() > 0.0005 ||
        (newMid - _mid).abs() > 0.0005 ||
        (newTreble - _treble).abs() > 0.0005) {
      setState(() {
        _bass   = newBass;
        _mid    = newMid;
        _treble = newTreble;
      });
    }
  }

  static double _rms(Float32List b, int start, int end) {
    var sum = 0.0;
    for (var i = start; i < end; i++) {
      sum += b[i] * b[i];
    }
    return math.sqrt(sum / (end - start)).clamp(0.0, 1.0);
  }

  static double _lerp(double current, double target, double t) =>
      current + (target - current) * t;

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scale = 1.0 + _bass * (_maxScale - 1.0);
    final ringRadius = widget.size / 2 + _mid * widget.size * _ringMaxRadius;
    final haloAlpha = _treble * _haloMaxAlpha;
    final spectral = ref.watch(currentSpectralProvider);

    // Outer halo + mid ring are painted behind the artwork via CustomPaint.
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: CustomPaint(
        painter: _LayersPainter(
          size: widget.size,
          ringRadius: ringRadius,
          ringAlpha: _mid,
          haloAlpha: haloAlpha,
          energy: spectral.energy,
          glow: spectral.glow,
        ),
        child: Transform.scale(
          scale: scale,
          child: Artwork(
            url: widget.imageUrl,
            size: widget.size,
            radius: widget.radius,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _LayersPainter — draws mid ring + treble halo behind the artwork
// ─────────────────────────────────────────────────────────────────────────────

class _LayersPainter extends CustomPainter {
  final double size;
  final double ringRadius;
  final double ringAlpha;
  final double haloAlpha;
  final Color energy;
  final Color glow;

  const _LayersPainter({
    required this.size,
    required this.ringRadius,
    required this.ringAlpha,
    required this.haloAlpha,
    required this.energy,
    required this.glow,
  });

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final center = Offset(canvasSize.width / 2, canvasSize.height / 2);

    // ── Outer halo (treble) ───────────────────────────────────────────────
    if (haloAlpha > 0.005) {
      final haloRadius = size * 0.62;
      final haloPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            glow.withValues(alpha: haloAlpha),
            glow.withValues(alpha: haloAlpha * 0.4),
            glow.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: haloRadius))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, haloRadius * 0.35);
      canvas.drawCircle(center, haloRadius, haloPaint);
    }

    // ── Mid ring ──────────────────────────────────────────────────────────
    if (ringAlpha > 0.01) {
      final ringPaint = Paint()
        ..color = energy.withValues(alpha: ringAlpha * 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, ringAlpha * 3.0)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, ringAlpha * 6.0);
      canvas.drawCircle(center, ringRadius, ringPaint);
    }
  }

  @override
  bool shouldRepaint(_LayersPainter old) =>
      old.ringRadius != ringRadius ||
      old.ringAlpha  != ringAlpha  ||
      old.haloAlpha  != haloAlpha  ||
      old.energy     != energy     ||
      old.glow       != glow;
}
