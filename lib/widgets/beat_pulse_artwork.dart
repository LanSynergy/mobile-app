import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import 'artwork.dart';

/// Album artwork that pulses with the music via the live FFT spectrum.
///
/// Maintains a smoothed energy value that tracks the RMS of the low-to-mid
/// FFT bands. The energy drives a [Transform.scale] between 1.0 and
/// [_maxScale]. A 60fps ticker lerps the current scale toward the target
/// so the animation is smooth without needing an [AnimationController]
/// per beat.
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

  /// Current smoothed scale value.
  double _scale = 1.0;

  /// Target scale set by the latest FFT frame.
  double _targetScale = 1.0;

  /// Maximum scale at full energy.
  static const double _maxScale = 1.08;

  /// How fast the scale rises toward the target.
  static const double _attackLerp = 0.6;

  /// How fast the scale falls back to 1.0.
  static const double _decayLerp = 0.15;

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_onTick);
    _ticker.repeat();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick() {
    if (!mounted) return;
    final lerp = _targetScale > _scale ? _attackLerp : _decayLerp;
    final next = _scale + (_targetScale - _scale) * lerp;
    if ((next - _scale).abs() > 0.0001) {
      setState(() => _scale = next);
    }
  }

  /// RMS of the first quarter of bands (bass + low-mid), with power curve.
  double _rms(Float32List bands) {
    if (bands.isEmpty) return 0.0;
    final end = (bands.length ~/ 4).clamp(1, bands.length);
    var sum = 0.0;
    for (var i = 0; i < end; i++) {
      sum += bands[i] * bands[i];
    }
    final rms = math.sqrt(sum / end).clamp(0.0, 1.0);
    // Power curve: quiet passages stay near 1.0 scale, only real beats pulse.
    return math.pow(rms, 2.5).toDouble().clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(fftSpectrumProvider, (prev, next) {
      next.whenData((frame) {
        final energy = _rms(frame.bands);
        // Map energy [0,1] directly to scale [1.0, _maxScale].
        _targetScale = 1.0 + energy * (_maxScale - 1.0);
      });
    });

    return Transform.scale(
      scale: _scale,
      child: Artwork(
        url: widget.imageUrl,
        size: widget.size,
        radius: widget.radius,
      ),
    );
  }
}
