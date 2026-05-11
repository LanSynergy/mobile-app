import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_tokens/tokens.dart';
import '../state/providers.dart';
import 'artwork.dart';

/// Album artwork that pulses in real-time sync with the audio output.
///
/// ## How it works
///
/// On Android, [VisualizerPlugin] (Kotlin) attaches
/// `android.media.audiofx.Visualizer` to ExoPlayer's audio session and
/// streams normalised FFT magnitude values (~60 Hz) via an [EventChannel].
/// [fftMagnitudeProvider] exposes that stream to the Riverpod tree.
///
/// Each FFT frame drives an [AnimationController] target: the controller
/// animates toward the incoming magnitude with a short spring-like decay
/// so rapid transients produce a sharp attack and a smooth tail rather
/// than a jittery flicker.
///
/// The magnitude is mapped to a [Transform.scale] in [1.0, 1.06] — the
/// artwork grows up to 6 % on loud beats and returns to rest on silence.
///
/// ## Fallback
///
/// When [fftMagnitudeProvider] emits nothing (non-Android, plugin absent,
/// or paused), the controller decays to 0 and the artwork sits at scale
/// 1.0 — no animation, no battery drain.
///
/// ## Design token compliance
///
/// Audio-coupled animations must use [AfCurves.linear]. The controller
/// drives a raw linear interpolation toward the target; no easing curve
/// is applied on top of it.
class BeatPulseArtwork extends ConsumerStatefulWidget {
  /// Cover art URL (may be null — falls back to the placeholder).
  final String? imageUrl;

  /// Square size of the artwork in logical pixels.
  final double size;

  /// Corner radius applied to the artwork.
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
  late final AnimationController _ctl;

  /// Maximum scale excursion at full FFT magnitude (1.0).
  /// 0.06 = artwork grows to 106 % on the loudest beats.
  static const double _maxScaleDelta = 0.06;

  /// How quickly the controller chases the incoming FFT value.
  /// Lower = snappier attack; higher = smoother but more lag.
  static const double _attackLerp = 0.55;

  /// How quickly the controller decays back toward zero when no FFT
  /// data arrives (pause / silence).
  static const double _decayLerp = 0.12;

  /// Current target magnitude [0.0, 1.0] set by the FFT stream.
  double _target = 0.0;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(
      vsync: this,
      // Duration is irrelevant — we drive the value manually each tick.
      duration: const Duration(milliseconds: 16),
    )..addListener(_onTick);
    _ctl.repeat();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  /// Called every frame (~60 fps) by the AnimationController repeat loop.
  /// Lerps the controller's value toward [_target] for attack, or toward
  /// 0.0 for decay when no new FFT data has arrived.
  void _onTick() {
    final current = _ctl.value;
    final lerp = _target > current ? _attackLerp : _decayLerp;
    final next = current + ((_target - current) * lerp);
    // Clamp to [0, 1] and write back without triggering a rebuild loop —
    // AnimationController.value setter notifies listeners (including this
    // one) but the repeat() loop drives the next frame independently.
    _ctl.value = next.clamp(0.0, 1.0);
    // Decay target toward silence so the artwork returns to rest when
    // the FFT stream stops emitting (pause / end of track).
    _target *= 0.85;
  }

  @override
  Widget build(BuildContext context) {
    // Watch the FFT stream. Each new magnitude value updates [_target];
    // the AnimationController tick loop smoothly chases it.
    ref.listen<AsyncValue<double>>(fftMagnitudeProvider, (_, next) {
      next.whenData((magnitude) {
        _target = magnitude.clamp(0.0, 1.0);
      });
    });

    return AnimatedBuilder(
      animation: _ctl,
      builder: (context, child) {
        final scale = 1.0 + _maxScaleDelta * _ctl.value;
        return Transform.scale(
          scale: scale,
          child: child,
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
