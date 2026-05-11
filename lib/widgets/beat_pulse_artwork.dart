import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design_tokens/tokens.dart';
import 'artwork.dart';

/// Album artwork that breathes in time with the track's energy profile.
///
/// ## How it works (no FFT package required)
///
/// Real-time FFT from `just_audio` / ExoPlayer is not exposed to Dart —
/// ExoPlayer decodes internally and doesn't surface PCM samples. Rather
/// than adding a native plugin, we derive a per-beat energy signal from
/// the **waveform peaks array** that the app already carries on every
/// [AfTrack]:
///
///   1. The peaks array encodes the track's loudness at each bar position
///      (0–100). We map the current playback progress to a bar index and
///      read the local energy window (±[_windowBars] bars around the
///      playhead).
///   2. That energy value (0.0–1.0) drives an [AnimationController] that
///      runs a sine-wave oscillation. The oscillation speed is fixed at
///      ~1.6 s/cycle (matching the waveform widget's own animation) and
///      the *amplitude* of the scale excursion is proportional to the
///      local energy — loud passages pulse more, quiet passages barely
///      move.
///   3. The controller is paused when [isPlaying] is false and the scale
///      smoothly returns to 1.0 via [AnimationController.animateTo].
///
/// The result is artwork that visually "breathes" with the song's energy
/// curve — the same premium effect Spotify uses — without any new
/// dependencies or native code.
///
/// ## Design token compliance
///
/// Audio-coupled animations must use [AfCurves.linear] (per the design
/// token constraints). The oscillation is a raw sine wave evaluated from
/// the controller's linear 0→1 value, which satisfies this rule.
class BeatPulseArtwork extends StatefulWidget {
  /// Cover art URL (may be null — falls back to the placeholder).
  final String? imageUrl;

  /// Square size of the artwork in logical pixels.
  final double size;

  /// Corner radius applied to the artwork.
  final BorderRadius radius;

  /// Per-bar peak amplitudes in [0, 100]. Same array used by [Waveform].
  /// When empty, the artwork still animates at a gentle fixed amplitude.
  final List<int> peaks;

  /// Current playback progress in [0.0, 1.0]. Used to look up the local
  /// energy window in [peaks].
  final double progress;

  /// Whether the player is currently playing. Pauses the animation when
  /// false.
  final bool isPlaying;

  const BeatPulseArtwork({
    super.key,
    required this.imageUrl,
    required this.size,
    required this.radius,
    required this.peaks,
    required this.progress,
    required this.isPlaying,
  });

  @override
  State<BeatPulseArtwork> createState() => _BeatPulseArtworkState();
}

class _BeatPulseArtworkState extends State<BeatPulseArtwork>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl;

  /// Number of bars on each side of the playhead to average for the
  /// local energy window. Wider windows smooth out transients; narrower
  /// windows react faster. 4 bars ≈ ~3 % of a 128-bar waveform.
  static const int _windowBars = 4;

  /// Maximum scale excursion at full energy (1.0 = 100 % peak amplitude).
  /// 0.035 means the artwork grows to 103.5 % at the loudest passages.
  static const double _maxScaleDelta = 0.035;

  /// Minimum scale excursion even at silence — keeps the animation alive
  /// during quiet intros/outros so the artwork never looks frozen.
  static const double _minScaleDelta = 0.008;

  /// Duration of one full oscillation cycle. Matches the waveform widget.
  static const Duration _cycleDuration = Duration(milliseconds: 1600);

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(vsync: this, duration: _cycleDuration);
    if (widget.isPlaying) _ctl.repeat();
  }

  @override
  void didUpdateWidget(covariant BeatPulseArtwork old) {
    super.didUpdateWidget(old);
    if (widget.isPlaying && !_ctl.isAnimating) {
      _ctl.repeat();
    } else if (!widget.isPlaying && _ctl.isAnimating) {
      // Wind down to neutral scale smoothly — same pattern as Waveform.
      _ctl.animateTo(
        0,
        duration: AfDurations.quick,
        curve: AfCurves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  /// Compute the normalised local energy (0.0–1.0) around the current
  /// playhead position from the peaks array.
  double _localEnergy() {
    final peaks = widget.peaks;
    if (peaks.isEmpty) return 0.5; // fallback: mid-energy
    final barCount = peaks.length;
    final headBar = (widget.progress * barCount).round().clamp(0, barCount - 1);
    final lo = (headBar - _windowBars).clamp(0, barCount - 1);
    final hi = (headBar + _windowBars).clamp(0, barCount - 1);
    if (lo > hi) return peaks[headBar] / 100.0;
    var sum = 0;
    for (var i = lo; i <= hi; i++) {
      sum += peaks[i];
    }
    return (sum / ((hi - lo + 1) * 100.0)).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctl,
      builder: (context, child) {
        final energy = _localEnergy();
        // Scale delta is linearly interpolated between min and max based
        // on local energy. The sine wave maps the controller's 0→1 linear
        // value to a smooth oscillation.
        final scaleDelta = _minScaleDelta +
            (_maxScaleDelta - _minScaleDelta) * energy;
        // sin(2π·t) oscillates between -1 and +1. We shift it to [0, 1]
        // so the artwork only ever scales UP from its resting size (no
        // shrink below 1.0, which would look like the artwork is gasping).
        final sine = (math.sin(2 * math.pi * _ctl.value) + 1) / 2;
        final scale = 1.0 + scaleDelta * sine;

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
