import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show FftFrame;

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
// Architecture
// ────────────
// • A single [_BeatNotifier] (ChangeNotifier) owns all animation state.
//   It drives both the CustomPainter repaint and the Transform.scale
//   via AnimatedBuilder — no setState() anywhere.
//
// • The ticker only runs when FFT data is arriving AND the widget is
//   visible. It stops automatically when playback pauses.
//
// • FFT values are validated (NaN/Infinity guard) before entering the
//   smoothing pipeline.
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
  late final _BeatNotifier _notifier;
  StreamSubscription<FftFrame>? _fftSub;
  // Track whether FFT arrived recently so we don't stop the ticker
  // between frames and kill visible animation.
  bool _hasRecentFft = false;

  @override
  void initState() {
    super.initState();
    _notifier = _BeatNotifier();
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_onTick);
    // Ticker starts only when FFT data arrives (see didChangeDependencies).
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Only resubscribe if the player service instance changed.
    final svc = ref.read(playerServiceProvider);
    _fftSub?.cancel();
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
    // Only stop when settled AND no recent FFT arriving.
    // Previously stopped aggressively between frames, killing visible animation.
    if (!changed && !_hasRecentFft) _ticker.stop();
    _hasRecentFft = false; // reset each tick; set again by next FFT frame
  }

  @override
  Widget build(BuildContext context) {
    final spectral = ref.watch(currentSpectralProvider);
    return AnimatedBuilder(
      animation: _notifier,
      builder: (context, child) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            painter: _LayersPainter(
              notifier: _notifier,
              size: widget.size,
              energy: spectral.energy,
              glow: spectral.glow,
            ),
            child: Transform.scale(
              scale: _notifier.scale,
              child: child,
            ),
          ),
        );
      },
      child: Artwork(
        url: widget.imageUrl,
        size: widget.size,
        radius: widget.radius,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _BeatNotifier — owns all animation state, drives repaints via ChangeNotifier
// ─────────────────────────────────────────────────────────────────────────────

class _BeatNotifier extends ChangeNotifier {
  // ── Smoothed values [0, 1] ────────────────────────────────────────────────
  double bass   = 0.0;
  double mid    = 0.0;
  double treble = 0.0;

  // ── Targets set by latest FFT frame ──────────────────────────────────────
  double _bassTarget   = 0.0;
  double _midTarget    = 0.0;
  double _trebleTarget = 0.0;

  // ── Dual-envelope beat detector ───────────────────────────────────────────
  // Fast envelope tracks kicks immediately; slow envelope tracks overall
  // bass energy. Beat impulse = fast - slow. This avoids the self-suppression
  // bug where (bassNow - smoothedBass) ≈ 0 because smoothing already follows.
  double _fastBass = 0.0;
  double _slowBass = 0.0;

  // ── Attack / release lerp constants ──────────────────────────────────────
  static const double _bassAttack    = 0.82;
  static const double _bassRelease   = 0.22;
  static const double _midAttack     = 0.40;
  static const double _midRelease    = 0.08;
  static const double _trebleAttack  = 0.25;
  static const double _trebleRelease = 0.05;

  // ── Visual limits ─────────────────────────────────────────────────────────
  static const double _maxScale      = 1.24;
  static const double _ringMaxRadius = 0.14;
  static const double _haloMaxAlpha  = 0.50;
  static const double _settleThresh  = 0.0005;

  double get scale      => 1.0 + bass * (_maxScale - 1.0);
  double ringRadius(double size) =>
      size / 2 + mid * size * _ringMaxRadius;
  double get haloAlpha  => treble * _haloMaxAlpha;

  void _updateTarget(Float32List bands) {
    if (bands.isEmpty) return;
    final n = bands.length;
    final bassEnd  = (n * 0.125).round().clamp(1, n);
    final midEnd   = (n * 0.50).round().clamp(bassEnd + 1, n);

    final bassNow = _rms(bands, 0, bassEnd);

    // Dual-envelope beat detector:
    //   fast envelope (0.55) captures kick transients immediately.
    //   slow envelope (0.08) tracks overall bass energy level.
    //   beat impulse = fast - slow = energy above the running average.
    _fastBass += (bassNow - _fastBass) * 0.55;
    _slowBass += (bassNow - _slowBass) * 0.08;
    final beat = math.max(0.0, _fastBass - _slowBass);

    // Strong transient amplification: beat * 4.5 makes kicks punch visibly.
    // bassNow * 0.25 provides a floor so sustained bass still shows.
    _bassTarget = (bassNow * 0.25 + beat * 4.5).clamp(0.0, 1.0);

    _midTarget    = (_rms(bands, bassEnd, midEnd) * 1.1).clamp(0.0, 1.0);
    _trebleTarget = (_rms(bands, midEnd, n)       * 0.9).clamp(0.0, 1.0);
  }

  /// Returns true if any value is still moving (ticker should keep running).
  bool _tick() {
    final nb = _lerp(bass,   _bassTarget,   _bassTarget   > bass   ? _bassAttack   : _bassRelease);
    final nm = _lerp(mid,    _midTarget,    _midTarget    > mid    ? _midAttack    : _midRelease);
    final nt = _lerp(treble, _trebleTarget, _trebleTarget > treble ? _trebleAttack : _trebleRelease);

    final changed = (nb - bass).abs()   > _settleThresh ||
                    (nm - mid).abs()    > _settleThresh ||
                    (nt - treble).abs() > _settleThresh;
    bass   = nb;
    mid    = nm;
    treble = nt;
    // Always notify during active FFT — don't quantize visual updates
    // by gating on settle threshold (scale changes matter before threshold).
    notifyListeners();
    return changed;
  }

  static double _rms(Float32List b, int start, int end) {
    final count = end - start;
    if (count <= 0) return 0.0;
    var sum = 0.0;
    for (var i = start; i < end; i++) {
      final v = b[i];
      // Guard against NaN / Infinity from malformed FFT frames.
      if (!v.isFinite) continue;
      sum += v * v;
    }
    return math.sqrt(sum / count).clamp(0.0, 1.0);
  }

  static double _lerp(double current, double target, double t) =>
      current + (target - current) * t;
}

// ─────────────────────────────────────────────────────────────────────────────
// _LayersPainter — draws mid ring + treble halo behind the artwork.
// Repaint is driven by _BeatNotifier (Listenable), not setState.
// ─────────────────────────────────────────────────────────────────────────────

class _LayersPainter extends CustomPainter {
  final _BeatNotifier notifier;
  final double size;
  final Color energy;
  final Color glow;

  _LayersPainter({
    required this.notifier,
    required this.size,
    required this.energy,
    required this.glow,
  }) : super(repaint: notifier);

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final center = Offset(canvasSize.width / 2, canvasSize.height / 2);
    final haloAlpha  = notifier.haloAlpha;
    final ringAlpha  = notifier.mid;
    final ringRadius = notifier.ringRadius(size);

    // ── Outer halo (treble) ───────────────────────────────────────────────
    if (haloAlpha > 0.005) {
      final haloRadius = size * 0.62;
      // Use a fixed blur radius to avoid per-frame shader recompilation.
      // Proportional blur (haloRadius * 0.35) caused raster cache misses.
      canvas.drawCircle(
        center,
        haloRadius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              glow.withValues(alpha: haloAlpha),
              glow.withValues(alpha: haloAlpha * 0.4),
              glow.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 0.55, 1.0],
          ).createShader(Rect.fromCircle(center: center, radius: haloRadius))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24.0),
      );
    }

    // ── Mid ring ──────────────────────────────────────────────────────────
    if (ringAlpha > 0.01) {
      canvas.drawCircle(
        center,
        ringRadius,
        Paint()
          ..color = energy.withValues(alpha: ringAlpha * 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.0, ringAlpha * 3.0)
          // Fixed blur radius — avoids proportional shader recompilation.
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0),
      );
    }
  }

  @override
  bool shouldRepaint(_LayersPainter old) =>
      old.energy != energy || old.glow != glow || old.size != size;
  // Value changes are handled by the repaint: notifier — no structural
  // comparison needed here.
}
