import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show FftFrame;

import '../state/providers.dart';
import 'artwork.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BeatPulseArtwork — distributed perceptual spectral field
//
// Architecture
// ────────────
// The artwork is the center anchor. Around it: a circular spectral field
// of independent emitters, one per perceptual frequency band.
//
// Signal pipeline:
//
//   Layer 1 — Raw FFT truth (64 bins, never globally smoothed)
//
//   Layer 2 — Spectral redistribution
//     64 FFT bins → 32 perceptual bands via logarithmic (mel-inspired) mapping.
//     Low frequencies get more visual bands (perceptually wider).
//     Each band extracts BOTH sustained energy AND transient impulse.
//     Dual-envelope per band: fast - slow = impulse.
//
//   Layer 3 — Independent emitters (32 bands)
//     Each emitter owns:
//       • fixed angle (log-spaced, asymmetrically seeded)
//       • sustained energy (slow envelope, frequency-dependent decay)
//       • transient impulse (fast-decay channel, amplified 3.2×)
//       • micro-jitter (per-emitter noise, frequency-dependent speed)
//       • width multiplier (bass wide, treble thin)
//     No shared state. No global coherence.
//
//   Layer 4 — Asymmetric spatial renderer
//     Per-emitter:
//       • spike body: sustained energy × maxSpike × widthMul
//       • transient tip: impulse × maxSpike × 0.9 (extends beyond body)
//       • color: bass→mid→treble color gradient (not uniform)
//       • glow pass: wide blurred stroke, low opacity
//       • sharp pass: crisp stroke, full opacity
//       • tip dot: bright point at spike tip for transient punch
//       • opacity: energy-driven (low-energy emitters fade out)
//
// Perceptual result:
//   • Kick drum → bass emitters (bottom arc) spike wide and heavy
//   • Hi-hat → treble emitters (top arc) flicker thin and fast
//   • Chord → mid emitters light up in a cluster
//   • Silence → all emitters decay to minimum independently
//   The eye sees localized activity in distinct arc regions, not one pulse.
// ─────────────────────────────────────────────────────────────────────────────

/// Number of perceptual bands (emitters) around the artwork.
const _kBandCount = 32;

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
  late final AnimationController _ticker;
  late final _SpectralField _field;
  StreamSubscription<FftFrame>? _fftSub;
  bool _hasRecentFft = false;

  @override
  void initState() {
    super.initState();
    _field = _SpectralField();
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
      _field.ingest(frame.bands);
      _hasRecentFft = true;
      if (!_ticker.isAnimating) _ticker.repeat();
    });
  }

  @override
  void dispose() {
    _fftSub?.cancel();
    _ticker.dispose();
    _field.dispose();
    super.dispose();
  }

  void _onTick() {
    if (!mounted) return;
    final moving = _field.tick();
    if (!moving && !_hasRecentFft) _ticker.stop();
    _hasRecentFft = false;
  }

  @override
  Widget build(BuildContext context) {
    final spectral = ref.watch(currentSpectralProvider);
    // Canvas is larger than artwork to give spikes room.
    final canvasSize = widget.size + _SpectralFieldPainter.maxSpike * 2 + 16;
    return RepaintBoundary(
      child: SizedBox(
        width: canvasSize,
        height: canvasSize,
        child: AnimatedBuilder(
          animation: _field,
          builder: (context, child) => CustomPaint(
            painter: _SpectralFieldPainter(
              field: _field,
              artworkSize: widget.size,
              energy: spectral.energy,
              glow: spectral.glow,
              shadow: spectral.shadow,
            ),
            child: child,
          ),
          child: Center(
            child: Hero(
              tag: 'now-playing-artwork',
              child: Artwork(
                url: widget.imageUrl,
                size: widget.size,
                radius: widget.radius,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SpectralField — Layer 2 + 3: redistribution + independent emitters
//
// Key design decisions:
//
// 1. ASYMMETRIC ANGLE SEEDING
//    Bands are NOT evenly spaced. Each band gets a small random angular
//    offset at construction time (seeded deterministically). This breaks
//    the "perfect circle" topology — the field looks like a living organism,
//    not a UI widget.
//
// 2. FREQUENCY-DEPENDENT SPIKE WIDTH
//    Bass emitters are wider (spectral weight is perceptually wide).
//    Treble emitters are thinner (hi-hats are point sources).
//    Width is encoded in _widthMul[b] and passed to the painter.
//
// 3. DUAL-ENVELOPE TRANSIENT DETECTION PER BAND
//    fast[b] tracks instantaneous energy (lerp 0.55–0.90).
//    slow[b] tracks sustained baseline (lerp 0.04–0.12).
//    impulse = max(0, fast - slow) = the "new energy" this frame.
//    Transient is amplified 3.2× — individual hits punch through.
//
// 4. ENERGY-DRIVEN OPACITY
//    spikeAlpha() returns near-zero for silent bands.
//    This creates visible "holes" in the spectrum during silence,
//    making active regions pop by contrast.
// ─────────────────────────────────────────────────────────────────────────────

class _SpectralField extends ChangeNotifier {
  static const int _fftBins = 64;
  static const int _bands   = _kBandCount; // 32

  // ── Per-band state ────────────────────────────────────────────────────────
  final Float32List _energy    = Float32List(_bands); // sustained energy
  final Float32List _transient = Float32List(_bands); // impulse channel
  final Float32List _slow      = Float32List(_bands); // slow baseline
  final Float32List _fast      = Float32List(_bands); // fast tracker
  final Float32List _jitter    = Float32List(_bands); // angle micro-jitter
  final Float32List _jitterV   = Float32List(_bands); // jitter velocity

  // ── Per-band envelope parameters ─────────────────────────────────────────
  final Float32List _attack    = Float32List(_bands);
  final Float32List _decay     = Float32List(_bands);
  final Float32List _tDecay    = Float32List(_bands);
  final Float32List _fastLerp  = Float32List(_bands);
  final Float32List _slowLerp  = Float32List(_bands);

  // ── Per-band geometry ─────────────────────────────────────────────────────
  // Width multiplier: bass wide (1.8), treble thin (0.5).
  final Float32List _widthMul  = Float32List(_bands);
  // Asymmetric angular offset seeded at construction.
  final Float32List _angleOffset = Float32List(_bands);

  // ── Logarithmic bin mapping ───────────────────────────────────────────────
  late final List<(int, int)> _binRanges;

  static const double _settleThresh = 0.0005;

  final _rng = math.Random(7); // deterministic seed for stable geometry

  _SpectralField() {
    _buildLogMapping();
    _buildEnvelopes();
    for (var i = 0; i < _bands; i++) {
      // Jitter phase: random start so emitters are incoherent from frame 1.
      _jitter[i] = _rng.nextDouble() * 2 * math.pi;
      // Jitter velocity: treble faster (hi-hat shimmer), bass slower.
      final t = i / (_bands - 1);
      final jSpeed = 0.012 + t * 0.048;
      _jitterV[i] = jSpeed * (_rng.nextBool() ? 1 : -1);

      // Asymmetric angle offset: small random perturbation per emitter.
      // This breaks the perfect-circle topology.
      // Bass emitters get larger offsets (bass is spatially diffuse).
      // Treble emitters get smaller offsets (hi-hats are point sources).
      final maxOffset = (0.08 - t * 0.05).clamp(0.03, 0.08);
      _angleOffset[i] = (_rng.nextDouble() * 2 - 1) * maxOffset;

      // Width multiplier: bass wide, treble thin.
      _widthMul[i] = (1.8 - t * 1.3).clamp(0.5, 1.8);
    }
  }

  void _buildLogMapping() {
    final ranges = <(int, int)>[];
    int prev = 0;
    for (var b = 0; b < _bands; b++) {
      final t    = (b + 1) / _bands;
      final binF = _fftBins * (math.exp(t * math.log(_fftBins + 1)) - 1) / _fftBins;
      final end  = binF.round().clamp(prev + 1, _fftBins);
      ranges.add((prev, end));
      prev = end;
    }
    _binRanges = ranges;
  }

  void _buildEnvelopes() {
    for (var i = 0; i < _bands; i++) {
      final t = i / (_bands - 1); // 0=bass, 1=treble
      _attack[i]   = (0.55 + t * 0.35).clamp(0.55, 0.90);
      _decay[i]    = (0.04 + t * 0.28).clamp(0.04, 0.32);
      _tDecay[i]   = (0.16 + t * 0.48).clamp(0.16, 0.64);
      _fastLerp[i] = (0.55 + t * 0.35).clamp(0.55, 0.90);
      _slowLerp[i] = (0.04 + t * 0.08).clamp(0.04, 0.12);
    }
  }

  /// Layer 2: ingest raw FFT, redistribute into perceptual bands.
  void ingest(Float32List bands) {
    for (var b = 0; b < _bands; b++) {
      final (start, end) = _binRanges[b];
      // RMS over the bin range for this perceptual band.
      var sum = 0.0;
      var count = 0;
      for (var k = start; k < end && k < bands.length; k++) {
        final v = bands[k];
        if (v.isFinite) {
          sum += v * v;
          count++;
        }
      }
      final rms = count > 0 ? math.sqrt(sum / count).clamp(0.0, 1.0) : 0.0;

      // Psychoacoustic amplitude weighting.
      // Bass: sqrt curve + amplification (perceptually louder, spatially wide).
      // Treble: linear attenuation (prevent harsh spikes).
      final t = b / (_bands - 1);
      final double weighted;
      if (b < 4) {
        // Sub-bass: strong sqrt boost.
        weighted = (math.sqrt(rms) * 1.9).clamp(0.0, 1.0);
      } else if (b < 10) {
        // Bass: moderate boost.
        weighted = (rms * 1.6).clamp(0.0, 1.0);
      } else if (b < 20) {
        // Mid: neutral.
        weighted = rms;
      } else {
        // Treble: attenuate but preserve transient punch.
        weighted = (rms * (1.0 - t * 0.35)).clamp(0.0, 1.0);
      }

      // Dual-envelope transient detection.
      _fast[b] += (weighted - _fast[b]) * _fastLerp[b];
      _slow[b] += (weighted - _slow[b]) * _slowLerp[b];
      final impulse = math.max(0.0, _fast[b] - _slow[b]);

      // Transient: amplify impulse strongly. Individual hits punch through.
      final tTarget = (impulse * 3.2).clamp(0.0, 1.0);
      if (tTarget > _transient[b]) _transient[b] = tTarget; // instant attack

      // Sustained energy: attack/decay envelope.
      if (weighted > _energy[b]) {
        _energy[b] += (weighted - _energy[b]) * _attack[b];
      }
    }
  }

  /// Layer 3: advance all emitters one frame.
  bool tick() {
    var anyMoving = false;

    for (var b = 0; b < _bands; b++) {
      // Sustained energy decay.
      final eNext = _energy[b] * (1.0 - _decay[b]);
      if ((_energy[b] - eNext).abs() > _settleThresh) anyMoving = true;
      _energy[b] = eNext;

      // Transient decay (faster than sustained).
      final tNext = _transient[b] * (1.0 - _tDecay[b]);
      if ((_transient[b] - tNext).abs() > _settleThresh) anyMoving = true;
      _transient[b] = tNext;

      // Micro-jitter: each emitter oscillates in angle independently.
      _jitter[b] += _jitterV[b];
      // Slowly drift jitter velocity for long-term variation.
      _jitterV[b] += (_rng.nextDouble() - 0.5) * 0.0025;
      final t = b / (_bands - 1);
      final maxV = 0.012 + t * 0.048;
      _jitterV[b] = _jitterV[b].clamp(-maxV, maxV);
    }

    notifyListeners();
    return anyMoving;
  }

  /// Spike body length for band [b].
  double spikeLength(int b, double maxSpike) {
    final base = _energy[b] * maxSpike * 0.65;
    final tip  = _transient[b] * maxSpike * 0.95;
    return (base + tip).clamp(1.0, maxSpike);
  }

  /// Spike opacity for band [b]: energy-driven, fades to near-zero in silence.
  double spikeAlpha(int b) {
    final e = _energy[b];
    final tr = _transient[b];
    // Low-energy bands fade out — creates visible spectral holes.
    return (0.08 + (e * 0.7 + tr * 1.2) * 0.92).clamp(0.0, 1.0);
  }

  /// Angle for band [b] with asymmetric offset + micro-jitter.
  double angle(int b) {
    // Start at top (-π/2), distribute bands around circle.
    final base = -math.pi / 2 + (b / _bands) * 2 * math.pi;
    // Asymmetric offset (fixed per emitter) + dynamic micro-jitter.
    return base + _angleOffset[b] + _jitter[b] * 0.035;
  }

  /// Width multiplier for band [b]: bass wide, treble thin.
  double widthMul(int b) => _widthMul[b];
}

// ─────────────────────────────────────────────────────────────────────────────
// _SpectralFieldPainter — Layer 4: asymmetric spatial renderer
//
// Key departures from the old uniform spike renderer:
//
// 1. FREQUENCY-DEPENDENT SPIKE WIDTH
//    Bass spikes are wider (spectral weight is perceptually wide).
//    Treble spikes are thinner (hi-hats are point sources).
//    Width = spikeWidth * field.widthMul(b).
//
// 2. SEPARATE BODY + TIP RENDERING
//    Body: sustained energy length, full opacity.
//    Tip: transient impulse extension, brighter color, wider dot.
//    The tip is rendered as a separate line segment beyond the body.
//    This makes individual hits visually distinct from sustained energy.
//
// 3. THREE-COLOR GRADIENT (not two)
//    bass → mid → treble uses three color stops:
//      shadow (bass) → energy (mid) → glow (treble)
//    This gives each frequency region a distinct visual identity.
//
// 4. ENERGY-DRIVEN OPACITY
//    Silent bands fade to near-zero opacity.
//    Active bands are fully opaque.
//    This creates visible spectral holes during silence.
//
// 5. NO UNIFORM GLOW BLUR on every spike
//    Glow is only applied to high-energy spikes (energy > 0.3).
//    This prevents the "everything glows equally" look.
//    Transient tips always get a glow dot for punch readability.
// ─────────────────────────────────────────────────────────────────────────────

class _SpectralFieldPainter extends CustomPainter {
  final _SpectralField field;
  final double artworkSize;
  final Color energy;
  final Color glow;
  final Color shadow;

  // Maximum spike length (body + tip combined).
  static const double maxSpike   = 40.0;
  // Gap between artwork edge and spike base.
  static const double spikeGap   = 6.0;
  // Base spike stroke width (scaled by widthMul per band).
  static const double spikeWidth = 1.8;
  // Energy threshold above which glow blur is applied.
  static const double _glowThresh = 0.30;

  const _SpectralFieldPainter({
    required this.field,
    required this.artworkSize,
    required this.energy,
    required this.glow,
    required this.shadow,
  }) : super(repaint: field);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final innerR = artworkSize / 2 + spikeGap;

    for (var b = 0; b < _kBandCount; b++) {
      final alpha  = field.spikeAlpha(b);
      if (alpha < 0.04) continue; // skip silent bands entirely

      final ang    = field.angle(b);
      final wMul   = field.widthMul(b);
      final eLevel = field._energy[b];
      final tLevel = field._transient[b];

      // Body length: sustained energy only.
      final bodyLen = (eLevel * maxSpike * 0.65).clamp(0.0, maxSpike * 0.75);
      // Tip length: transient impulse only (extends beyond body).
      final tipLen  = (tLevel * maxSpike * 0.90).clamp(0.0, maxSpike * 0.50);

      final cos = math.cos(ang);
      final sin = math.sin(ang);

      final pBase = Offset(center.dx + cos * innerR,
                           center.dy + sin * innerR);
      final pBodyEnd = Offset(center.dx + cos * (innerR + bodyLen),
                              center.dy + sin * (innerR + bodyLen));
      final pTipEnd  = Offset(center.dx + cos * (innerR + bodyLen + tipLen),
                              center.dy + sin * (innerR + bodyLen + tipLen));

      // Three-color gradient: shadow (bass) → energy (mid) → glow (treble).
      final t = b / (_kBandCount - 1);
      final Color spikeColor;
      if (t < 0.5) {
        spikeColor = Color.lerp(shadow, energy, t * 2)!;
      } else {
        spikeColor = Color.lerp(energy, glow, (t - 0.5) * 2)!;
      }

      final strokeW = spikeWidth * wMul;

      // ── Glow pass (only for high-energy spikes) ───────────────────────
      if (eLevel > _glowThresh && bodyLen > 2.0) {
        canvas.drawLine(
          pBase, pBodyEnd,
          Paint()
            ..color = spikeColor.withValues(alpha: alpha * 0.25)
            ..strokeWidth = strokeW * 2.8
            ..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5),
        );
      }

      // ── Body: sharp pass ──────────────────────────────────────────────
      if (bodyLen > 1.0) {
        canvas.drawLine(
          pBase, pBodyEnd,
          Paint()
            ..color = spikeColor.withValues(alpha: alpha)
            ..strokeWidth = strokeW
            ..strokeCap = StrokeCap.round,
        );
      }

      // ── Transient tip ─────────────────────────────────────────────────
      if (tLevel > 0.08 && tipLen > 1.0) {
        // Tip line: brighter, slightly thinner.
        final tipColor = Color.lerp(spikeColor, glow, 0.4)!
            .withValues(alpha: (alpha * tLevel * 1.3).clamp(0.0, 1.0));

        canvas.drawLine(
          pBodyEnd, pTipEnd,
          Paint()
            ..color = tipColor
            ..strokeWidth = strokeW * 0.75
            ..strokeCap = StrokeCap.round,
        );

        // Tip dot: bright point at spike tip for punch readability.
        final dotR = strokeW * (0.9 + tLevel * 1.4);
        // Glow halo around tip dot.
        canvas.drawCircle(
          pTipEnd,
          dotR * 2.2,
          Paint()
            ..color = tipColor.withValues(alpha: tLevel * 0.35)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0),
        );
        canvas.drawCircle(
          pTipEnd,
          dotR,
          Paint()
            ..color = tipColor
            ..style = PaintingStyle.fill,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_SpectralFieldPainter old) =>
      old.energy != energy ||
      old.glow   != glow   ||
      old.shadow != shadow ||
      old.artworkSize != artworkSize;
}
