import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show FftFrame;

import '../state/providers.dart';
import 'artwork.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BeatPulseArtwork — circular spectrum analyzer around album artwork
//
// Architecture
// ────────────
// Each of the 64 FFT bins controls its own radial spike positioned around
// the artwork at angle (i / 64) * 2π. Spikes are independent — bin 0 is
// bass at the bottom-left, bin 32 is treble at the top-right. The eye
// perceives distributed spectral motion, not a single scaling object.
//
// Per-bin envelope:
//   • Bass bins (0–7):    slow attack, very slow decay — kick drums sustain
//   • Low-mid (8–15):     medium
//   • Mid (16–31):        neutral
//   • Treble (32–63):     fast attack, fast decay — hi-hats flicker
//
// Psychoacoustic amplitude weighting per region matches the waveform widget.
//
// No uniform Transform.scale — that always reads as one object.
// No global ring radius — that always reads as one oscillator.
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
  late final AnimationController _ticker;
  late final _SpectrumNotifier _notifier;
  StreamSubscription<FftFrame>? _fftSub;
  bool _hasRecentFft = false;

  @override
  void initState() {
    super.initState();
    _notifier = _SpectrumNotifier();
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
      _notifier._updateTarget(frame.bands);
      _hasRecentFft = true;
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
    final changed = _notifier._tick();
    if (!changed && !_hasRecentFft) _ticker.stop();
    _hasRecentFft = false;
  }

  @override
  Widget build(BuildContext context) {
    final spectral = ref.watch(currentSpectralProvider);
    // Outer SizedBox is slightly larger than artwork to give spikes room.
    final outerSize = widget.size + _SpectrumPainter.maxSpikeLength * 2;
    return SizedBox(
      width: outerSize,
      height: outerSize,
      child: AnimatedBuilder(
        animation: _notifier,
        builder: (context, child) => CustomPaint(
          painter: _SpectrumPainter(
            notifier: _notifier,
            artworkSize: widget.size,
            energy: spectral.energy,
            glow: spectral.glow,
          ),
          child: child,
        ),
        child: Center(
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
// _SpectrumNotifier — 64 independent per-bin envelopes
// ─────────────────────────────────────────────────────────────────────────────

class _SpectrumNotifier extends ChangeNotifier {
  static const int _binCount = 64;

  // Per-bin visual heights [0, 1] — mutated in-place each tick.
  final Float32List bins = Float32List(_binCount);

  // Per-bin attack/decay — pre-computed by frequency region.
  final Float32List _attack = Float32List(_binCount);
  final Float32List _decay  = Float32List(_binCount);

  // Raw FFT target — written by stream, read by tick.
  Float32List? _fftTarget;

  static const double _settleThresh = 0.0008;
  static const double _minHeight    = 0.0;

  // Frequency region boundaries (same as waveform widget).
  static const int _bassEnd   = 8;
  static const int _lowMidEnd = 16;
  static const int _midEnd    = 32;

  _SpectrumNotifier() {
    for (var i = 0; i < _binCount; i++) {
      if (i < _bassEnd) {
        _attack[i] = 0.65;
        _decay[i]  = 0.06; // very slow — bass sustains
      } else if (i < _lowMidEnd) {
        _attack[i] = 0.72;
        _decay[i]  = 0.12;
      } else if (i < _midEnd) {
        _attack[i] = 0.78;
        _decay[i]  = 0.20;
      } else {
        _attack[i] = 0.90; // treble: instant snap
        _decay[i]  = 0.35; // treble: fast flicker
      }
    }
  }

  void _updateTarget(Float32List bands) {
    _fftTarget = bands;
  }

  bool _tick() {
    final bands = _fftTarget;
    if (bands == null) return false;

    var anyMoving = false;
    for (var i = 0; i < _binCount; i++) {
      final raw = i < bands.length ? bands[i] : 0.0;
      final safeRaw = raw.isFinite ? raw.clamp(0.0, 1.0) : 0.0;

      // Psychoacoustic amplitude weighting — same as waveform.
      final double weighted;
      if (i < _bassEnd) {
        weighted = (safeRaw * 1.8).clamp(0.0, 1.0); // bass amplified more for spikes
      } else if (i < _lowMidEnd) {
        weighted = (safeRaw * 1.3).clamp(0.0, 1.0);
      } else if (i < _midEnd) {
        weighted = safeRaw;
      } else {
        weighted = (safeRaw * 0.80).clamp(0.0, 1.0);
      }

      final target = weighted.clamp(_minHeight, 1.0);
      final lerp   = target > bins[i] ? _attack[i] : _decay[i];
      final next   = bins[i] + (target - bins[i]) * lerp;
      if ((next - bins[i]).abs() > _settleThresh) anyMoving = true;
      bins[i] = next;
    }

    notifyListeners();
    return anyMoving;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SpectrumPainter — draws 64 radial spikes around the artwork
// ─────────────────────────────────────────────────────────────────────────────

class _SpectrumPainter extends CustomPainter {
  final _SpectrumNotifier notifier;
  final double artworkSize;
  final Color energy;
  final Color glow;

  // Maximum radial extension of a spike at full energy.
  static const double maxSpikeLength = 28.0;
  // Minimum spike length so the ring is always visible.
  static const double minSpikeLength = 2.0;
  // Gap between artwork edge and spike base.
  static const double spikeGap = 4.0;
  // Spike width at base.
  static const double spikeWidth = 2.5;

  const _SpectrumPainter({
    required this.notifier,
    required this.artworkSize,
    required this.energy,
    required this.glow,
  }) : super(repaint: notifier);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final innerRadius = artworkSize / 2 + spikeGap;
    final bins = notifier.bins;
    final n = bins.length;

    for (var i = 0; i < n; i++) {
      final amp = bins[i];
      if (amp < 0.01) continue; // skip invisible spikes

      // Angle: distribute bins evenly around the circle.
      // Start at top (-π/2) so bass (bin 0) is at the top.
      final angle = -math.pi / 2 + (i / n) * 2 * math.pi;
      final cos = math.cos(angle);
      final sin = math.sin(angle);

      final spikeLen = minSpikeLength + amp * (maxSpikeLength - minSpikeLength);
      final outerRadius = innerRadius + spikeLen;

      final p1 = Offset(
        center.dx + cos * innerRadius,
        center.dy + sin * innerRadius,
      );
      final p2 = Offset(
        center.dx + cos * outerRadius,
        center.dy + sin * outerRadius,
      );

      // Color: bass bins use energy color, treble bins use glow color.
      // Interpolate between them across the spectrum.
      final t = i / (n - 1);
      final spikeColor = Color.lerp(energy, glow, t)!
          .withValues(alpha: (0.4 + amp * 0.6).clamp(0.0, 1.0));

      // Glow pass (wider, blurred).
      canvas.drawLine(
        p1,
        p2,
        Paint()
          ..color = spikeColor.withValues(alpha: amp * 0.35)
          ..strokeWidth = spikeWidth * 2.5
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0),
      );

      // Sharp pass.
      canvas.drawLine(
        p1,
        p2,
        Paint()
          ..color = spikeColor
          ..strokeWidth = spikeWidth
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_SpectrumPainter old) =>
      old.energy != energy || old.glow != glow || old.artworkSize != artworkSize;
  // Value changes handled by repaint: notifier.
}
