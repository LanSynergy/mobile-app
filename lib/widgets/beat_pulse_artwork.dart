import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_tokens/tokens.dart';
import '../state/providers.dart';
import 'artwork.dart';

/// Album artwork that pulses in real-time sync with the audio output.
///
/// ## How it works
///
/// [fftSpectrumProvider] exposes `Player.stream.spectrum` from
/// mpv_audio_kit — 64 log-spaced perceptual bands in [0, 1] at ~30 fps,
/// captured post-DSP (after EQ, volume, compressor: what you actually
/// hear). No RECORD_AUDIO permission needed.
///
/// Each FFT frame drives an [AnimationController] target: the controller
/// lerps toward the incoming RMS energy with a fast attack and slow decay
/// so rapid transients produce a sharp hit and a smooth tail.
///
/// The energy is mapped to [Transform.scale] in [1.0, 1.06].
///
/// ## Design token compliance
///
/// Audio-coupled animations must use [AfCurves.linear]. The controller
/// drives a raw linear interpolation — no easing curve on top.
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
  late final AnimationController _ctl;

  /// Maximum scale excursion at full energy. 0.06 = 106 % on loud beats.
  static const double _maxScaleDelta = 0.06;

  /// Lerp factor toward the incoming FFT value (attack).
  static const double _attackLerp = 0.55;

  /// Lerp factor back toward zero when no new frame arrives (decay).
  static const double _decayLerp = 0.12;

  double _target = 0.0;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_onTick);
    _ctl.repeat();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _onTick() {
    final current = _ctl.value;
    final lerp = _target > current ? _attackLerp : _decayLerp;
    _ctl.value = (current + (_target - current) * lerp).clamp(0.0, 1.0);
    // Decay target so the artwork returns to rest when the stream pauses.
    _target *= 0.85;
  }

  /// Compute RMS energy from the low-to-mid bands (indices 0..15 of 64).
  /// These cover roughly 20 Hz – 2 kHz — the range that drives perceived
  /// beat energy.
  double _rmsEnergy(Float32List bands) {
    if (bands.isEmpty) return 0.0;
    final end = (bands.length ~/ 4).clamp(1, bands.length);
    var sum = 0.0;
    for (var i = 0; i < end; i++) {
      sum += bands[i] * bands[i];
    }
    return (sum / end).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(fftSpectrumProvider, (_, next) {
      next.whenData((frame) {
        _target = _rmsEnergy(frame.bands);
      });
    });

    return AnimatedBuilder(
      animation: _ctl,
      builder: (context, child) {
        return Transform.scale(
          scale: 1.0 + _maxScaleDelta * _ctl.value,
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
