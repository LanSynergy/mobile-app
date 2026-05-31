import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/artwork.dart';

class ReactiveArtwork extends ConsumerStatefulWidget {
  const ReactiveArtwork({super.key, required this.track});

  final AfTrack track;

  @override
  ConsumerState<ReactiveArtwork> createState() => _ReactiveArtworkState();
}

class _ReactiveArtworkState extends ConsumerState<ReactiveArtwork>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<double> _scale = ValueNotifier(1.0);
  late final AnimationController _ticker;
  Timer? _silenceTimer;

  double _bassAverage = 0.0;
  double _prevBass = 0.0;
  int _cooldown = 0;

  @override
  void initState() {
    super.initState();
    _ticker =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 16),
        )..addListener(() {
          if (_scale.value > 1.001) {
            _scale.value = 1.0 + (_scale.value - 1.0) * 0.85;
          } else {
            _scale.value = 1.0;
            _ticker.stop();
          }
        });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Listen through shared fftFrameProvider instead of direct spectrumStream
    // subscription — both visualizer and artwork pulse share one mpv stream.
    ref.listen(fftFrameProvider, (prev, next) {
      if (!mounted) return;
      if (!ref.read(artworkPulseEnabledProvider)) return;
      final frame = next.valueOrNull;
      if (frame == null || frame.bands.isEmpty) return;
      _silenceTimer?.cancel();

      final int hi = frame.bands.length < 7 ? frame.bands.length : 7;
      double rawBass = 0.0;
      for (var i = 1; i < hi; i++) {
        final v = frame.bands[i].abs();
        if (v > rawBass) rawBass = v;
      }

      final delta = rawBass - _prevBass;
      _prevBass = rawBass;

      _bassAverage +=
          (rawBass - _bassAverage) * (rawBass < _bassAverage ? 0.12 : 0.03);

      if (_cooldown > 0) {
        _cooldown--;
      } else if ((rawBass > _bassAverage * 1.12 || delta > 0.04) &&
          rawBass > 0.015) {
        _scale.value = 1.06;
        _cooldown = 15;
        if (!_ticker.isAnimating) _ticker.repeat();
      }

      _silenceTimer?.cancel();
      if (mounted) {
        _silenceTimer = Timer(const Duration(milliseconds: 300), () {
          if (mounted) {
            _bassAverage = 0.0;
            _prevBass = 0.0;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _silenceTimer?.cancel();
    _ticker.dispose();
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spectral = ref.watch(currentSpectralProvider);
    final pulseEnabled = ref.watch(artworkPulseEnabledProvider);
    final artworkUri = ref.watch(currentArtworkUriProvider);

    final artworkWidget = Center(
      child: Hero(
        tag: 'now-playing-artwork',
        child: Container(
          decoration: BoxDecoration(
            borderRadius: AfRadii.borderLg,
            boxShadow: [
              BoxShadow(
                color: spectral.glow.withValues(alpha: 0.30),
                blurRadius: 40,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Artwork(
            url: artworkUri?.toString() ?? widget.track.imageUrl,
            size: 300,
            radius: AfRadii.borderLg,
          ),
        ),
      ),
    );

    if (!pulseEnabled) return artworkWidget;

    return ValueListenableBuilder<double>(
      valueListenable: _scale,
      builder: (context, scaleVal, child) => Transform.scale(
        scale: scaleVal,
        alignment: Alignment.center,
        child: child,
      ),
      child: artworkWidget,
    );
  }
}
