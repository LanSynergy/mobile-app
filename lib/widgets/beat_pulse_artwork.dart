import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import 'artwork.dart';

/// Album artwork that pulses in real-time sync with the audio output.
///
/// Uses [fftSpectrumProvider] (mpv_audio_kit's post-DSP FFT stream) to
/// drive a [Transform.scale]. The scale is animated with a short
/// spring-like tween so each beat hit is smooth rather than a hard jump.
///
/// The AnimationController only runs when there is actual FFT energy —
/// it stays idle when paused or when the screen is not visible, avoiding
/// the 60fps drain that caused the mini-player tap freeze.
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
  late final Animation<double> _scaleAnim;

  /// Maximum scale at full energy. 1.08 = artwork grows to 108% on loud beats.
  static const double _maxScale = 1.08;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      reverseDuration: const Duration(milliseconds: 400),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: _maxScale).animate(
      CurvedAnimation(parent: _ctl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  /// Compute RMS energy from the low-to-mid bands (first quarter of 64 bands).
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
    // Listen to FFT frames and drive the controller forward/reverse
    // based on energy. No continuous tick loop — only animates on beat.
    ref.listen(fftSpectrumProvider, (prev, next) {
      next.whenData((frame) {
        final energy = _rmsEnergy(frame.bands);
        // Scale down so the artwork spends most of its time near rest
        // and only visibly pulses on actual loud beats.
        final scaled = (energy * 0.5).clamp(0.0, 1.0);
        if (scaled > 0.05) {
          final target = ((scaled - 0.05) / 0.95).clamp(0.0, 1.0);
          _ctl.animateTo(target, duration: const Duration(milliseconds: 60));
        } else {
          if (_ctl.value > 0.01) {
            _ctl.animateTo(0.0, duration: const Duration(milliseconds: 300));
          }
        }
      });
    });

    return AnimatedBuilder(
      animation: _scaleAnim,
      builder: (context, child) => Transform.scale(
        scale: _scaleAnim.value,
        child: child,
      ),
      child: Artwork(
        url: widget.imageUrl,
        size: widget.size,
        radius: widget.radius,
      ),
    );
  }
}
