import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show FftFrame;

import '../design_tokens/tokens.dart';
import '../state/providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// REDESIGNED SIGNAL ARCHITECTURE — waveform.dart
//
// The previous renderer was a uniform horizontal bar chart. Every bar shared
// the same center-Y, same width, same color gradient direction. The topology
// was a single organism by construction — perceptually dead.
//
// New architecture: DISTRIBUTED SPECTRAL FIELD
// ─────────────────────────────────────────────
// Layer 1 — Raw FFT truth (64 bins, immutable per frame)
//   Direct 1:1 mapping. Never globally smoothed.
//
// Layer 2 — Spectral redistribution + transient extraction
//   Per-bar dual-envelope transient detector (fast - slow = impulse).
//   Logarithmic psychoacoustic amplitude weighting.
//   Delta-energy emphasis: transients amplified 3× over sustained energy.
//
// Layer 3 — Independent emitters (one per bar)
//   Each bar owns: sustained energy, transient impulse, vertical anchor,
//   width multiplier, opacity, micro-jitter phase.
//   No shared state. No global coherence.
//
// Layer 4 — Asymmetric spatial renderer
//   Bars are NOT uniform. Each bar has:
//     • frequency-dependent width (bass wide, treble thin)
//     • frequency-dependent vertical anchor (bass bottom-anchored,
//       treble top-anchored, mid center-anchored)
//     • transient tip extension above/below the bar body
//     • per-bar micro-jitter in height for organic instability
//     • color: played/unplayed split still works for scrubbing
//
// Why this produces perceptual separation:
//   • Kick drum → bass bars spike from the bottom, wide, heavy
//   • Hi-hat → treble bars flicker from the top, thin, fast
//   • Vocal → mid bars pulse from center, medium width
//   • The eye sees localized activity in different spatial zones,
//     not one breathing shape.
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// FftWaveform — live FFT visualiser + progress scrubber
//
// Architecture
// ────────────
// • A [_WaveformNotifier] (ChangeNotifier) owns all animation state:
//   FFT signal processing, idle oscillation, drag progress.
//   It drives repaints via CustomPainter(repaint: notifier) — no setState.
//
// • The ticker only runs when playing or dragging. It stops automatically
//   when paused and all emitters have settled.
//
// • All buffers are pre-allocated — no per-frame allocation.
//   shouldRepaint() is always false because repaint is driven by the
//   Listenable, not structural comparison.
//
// • FFT values are validated (NaN/Infinity guard) before processing.
//
// • Reduced-motion accessibility: idle animation disabled when
//   MediaQuery.disableAnimations is true.
//
// Public API (unchanged):
//   peaks, progress, isPlaying, playedColor, unplayedColor,
//   height, onScrub, onScrubEnd
// ─────────────────────────────────────────────────────────────────────────────

class FftWaveform extends ConsumerStatefulWidget {
  final List<int> peaks;
  final double progress;
  final Color playedColor;
  final Color unplayedColor;
  final double height;
  final ValueChanged<double>? onScrub;
  final ValueChanged<double>? onScrubEnd;
  final bool isPlaying;

  const FftWaveform({
    super.key,
    required this.peaks,
    required this.progress,
    this.playedColor   = AfColors.indigo300,
    this.unplayedColor = AfColors.textTertiary,
    this.height        = 72,
    this.onScrub,
    this.onScrubEnd,
    this.isPlaying     = true,
  });

  @override
  ConsumerState<FftWaveform> createState() => _FftWaveformState();
}

class _FftWaveformState extends ConsumerState<FftWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;
  late final _WaveformNotifier _notifier;
  StreamSubscription<FftFrame>? _fftSub;

  @override
  void initState() {
    super.initState();
    _notifier = _WaveformNotifier(widget.peaks);
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_onTick);
    _maybeStartTicker();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _fftSub?.cancel();
    final svc = ref.read(playerServiceProvider);
    _fftSub = svc.spectrumStream.listen((frame) {
      _notifier._setFftTarget(frame.bands);
      _maybeStartTicker();
    });
  }

  @override
  void didUpdateWidget(FftWaveform old) {
    super.didUpdateWidget(old);
    if (old.peaks != widget.peaks) {
      _notifier._resetPeaks(widget.peaks);
    }
    if (old.isPlaying != widget.isPlaying) {
      _maybeStartTicker();
    }
    // Forward progress/color changes to notifier so painter sees them.
    _notifier._progress = widget.progress;
    _notifier._playedColor   = widget.playedColor;
    _notifier._unplayedColor = widget.unplayedColor;
  }

  @override
  void dispose() {
    _fftSub?.cancel();
    _ticker.dispose();
    _notifier.dispose();
    super.dispose();
  }

  void _maybeStartTicker() {
    if ((widget.isPlaying || _notifier._dragging) && !_ticker.isAnimating) {
      _ticker.repeat();
    }
  }

  void _onTick() {
    if (!mounted) return;
    final reducedMotion = MediaQuery.of(context).disableAnimations;
    final changed = _notifier._tick(
      isPlaying: widget.isPlaying,
      reducedMotion: reducedMotion,
    );
    // Stop ticker when paused and all bars have settled.
    if (!changed && !widget.isPlaying && !_notifier._dragging) {
      _ticker.stop();
    }
  }

  // ── Gesture handlers ──────────────────────────────────────────────────────

  void _handleDragStart(DragStartDetails d) {
    HapticFeedback.selectionClick();
    _notifier._setDrag(true, _toProgress(d.localPosition.dx));
    widget.onScrub?.call(_notifier._dragProgress);
    _maybeStartTicker();
  }

  void _handleDragUpdate(DragUpdateDetails d) {
    _notifier._setDrag(true, _toProgress(d.localPosition.dx));
    widget.onScrub?.call(_notifier._dragProgress);
  }

  void _handleDragEnd(DragEndDetails _) {
    widget.onScrubEnd?.call(_notifier._dragProgress);
    _notifier._setDrag(false, _notifier._dragProgress);
  }

  void _handleTap(TapDownDetails d) {
    HapticFeedback.selectionClick();
    final p = _toProgress(d.localPosition.dx);
    widget.onScrub?.call(p);
    widget.onScrubEnd?.call(p);
  }

  double _toProgress(double dx) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || box.size.width <= 0) return 0;
    return (dx / box.size.width).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    // Sync progress/colors on every build (cheap field writes).
    _notifier._progress      = widget.progress;
    _notifier._playedColor   = widget.playedColor;
    _notifier._unplayedColor = widget.unplayedColor;

    return RepaintBoundary(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: _handleDragStart,
        onHorizontalDragUpdate: _handleDragUpdate,
        onHorizontalDragEnd: _handleDragEnd,
        onTapDown: _handleTap,
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: CustomPaint(
            painter: _WaveformPainter(notifier: _notifier),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _WaveformNotifier — distributed spectral field signal processor.
//
// Layer 1: Raw FFT truth — 64 bins, immutable per frame.
// Layer 2: Per-bar dual-envelope transient extraction.
//   fast[i] tracks instantaneous energy (lerp 0.65–0.90 by frequency).
//   slow[i] tracks sustained baseline (lerp 0.05–0.12 by frequency).
//   transient[i] = max(0, fast[i] - slow[i]) — the "punch" signal.
// Layer 3: Independent emitters.
//   sustained[i] = smoothed energy, frequency-weighted.
//   transient[i] = impulse channel, decays faster than sustained.
//   jitter[i]    = per-bar micro-noise for organic instability.
// ─────────────────────────────────────────────────────────────────────────────

class _WaveformNotifier extends ChangeNotifier {
  // ── Layer 1: Raw FFT truth ────────────────────────────────────────────────
  Float32List? _fftTarget;
  bool _hasFft = false;

  // ── Layer 2+3: Independent emitter state ─────────────────────────────────
  // sustained[i]: smoothed energy level, [0,1]. Drives bar body height.
  late Float32List sustained;
  // transient[i]: impulse channel. Drives tip extension above/below bar.
  late Float32List _transient;
  // fast/slow envelopes for transient detection.
  late Float32List _fast;
  late Float32List _slow;
  // Per-bar micro-jitter for organic instability (especially treble).
  late Float32List _jitter;
  late Float32List _jitterV;

  // Pre-computed per-bar envelope parameters.
  late Float32List _attack;   // sustained attack lerp
  late Float32List _decay;    // sustained decay lerp
  late Float32List _tDecay;   // transient decay lerp (faster)
  late Float32List _fastLerp; // fast envelope lerp
  late Float32List _slowLerp; // slow envelope lerp

  // ── Idle animation ────────────────────────────────────────────────────────
  double _idlePhase = 0.0;

  // ── Drag state ────────────────────────────────────────────────────────────
  bool   _dragging     = false;
  double _dragProgress = 0.0;

  // ── Display state ─────────────────────────────────────────────────────────
  double _progress      = 0.0;
  Color  _playedColor   = AfColors.indigo300;
  Color  _unplayedColor = AfColors.textTertiary;

  static const int    _barCount     = 64;
  static const double _minHeight    = 0.04;
  static const double _settleThresh = 0.0006;

  // Frequency region boundaries (bin indices):
  //   bass:    0–7   heavy, bottom-anchored, wide bars
  //   low-mid: 8–15  medium weight, slight bottom bias
  //   mid:     16–31 center-anchored, neutral
  //   treble:  32–63 top-anchored, thin, fast flicker
  static const int _bassEnd   = 8;
  static const int _lowMidEnd = 16;
  static const int _midEnd    = 32;

  final _rng = math.Random(42); // seeded for deterministic jitter init

  _WaveformNotifier(List<int> peaks) {
    _initBuffers(peaks);
  }

  void _initBuffers(List<int> peaks) {
    sustained  = Float32List(_barCount);
    _transient = Float32List(_barCount);
    _fast      = Float32List(_barCount);
    _slow      = Float32List(_barCount);
    _jitter    = Float32List(_barCount);
    _jitterV   = Float32List(_barCount);
    _attack    = Float32List(_barCount);
    _decay     = Float32List(_barCount);
    _tDecay    = Float32List(_barCount);
    _fastLerp  = Float32List(_barCount);
    _slowLerp  = Float32List(_barCount);

    for (var i = 0; i < _barCount; i++) {
      final t = i / (_barCount - 1); // 0=bass, 1=treble

      // Seed from static peaks waveform.
      final peakVal = (i < peaks.length)
          ? (peaks[i] / 100.0).clamp(_minHeight, 1.0) * 0.4
          : _minHeight;
      sustained[i] = peakVal;

      // ── Psychoacoustic envelope parameters ───────────────────────────────
      // Bass: slow attack, very slow decay — weight builds, sustains.
      // Treble: fast attack, fast decay — flickers, sparkles.
      _attack[i]   = (0.55 + t * 0.35).clamp(0.55, 0.90);
      _decay[i]    = (0.05 + t * 0.28).clamp(0.05, 0.33);
      _tDecay[i]   = (0.18 + t * 0.45).clamp(0.18, 0.63); // transient faster
      _fastLerp[i] = (0.55 + t * 0.35).clamp(0.55, 0.90);
      _slowLerp[i] = (0.04 + t * 0.08).clamp(0.04, 0.12);

      // Seed jitter at random phases so bars start incoherent.
      _jitter[i]  = _rng.nextDouble() * 2 * math.pi;
      // Treble bars get faster jitter velocity — hi-hat instability.
      final jSpeed = 0.015 + t * 0.055;
      _jitterV[i] = jSpeed * (_rng.nextBool() ? 1 : -1);
    }
  }

  void _resetPeaks(List<int> peaks) => _initBuffers(peaks);

  void _setFftTarget(Float32List bands) {
    _fftTarget = bands;
    _hasFft = true;
  }

  void _setDrag(bool dragging, double progress) {
    _dragging     = dragging;
    _dragProgress = progress;
    notifyListeners();
  }

  double get displayProgress =>
      _dragging ? _dragProgress : _progress.clamp(0.0, 1.0);

  /// Advance one frame. Returns true if any emitter is still moving.
  bool _tick({required bool isPlaying, required bool reducedMotion}) {
    var anyMoving = false;

    if (_hasFft && _fftTarget != null) {
      final bands = _fftTarget!;

      for (var i = 0; i < _barCount; i++) {
        // ── Layer 1: Raw FFT truth ──────────────────────────────────────────
        final raw    = i < bands.length ? bands[i] : 0.0;
        final safeRaw = raw.isFinite ? raw.clamp(0.0, 1.0) : 0.0;

        // ── Psychoacoustic amplitude weighting ──────────────────────────────
        // Bass amplified (perceptually louder), treble attenuated.
        // Weighting is non-linear: bass gets a hard boost, treble a soft cut.
        final double weighted;
        if (i < _bassEnd) {
          // Bass: strong boost + slight saturation curve.
          weighted = (math.sqrt(safeRaw) * 1.7).clamp(0.0, 1.0);
        } else if (i < _lowMidEnd) {
          weighted = (safeRaw * 1.25).clamp(0.0, 1.0);
        } else if (i < _midEnd) {
          weighted = safeRaw;
        } else {
          // Treble: attenuate but preserve transient punch.
          weighted = (safeRaw * 0.80).clamp(0.0, 1.0);
        }

        // ── Layer 2: Dual-envelope transient detection ──────────────────────
        // fast tracks instantaneous energy; slow tracks baseline.
        // impulse = fast - slow = the "new energy" this frame.
        _fast[i] += (weighted - _fast[i]) * _fastLerp[i];
        _slow[i] += (weighted - _slow[i]) * _slowLerp[i];
        final impulse = math.max(0.0, _fast[i] - _slow[i]);

        // Transient: amplify impulse strongly. This is what makes
        // individual hits punch through without smearing.
        final tTarget = (impulse * 3.2).clamp(0.0, 1.0);
        if (tTarget > _transient[i]) {
          _transient[i] = tTarget; // instant attack
        }

        // ── Layer 3: Independent sustained envelope ─────────────────────────
        final sTarget = weighted.clamp(_minHeight, 1.0);
        final sLerp   = sTarget > sustained[i] ? _attack[i] : _decay[i];
        final sNext   = sustained[i] + (sTarget - sustained[i]) * sLerp;
        if ((sNext - sustained[i]).abs() > _settleThresh) anyMoving = true;
        sustained[i] = sNext;

        // Transient decay (faster than sustained).
        final tNext = _transient[i] * (1.0 - _tDecay[i]);
        if ((_transient[i] - tNext).abs() > _settleThresh) anyMoving = true;
        _transient[i] = tNext;

        // ── Micro-jitter: per-bar organic instability ───────────────────────
        // Treble bars oscillate faster — hi-hat shimmer.
        // Bass bars oscillate slowly — sub-bass breathing.
        _jitter[i] += _jitterV[i];
        // Slowly drift jitter velocity for long-term variation.
        _jitterV[i] += (_rng.nextDouble() - 0.5) * 0.003;
        final maxV = 0.015 + (i / _barCount) * 0.055;
        _jitterV[i] = _jitterV[i].clamp(-maxV, maxV);
      }
    } else if (isPlaying && !reducedMotion) {
      // Idle: per-bar sine oscillation with frequency-differentiated phases.
      // Each bar still uses its own decay so idle feels spectrally alive.
      _idlePhase = (_idlePhase + 0.025) % (math.pi * 2);
      for (var i = 0; i < _barCount; i++) {
        final peak   = sustained[i].clamp(_minHeight, 1.0);
        // Phase offset varies by bar so they don't all move together.
        final target = peak * (0.35 + 0.20 * math.sin(_idlePhase + i * 0.31));
        final next   = sustained[i] + (target - sustained[i]) * _decay[i];
        if ((next - sustained[i]).abs() > _settleThresh) anyMoving = true;
        sustained[i] = next;
        _jitter[i] += _jitterV[i] * 0.3;
      }
    }

    notifyListeners();
    return anyMoving;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _WaveformPainter — asymmetric distributed spectral field renderer.
//
// Layer 4: Spatial renderer.
//
// Key departures from the old uniform bar chart:
//
// 1. VERTICAL ANCHOR by frequency region:
//    Bass bars grow upward from the bottom — like a kick drum hitting the floor.
//    Treble bars grow downward from the top — hi-hats shimmer from above.
//    Mid bars grow from center — vocals occupy the middle space.
//    This creates three distinct spatial zones the eye can track independently.
//
// 2. VARIABLE BAR WIDTH by frequency:
//    Bass bars are wider (spectral weight is perceptually wide).
//    Treble bars are thinner (hi-hats are point sources).
//    This breaks the uniform grid topology.
//
// 3. TRANSIENT TIP EXTENSION:
//    Each bar has a body (sustained energy) + a tip (transient impulse).
//    The tip extends beyond the body in the anchor direction.
//    Kicks punch through the bottom; hi-hats spike through the top.
//    The tip is brighter and slightly wider than the body.
//
// 4. MICRO-JITTER in height:
//    Each bar's height is modulated by its jitter phase.
//    Treble bars jitter fast (shimmer). Bass bars jitter slow (breathe).
//    This injects controlled incoherence — no two bars move identically.
//
// 5. OPACITY by energy:
//    Low-energy bars fade out rather than staying at minimum height.
//    This creates visible "holes" in the spectrum during silence,
//    making active regions pop by contrast.
//
// 6. PLAYED/UNPLAYED split still works:
//    The color split is applied per-bar based on progress, same as before.
//    Scrubbing still works correctly.
// ─────────────────────────────────────────────────────────────────────────────

class _WaveformPainter extends CustomPainter {
  final _WaveformNotifier notifier;

  // Bar width multipliers by frequency region.
  // Bass bars are 1.6× the base width; treble bars are 0.55×.
  static const double _bassWidthMul   = 1.60;
  static const double _lowMidWidthMul = 1.20;
  static const double _midWidthMul    = 0.90;
  static const double _trebleWidthMul = 0.55;

  // Gap between bars as a fraction of base bar width.
  static const double _gapFraction = 0.40;

  // Minimum rendered bar height in logical pixels.
  static const double _minBarPx = 2.5;

  // Playhead geometry.
  static const double _headWidth       = 2.0;
  static const double _thumbRadius     = 5.0;
  static const double _thumbRadiusDrag = 7.5;
  static const double _glowRadius      = 10.0;

  _WaveformPainter({required this.notifier}) : super(repaint: notifier);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final s = notifier.sustained;
    if (s.isEmpty) return;

    final barCount = s.length;
    // Base bar width: divide total width evenly, then scale per-bar.
    // We compute a nominal width assuming average multiplier ~1.0.
    final baseWidth = size.width / (barCount * (1.0 + _gapFraction));
    final gap       = baseWidth * _gapFraction;

    final progress   = notifier.displayProgress;
    final headBarF   = progress * barCount;
    final headX      = progress * size.width;
    final isDragging = notifier._dragging;

    final playedPaint   = Paint()..style = PaintingStyle.fill;
    final unplayedPaint = Paint()..style = PaintingStyle.fill;

    // ── Bars ─────────────────────────────────────────────────────────────
    // We accumulate x manually because bar widths vary.
    var x = 0.0;
    for (var i = 0; i < barCount; i++) {
      final t = i / (barCount - 1); // 0=bass, 1=treble

      // ── Bar width: frequency-dependent ───────────────────────────────
      final double widthMul;
      if (i < _WaveformNotifier._bassEnd) {
        widthMul = _bassWidthMul;
      } else if (i < _WaveformNotifier._lowMidEnd) {
        widthMul = _lowMidWidthMul;
      } else if (i < _WaveformNotifier._midEnd) {
        widthMul = _midWidthMul;
      } else {
        widthMul = _trebleWidthMul;
      }
      final barW = baseWidth * widthMul;

      // ── Energy + jitter ───────────────────────────────────────────────
      final energy    = s[i];
      final transient = notifier._transient[i];
      final jitter    = notifier._jitter[i];

      // Micro-jitter modulates height by ±8% for bass, ±18% for treble.
      final jitterAmp  = 0.08 + t * 0.10;
      final jitterMod  = 1.0 + jitterAmp * math.sin(jitter);
      final bodyHeight = math.max(_minBarPx,
          size.height * energy * jitterMod).clamp(_minBarPx, size.height * 0.92);
      final tipHeight  = transient * size.height * 0.28;

      // ── Vertical anchor: frequency-dependent ─────────────────────────
      // Bass: bottom-anchored (grows up from floor).
      // Treble: top-anchored (grows down from ceiling).
      // Mid: center-anchored.
      // Low-mid: slight bottom bias (lerp between bass and mid).
      final double bodyTop;
      final double tipTop;
      if (i < _WaveformNotifier._bassEnd) {
        // Bottom-anchored.
        bodyTop = size.height - bodyHeight;
        tipTop  = bodyTop - tipHeight;
      } else if (i < _WaveformNotifier._lowMidEnd) {
        // Slight bottom bias: lerp between bottom-anchor and center.
        final bias = 0.35; // 0=center, 1=bottom
        final centerTop = (size.height - bodyHeight) / 2;
        final bottomTop = size.height - bodyHeight;
        bodyTop = centerTop + (bottomTop - centerTop) * bias;
        tipTop  = bodyTop - tipHeight;
      } else if (i < _WaveformNotifier._midEnd) {
        // Center-anchored.
        bodyTop = (size.height - bodyHeight) / 2;
        tipTop  = bodyTop - tipHeight / 2; // tip splits above and below
      } else {
        // Top-anchored (treble grows down from ceiling).
        bodyTop = 0;
        tipTop  = bodyHeight; // tip extends below the bar body
      }

      // ── Opacity: energy-driven ────────────────────────────────────────
      // Low-energy bars fade out. Creates visible spectral holes.
      final alpha = (0.12 + energy * 0.88).clamp(0.0, 1.0);

      // ── Color: played/unplayed split ──────────────────────────────────
      final isPlayed = i < headBarF;
      final isSplit  = i == headBarF.floor();
      final Color baseColor;
      if (isPlayed) {
        baseColor = notifier._playedColor;
      } else if (isSplit) {
        final frac = headBarF - headBarF.floor();
        baseColor = Color.lerp(
          notifier._unplayedColor.withValues(alpha: 0.28),
          notifier._playedColor,
          frac,
        )!;
      } else {
        baseColor = notifier._unplayedColor.withValues(alpha: 0.28);
      }

      playedPaint.color = baseColor.withValues(alpha: alpha);

      // ── Draw bar body ─────────────────────────────────────────────────
      final capR = Radius.circular(barW / 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, bodyTop, barW, bodyHeight),
          capR,
        ),
        playedPaint,
      );

      // ── Draw transient tip ────────────────────────────────────────────
      if (transient > 0.06 && tipHeight > 1.0) {
        final tipW = barW * (0.7 + transient * 0.5);
        final tipX = x + (barW - tipW) / 2;
        final tipColor = baseColor.withValues(alpha: (alpha * transient * 1.4).clamp(0.0, 1.0));
        unplayedPaint.color = tipColor;

        if (i < _WaveformNotifier._midEnd) {
          // Bass/low-mid/mid: tip extends upward.
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(tipX, tipTop, tipW, tipHeight),
              Radius.circular(tipW / 2),
            ),
            unplayedPaint,
          );
        } else {
          // Treble: tip extends downward below bar body.
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(tipX, tipTop, tipW, tipHeight),
              Radius.circular(tipW / 2),
            ),
            unplayedPaint,
          );
        }
      }

      x += barW + gap;
    }

    // ── Playhead glow ────────────────────────────────────────────────────
    canvas.drawRect(
      Rect.fromLTWH(headX - _glowRadius, 0, _glowRadius * 2, size.height),
      Paint()
        ..color = notifier._playedColor
            .withValues(alpha: isDragging ? 0.22 : 0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // ── Playhead line ────────────────────────────────────────────────────
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(headX - _headWidth / 2, 0, _headWidth, size.height),
        const Radius.circular(1),
      ),
      Paint()
        ..color = isDragging
            ? AfColors.textPrimary
            : notifier._playedColor.withValues(alpha: 0.9)
        ..style = PaintingStyle.fill,
    );

    // ── Scrub thumb ──────────────────────────────────────────────────────
    final centerY = size.height / 2;
    final thumbR  = isDragging ? _thumbRadiusDrag : _thumbRadius;
    if (isDragging) {
      canvas.drawCircle(
        Offset(headX, centerY),
        thumbR + 7,
        Paint()
          ..color = notifier._playedColor.withValues(alpha: 0.22)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
    canvas.drawCircle(
      Offset(headX, centerY),
      thumbR,
      Paint()
        ..color = AfColors.textPrimary
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_WaveformPainter _) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Waveform — static peaks-only scrubber (Queue, mini-player, etc.)
//
// Same architecture: ChangeNotifier drives repaints, no setState.
// Ticker stops when paused and bars have settled.
// ─────────────────────────────────────────────────────────────────────────────

class Waveform extends StatefulWidget {
  final List<int> peaks;
  final double progress;
  final Color playedColor;
  final Color unplayedColor;
  final double height;
  final ValueChanged<double>? onScrub;
  final ValueChanged<double>? onScrubEnd;
  final bool isPlaying;

  const Waveform({
    super.key,
    required this.peaks,
    required this.progress,
    this.playedColor   = AfColors.indigo300,
    this.unplayedColor = AfColors.textTertiary,
    this.height        = 72,
    this.onScrub,
    this.onScrubEnd,
    this.isPlaying     = true,
  });

  @override
  State<Waveform> createState() => _WaveformState();
}

class _WaveformState extends State<Waveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;
  late final _WaveformNotifier _notifier;

  @override
  void initState() {
    super.initState();
    _notifier = _WaveformNotifier(widget.peaks);
    _notifier._progress      = widget.progress;
    _notifier._playedColor   = widget.playedColor;
    _notifier._unplayedColor = widget.unplayedColor;
    _ctl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_onTick);
    if (widget.isPlaying) _ctl.repeat();
  }

  @override
  void didUpdateWidget(covariant Waveform old) {
    super.didUpdateWidget(old);
    if (old.peaks != widget.peaks) _notifier._resetPeaks(widget.peaks);
    _notifier._progress      = widget.progress;
    _notifier._playedColor   = widget.playedColor;
    _notifier._unplayedColor = widget.unplayedColor;
    if (widget.isPlaying && !_ctl.isAnimating) {
      _ctl.repeat();
    } else if (!widget.isPlaying && _ctl.isAnimating) {
      // Let bars settle before stopping.
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    _notifier.dispose();
    super.dispose();
  }

  void _onTick() {
    if (!mounted) return;
    final reducedMotion = MediaQuery.of(context).disableAnimations;
    final changed = _notifier._tick(
      isPlaying: widget.isPlaying,
      reducedMotion: reducedMotion,
    );
    if (!changed && !widget.isPlaying && !_notifier._dragging) {
      _ctl.stop();
    }
  }

  void _handleDragStart(DragStartDetails d) {
    HapticFeedback.selectionClick();
    _notifier._setDrag(true, _toProgress(d.localPosition.dx));
    widget.onScrub?.call(_notifier._dragProgress);
    if (!_ctl.isAnimating) _ctl.repeat();
  }

  void _handleDragUpdate(DragUpdateDetails d) {
    _notifier._setDrag(true, _toProgress(d.localPosition.dx));
    widget.onScrub?.call(_notifier._dragProgress);
  }

  void _handleDragEnd(DragEndDetails _) {
    widget.onScrubEnd?.call(_notifier._dragProgress);
    _notifier._setDrag(false, _notifier._dragProgress);
  }

  void _handleTap(TapDownDetails d) {
    HapticFeedback.selectionClick();
    final p = _toProgress(d.localPosition.dx);
    widget.onScrub?.call(p);
    widget.onScrubEnd?.call(p);
  }

  double _toProgress(double dx) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || box.size.width <= 0) return 0;
    return (dx / box.size.width).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    _notifier._progress      = widget.progress;
    _notifier._playedColor   = widget.playedColor;
    _notifier._unplayedColor = widget.unplayedColor;

    return RepaintBoundary(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: _handleDragStart,
        onHorizontalDragUpdate: _handleDragUpdate,
        onHorizontalDragEnd: _handleDragEnd,
        onTapDown: _handleTap,
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: CustomPaint(
            painter: _WaveformPainter(notifier: _notifier),
          ),
        ),
      ),
    );
  }
}
