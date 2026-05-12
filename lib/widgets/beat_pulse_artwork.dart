import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show FftFrame;

import '../state/providers.dart';
import 'artwork.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BeatPulseArtwork — circular spectral field
//
// Architecture
// ────────────
// The artwork is the center anchor. Around it: a circular spectral field
// of independent emitters, one per perceptual frequency band.
//
// Signal pipeline (signal-inward, not UI-outward):
//
//   Layer 1 — Raw FFT truth (64 bins, never globally smoothed)
//
//   Layer 2 — Spectral redistribution
//     64 FFT bins → 32 perceptual bands via logarithmic remapping.
//     Low frequencies get more visual bands (perceptually wider).
//     High frequencies get fewer (perceptually compressed).
//     Each band extracts BOTH energy AND transient (delta from slow envelope).
//
//   Layer 3 — Independent emitters
//     Each of the 32 bands owns:
//       • angle (fixed, log-spaced around circle)
//       • current spike length (independent attack/decay)
//       • transient impulse (separate fast-decay channel)
//       • micro-jitter (per-emitter noise for organic feel)
//     No shared state. No global coherence.
//
//   Layer 4 — Spatial renderer
//     Radial spikes with:
//       • base length from sustained energy
//       • tip extension from transient impulse
//       • color interpolated by frequency position
//       • glow pass + sharp pass per spike
//       • micro-jitter in angle for organic asymmetry
//
// Why this works perceptually:
//   • Kick drum → bass emitters spike independently, others unaffected
//   • Hi-hat → treble emitters flicker, bass stays calm
//   • Chord → mid emitters light up in a cluster
//   • Silence → all emitters decay to minimum independently
//   The eye sees localized activity, not one breathing object.
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
// ─────────────────────────────────────────────────────────────────────────────

class _SpectralField extends ChangeNotifier {
  static const int _fftBins  = 64;
  static const int _bands    = _kBandCount;

  // ── Per-band state ────────────────────────────────────────────────────────
  // Sustained energy (slow envelope).
  final Float32List _energy    = Float32List(_bands);
  // Transient impulse (fast envelope, separate decay).
  final Float32List _transient = Float32List(_bands);
  // Slow envelope for transient detection (per-band baseline).
  final Float32List _slow      = Float32List(_bands);
  // Fast envelope for transient detection.
  final Float32List _fast      = Float32List(_bands);
  // Per-band micro-jitter phase (organic asymmetry).
  final Float32List _jitter    = Float32List(_bands);
  // Per-band jitter velocity.
  final Float32List _jitterV   = Float32List(_bands);

  // ── Per-band envelope parameters ─────────────────────────────────────────
  final Float32List _attack    = Float32List(_bands);
  final Float32List _decay     = Float32List(_bands);
  final Float32List _tDecay    = Float32List(_bands); // transient decay

  // ── Logarithmic bin mapping ───────────────────────────────────────────────
  // Maps each perceptual band to a range of FFT bins.
  // Low bands cover fewer bins (bass is spectrally dense).
  // High bands cover more bins (treble is spectrally sparse in perception).
  late final List<(int, int)> _binRanges; // (startBin, endBin) per band

  static const double _settleThresh = 0.0006;

  final _rng = math.Random();

  _SpectralField() {
    _buildLogMapping();
    _buildEnvelopes();
    // Seed jitter phases randomly so emitters start at different positions.
    for (var i = 0; i < _bands; i++) {
      _jitter[i] = _rng.nextDouble() * 2 * math.pi;
      _jitterV[i] = (0.02 + _rng.nextDouble() * 0.04) *
          (_rng.nextBool() ? 1 : -1);
    }
  }

  /// Build logarithmic frequency-to-band mapping.
  /// Band 0 = lowest perceptual frequency, band 31 = highest.
  /// Uses mel-scale-inspired spacing: more bands for bass, fewer for treble.
  void _buildLogMapping() {
    // Map _bands perceptual bands across _fftBins using log spacing.
    // f(i) = fftBins * (exp(i / bands * ln(fftBins+1)) - 1) / fftBins
    final ranges = <(int, int)>[];
    int prev = 0;
    for (var b = 0; b < _bands; b++) {
      final t = (b + 1) / _bands;
      final binF = _fftBins * (math.exp(t * math.log(_fftBins + 1)) - 1) / _fftBins;
      final end = binF.round().clamp(prev + 1, _fftBins);
      ranges.add((prev, end));
      prev = end;
    }
    _binRanges = ranges;
  }

  void _buildEnvelopes() {
    for (var i = 0; i < _bands; i++) {
      final t = i / (_bands - 1); // 0 = bass, 1 = treble
      // Bass: slow attack, very slow decay (sustain).
      // Treble: fast attack, fast decay (flicker).
      _attack[i]  = (0.55 + t * 0.35).clamp(0.55, 0.90);
      _decay[i]   = (0.05 + t * 0.30).clamp(0.05, 0.35);
      _tDecay[i]  = (0.15 + t * 0.50).clamp(0.15, 0.65); // transient decays faster
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
      // Bass amplified (perceptually louder), treble attenuated.
      final t = b / (_bands - 1);
      final weight = 1.8 - t * 1.0; // 1.8 at bass, 0.8 at treble
      final weighted = (rms * weight).clamp(0.0, 1.0);

      // Dual-envelope transient detector per band.
      _fast[b] += (weighted - _fast[b]) * 0.60;
      _slow[b] += (weighted - _slow[b]) * 0.08;
      final impulse = math.max(0.0, _fast[b] - _slow[b]);

      // Transient target: impulse amplified strongly.
      // This is what makes individual hits punch.
      final tTarget = (impulse * 3.5).clamp(0.0, 1.0);
      // Only update transient upward (attack); decay handled in tick().
      if (tTarget > _transient[b]) _transient[b] = tTarget;

      // Energy target: sustained level.
      if (weighted > _energy[b]) {
        _energy[b] += (weighted - _energy[b]) * _attack[b];
      }
    }
  }

  /// Layer 3: advance all emitters one frame.
  bool tick() {
    var anyMoving = false;

    for (var b = 0; b < _bands; b++) {
      // Energy decay.
      final eNext = _energy[b] * (1.0 - _decay[b]);
      if ((_energy[b] - eNext).abs() > _settleThresh) anyMoving = true;
      _energy[b] = eNext;

      // Transient decay (faster than energy).
      final tNext = _transient[b] * (1.0 - _tDecay[b]);
      if ((_transient[b] - tNext).abs() > _settleThresh) anyMoving = true;
      _transient[b] = tNext;

      // Micro-jitter: each emitter oscillates slightly in angle.
      // Creates organic asymmetry — emitters don't all point the same way.
      _jitter[b] += _jitterV[b];
      // Slowly drift jitter velocity for long-term variation.
      _jitterV[b] += (_rng.nextDouble() - 0.5) * 0.002;
      _jitterV[b] = _jitterV[b].clamp(-0.06, 0.06);
    }

    notifyListeners();
    return anyMoving;
  }

  /// Spike length for band [b]: sustained energy + transient tip.
  double spikeLength(int b, double maxSpike) {
    final base = _energy[b] * maxSpike * 0.6;
    final tip  = _transient[b] * maxSpike * 0.9;
    return (base + tip).clamp(1.0, maxSpike);
  }

  /// Spike opacity for band [b].
  double spikeAlpha(int b) =>
      (0.15 + (_energy[b] + _transient[b] * 1.5) * 0.85).clamp(0.0, 1.0);

  /// Angle for band [b] with micro-jitter.
  double angle(int b) {
    // Start at top (-π/2), distribute bands around circle.
    final base = -math.pi / 2 + (b / _bands) * 2 * math.pi;
    return base + _jitter[b] * 0.04; // small jitter in radians
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SpectralFieldPainter — Layer 4: spatial renderer
// ─────────────────────────────────────────────────────────────────────────────

class _SpectralFieldPainter extends CustomPainter {
  final _SpectralField field;
  final double artworkSize;
  final Color energy;
  final Color glow;
  final Color shadow;

  static const double maxSpike   = 36.0;
  static const double spikeGap   = 5.0;  // gap between artwork edge and spike base
  static const double spikeWidth = 2.2;

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
      final len   = field.spikeLength(b, maxSpike);
      final alpha = field.spikeAlpha(b);
      final ang   = field.angle(b);

      if (len < 1.5 || alpha < 0.05) continue;

      final cos = math.cos(ang);
      final sin = math.sin(ang);

      final p1 = Offset(center.dx + cos * innerR,
                        center.dy + sin * innerR);
      final p2 = Offset(center.dx + cos * (innerR + len),
                        center.dy + sin * (innerR + len));

      // Color: interpolate energy→glow across frequency (bass→treble).
      final t = b / (_kBandCount - 1);
      final spikeColor = Color.lerp(energy, glow, t)!
          .withValues(alpha: alpha);

      // Glow pass — wide, blurred, lower opacity.
      canvas.drawLine(
        p1, p2,
        Paint()
          ..color = spikeColor.withValues(alpha: alpha * 0.30)
          ..strokeWidth = spikeWidth * 3.0
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0),
      );

      // Sharp pass — crisp, full opacity.
      canvas.drawLine(
        p1, p2,
        Paint()
          ..color = spikeColor
          ..strokeWidth = spikeWidth
          ..strokeCap = StrokeCap.round,
      );

      // Transient tip dot — extra bright point at spike tip for punch.
      final tAmp = field._transient[b];
      if (tAmp > 0.1) {
        canvas.drawCircle(
          p2,
          spikeWidth * (0.8 + tAmp * 1.2),
          Paint()
            ..color = spikeColor.withValues(alpha: tAmp * 0.9)
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
