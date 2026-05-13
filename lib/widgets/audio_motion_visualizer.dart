import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show FftFrame;

import '../state/providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AudioMotionVisualizer — audiomotion-analyzer style spectrum renderer
//
// Visual model (mirrors audiomotion-analyzer Preset 1 / Preset 2):
//
//   • Log-spaced frequency bars (20 Hz – 20 kHz mapped to 64 FFT bins)
//   • Gradient coloring: spectral shadow (bass) → energy (mid) → glow (treble)
//   • Reflex: bars mirrored below center at reduced opacity (water reflection)
//   • Peak hold: per-bar peak dot that holds for ~500 ms then fades
//   • Rounded bar caps
//   • Bars grow upward from center baseline; reflex grows downward
//   • Transparent background — sits over artwork/gradient
//
// Architecture:
//   _AmaNotifier (ChangeNotifier) — all signal processing + peak state
//   _AmaPainter  (CustomPainter, repaint: notifier) — pure rendering
//   No setState, no AnimatedBuilder overhead in the hot path.
//   Ticker stops when paused and all bars + peaks have settled.
// ─────────────────────────────────────────────────────────────────────────────

class AudioMotionVisualizer extends ConsumerStatefulWidget {
  /// Height of the visualizer canvas (bars + reflex combined).
  final double height;

  /// Fraction of [height] used for the reflex mirror (0 = none, 0.5 = half).
  final double reflexRatio;

  /// Opacity of the reflex mirror (0–1).
  final double reflexAlpha;

  /// Fraction of bar width used as gap between bars (0 = no gap, 1 = all gap).
  final double barSpace;

  /// Whether to show peak-hold dots.
  final bool showPeaks;

  /// Peak hold duration before fade begins.
  final Duration peakHoldTime;

  /// Duration over which the peak dot fades to zero after hold.
  final Duration peakFadeTime;

  /// Whether to round bar caps.
  final bool roundBars;

  const AudioMotionVisualizer({
    super.key,
    this.height = 120,
    this.reflexRatio = 0.45,
    this.reflexAlpha = 0.35,
    this.barSpace = 0.25,
    this.showPeaks = true,
    this.peakHoldTime = const Duration(milliseconds: 500),
    this.peakFadeTime = const Duration(milliseconds: 900),
    this.roundBars = true,
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
    _notifier = _AmaNotifier(
      peakHoldMs: widget.peakHoldTime.inMilliseconds,
      peakFadeMs: widget.peakFadeTime.inMilliseconds,
    );
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
    final moving = _notifier.tick();
    if (!moving) _ticker.stop();
  }

  @override
  Widget build(BuildContext context) {
    final spectral = ref.watch(currentSpectralProvider);
    return RepaintBoundary(
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: AnimatedBuilder(
          animation: _notifier,
          builder: (context, _) => CustomPaint(
            painter: _AmaPainter(
              notifier: _notifier,
              energy: spectral.energy,
              glow: spectral.glow,
              shadow: spectral.shadow,
              reflexRatio: widget.reflexRatio,
              reflexAlpha: widget.reflexAlpha,
              barSpace: widget.barSpace,
              showPeaks: widget.showPeaks,
              roundBars: widget.roundBars,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _AmaNotifier — signal processor
//
// Single EMA smoothing per bar (mirrors audiomotion-analyzer's `smoothing`
// coefficient). No dual-envelope — audiomotion uses one smoothing value.
//
// Peak hold state machine per bar:
//   IDLE → HOLD (when bar exceeds peak) → FADE → IDLE
// ─────────────────────────────────────────────────────────────────────────────

class _AmaNotifier extends ChangeNotifier {
  static const int _barCount = 64;
  static const double _smoothing = 0.72; // EMA coefficient (higher = smoother)
  static const double _settleThresh = 0.0008;

  // Smoothed bar heights [0, 1].
  final Float32List _bars = Float32List(_barCount);

  // Peak hold state per bar.
  final Float32List _peakLevel = Float32List(_barCount);
  // Milliseconds since peak was last exceeded (for hold + fade timing).
  final Float32List _peakAge = Float32List(_barCount);

  final int _peakHoldMs;
  final int _peakFadeMs;

  // Timestamp of last tick for delta-time peak aging.
  int _lastTickMs = 0;

  _AmaNotifier({required int peakHoldMs, required int peakFadeMs})
      : _peakHoldMs = peakHoldMs,
        _peakFadeMs = peakFadeMs;

  /// Ingest a raw FFT frame (64 bins, [0,1]).
  void ingest(Float32List bands) {
    for (var i = 0; i < _barCount; i++) {
      final raw = i < bands.length ? bands[i] : 0.0;
      final safe = raw.isFinite ? raw.clamp(0.0, 1.0) : 0.0;

      // Psychoacoustic amplitude weighting — same as audiomotion's
      // default A-weighting approximation: boost bass, attenuate treble.
      final t = i / (_barCount - 1);
      final double weighted;
      if (i < 6) {
        // Sub-bass: sqrt boost.
        weighted = (math.sqrt(safe) * 1.6).clamp(0.0, 1.0);
      } else if (i < 14) {
        // Bass: moderate boost.
        weighted = (safe * 1.35).clamp(0.0, 1.0);
      } else if (i < 28) {
        // Mid: neutral.
        weighted = safe;
      } else {
        // Treble: gentle attenuation.
        weighted = (safe * (1.0 - t * 0.30)).clamp(0.0, 1.0);
      }

      // Single EMA smoothing (audiomotion-analyzer model).
      _bars[i] = _bars[i] * _smoothing + weighted * (1.0 - _smoothing);

      // Peak hold: update if bar exceeds current peak.
      if (_bars[i] >= _peakLevel[i]) {
        _peakLevel[i] = _bars[i];
        _peakAge[i] = 0.0; // reset hold timer
      }
    }
  }

  /// Advance one frame. Returns true if any bar or peak is still moving.
  bool tick() {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final dtMs = _lastTickMs == 0 ? 16.0 : (nowMs - _lastTickMs).toDouble();
    _lastTickMs = nowMs;

    var anyMoving = false;

    for (var i = 0; i < _barCount; i++) {
      // Decay bars toward zero when no FFT is being ingested.
      final prev = _bars[i];
      _bars[i] = prev * _smoothing;
      if ((_bars[i] - prev).abs() > _settleThresh) anyMoving = true;

      // Peak aging.
      if (_peakLevel[i] > _settleThresh) {
        _peakAge[i] += dtMs;
        if (_peakAge[i] > _peakHoldMs + _peakFadeMs) {
          // Fully faded — reset.
          _peakLevel[i] = 0.0;
          _peakAge[i] = 0.0;
        } else {
          anyMoving = true;
        }
      }
    }

    notifyListeners();
    return anyMoving;
  }

  /// Bar height for bar [i], [0, 1].
  double bar(int i) => _bars[i];

  /// Peak dot opacity for bar [i], [0, 1].
  /// Returns 0 when peak is in hold phase (fully visible) or below threshold.
  double peakAlpha(int i) {
    if (_peakLevel[i] < _settleThresh) return 0.0;
    final age = _peakAge[i];
    if (age <= _peakHoldMs) return 1.0; // hold phase — fully visible
    // Fade phase.
    final fadeProgress = (age - _peakHoldMs) / _peakFadeMs;
    return (1.0 - fadeProgress).clamp(0.0, 1.0);
  }

  /// Peak level for bar [i], [0, 1].
  double peakLevel(int i) => _peakLevel[i];
}

// ─────────────────────────────────────────────────────────────────────────────
// _AmaPainter — audiomotion-analyzer style renderer
//
// Layout:
//   Total height H.
//   Bar zone:    top = 0,                  height = H * (1 - reflexRatio)
//   Reflex zone: top = H * (1-reflexRatio), height = H * reflexRatio
//
// Bars grow upward from the bottom of the bar zone.
// Reflex is the bar zone flipped vertically, drawn at reduced opacity.
//
// Gradient: vertical, bottom-to-top across the bar zone.
//   bottom stop = shadow color (bass energy)
//   mid stop    = energy color
//   top stop    = glow color (treble peaks)
// ─────────────────────────────────────────────────────────────────────────────

class _AmaPainter extends CustomPainter {
  final _AmaNotifier notifier;
  final Color energy;
  final Color glow;
  final Color shadow;
  final double reflexRatio;
  final double reflexAlpha;
  final double barSpace;
  final bool showPeaks;
  final bool roundBars;

  static const int _barCount = 64;
  static const double _peakDotHeight = 3.0;

  const _AmaPainter({
    required this.notifier,
    required this.energy,
    required this.glow,
    required this.shadow,
    required this.reflexRatio,
    required this.reflexAlpha,
    required this.barSpace,
    required this.showPeaks,
    required this.roundBars,
  }) : super(repaint: notifier);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final barZoneH = size.height * (1.0 - reflexRatio);
    final reflexZoneTop = barZoneH;

    // Bar geometry: equal-width bars with gap fraction.
    final totalBarW = size.width / _barCount;
    final barW = totalBarW * (1.0 - barSpace.clamp(0.0, 0.9));
    final barX0 = totalBarW * barSpace / 2; // left offset of first bar center

    // Gradient: bottom of bar zone → top of bar zone.
    final gradient = LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [shadow, energy, glow],
      stops: const [0.0, 0.55, 1.0],
    );
    final gradientRect = Rect.fromLTWH(0, 0, size.width, barZoneH);
    final gradientShader = gradient.createShader(gradientRect);

    final barPaint = Paint()
      ..shader = gradientShader
      ..style = PaintingStyle.fill;

    final peakPaint = Paint()..style = PaintingStyle.fill;

    // ── Draw bars ────────────────────────────────────────────────────────────
    for (var i = 0; i < _barCount; i++) {
      final level = notifier.bar(i);
      if (level < 0.001) continue;

      final barH = (level * barZoneH).clamp(1.0, barZoneH);
      final x = barX0 + i * totalBarW;
      final y = barZoneH - barH;

      final rect = Rect.fromLTWH(x, y, barW, barH);

      if (roundBars && barH > barW) {
        final r = Radius.circular(barW / 2);
        canvas.drawRRect(
          RRect.fromRectAndCorners(rect, topLeft: r, topRight: r),
          barPaint,
        );
      } else {
        canvas.drawRect(rect, barPaint);
      }

      // ── Peak dot ──────────────────────────────────────────────────────────
      if (showPeaks) {
        final pAlpha = notifier.peakAlpha(i);
        if (pAlpha > 0.01) {
          final pLevel = notifier.peakLevel(i);
          final pY = barZoneH - (pLevel * barZoneH).clamp(1.0, barZoneH) - _peakDotHeight - 1.0;
          // Color at peak height position in gradient.
          final t = pLevel.clamp(0.0, 1.0);
          final Color peakColor;
          if (t < 0.55) {
            peakColor = Color.lerp(shadow, energy, t / 0.55)!;
          } else {
            peakColor = Color.lerp(energy, glow, (t - 0.55) / 0.45)!;
          }
          peakPaint.color = peakColor.withValues(alpha: pAlpha);
          final peakRect = Rect.fromLTWH(x, pY, barW, _peakDotHeight);
          if (roundBars) {
            canvas.drawRRect(
              RRect.fromRectAndRadius(peakRect, const Radius.circular(1.5)),
              peakPaint,
            );
          } else {
            canvas.drawRect(peakRect, peakPaint);
          }
        }
      }
    }

    // ── Reflex (mirror) ──────────────────────────────────────────────────────
    if (reflexRatio > 0.01 && reflexAlpha > 0.01) {
      canvas.save();
      // Clip to reflex zone.
      canvas.clipRect(
        Rect.fromLTWH(0, reflexZoneTop, size.width, size.height - reflexZoneTop),
      );
      // Flip vertically around the baseline (reflexZoneTop).
      canvas.translate(0, reflexZoneTop * 2);
      canvas.scale(1, -1);

      // Reflex gradient: same gradient but at reduced opacity.
      final reflexGradient = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          shadow.withValues(alpha: reflexAlpha),
          energy.withValues(alpha: reflexAlpha * 0.7),
          glow.withValues(alpha: reflexAlpha * 0.4),
        ],
        stops: const [0.0, 0.55, 1.0],
      );
      final reflexShader = reflexGradient.createShader(gradientRect);
      final reflexPaint = Paint()
        ..shader = reflexShader
        ..style = PaintingStyle.fill;

      for (var i = 0; i < _barCount; i++) {
        final level = notifier.bar(i);
        if (level < 0.001) continue;

        final barH = (level * barZoneH).clamp(1.0, barZoneH);
        final x = barX0 + i * totalBarW;
        final y = barZoneH - barH;

        final rect = Rect.fromLTWH(x, y, barW, barH);
        if (roundBars && barH > barW) {
          final r = Radius.circular(barW / 2);
          canvas.drawRRect(
            RRect.fromRectAndCorners(rect, topLeft: r, topRight: r),
            reflexPaint,
          );
        } else {
          canvas.drawRect(rect, reflexPaint);
        }
      }

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_AmaPainter old) =>
      old.energy != energy ||
      old.glow != glow ||
      old.shadow != shadow ||
      old.reflexRatio != reflexRatio ||
      old.reflexAlpha != reflexAlpha ||
      old.barSpace != barSpace ||
      old.showPeaks != showPeaks ||
      old.roundBars != roundBars;
}
