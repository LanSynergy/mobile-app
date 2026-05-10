import 'dart:ui' show Color;

import 'package:flutter/material.dart' show NetworkImage;
import 'package:palette_generator/palette_generator.dart';

import '../../design_tokens/colors.dart';
import '../../utils/oklch.dart';

/// Extracts the spectral accent triple from an artwork URL.
///
/// Sampling strategy:
///   1. Use `palette_generator` to grab up to 16 dominant colors over the
///      whole image (it does the down-sampling for us).
///   2. Pass those colors through the OKLCH classifier in `utils/oklch.dart`
///      (discards greys, near-black, near-white).
///   3. Pick the highest-chroma remaining sample.
///   4. If no sample qualifies, fall back to indigo.500.
class SpectralExtractor {
  Future<Spectral> fromImageUrl(String imageUrl) async {
    final palette = await PaletteGenerator.fromImageProvider(
      NetworkImage(imageUrl),
      maximumColorCount: 16,
    );
    final samples = palette.colors.toList(growable: false);
    if (samples.isEmpty) return Spectral.fallback;
    final hue = pickSpectralHue(samples);
    if (hue == null) return Spectral.fallback;
    final triple = buildSpectralTriple(hue.h);
    return Spectral(
      energy: triple.energy,
      shadow: triple.shadow,
      glow: triple.glow,
    );
  }

  /// Synchronous fallback used in widget tests / preview mode.
  Spectral fromColors(Iterable<Color> samples) {
    final hue = pickSpectralHue(samples);
    if (hue == null) return Spectral.fallback;
    final triple = buildSpectralTriple(hue.h);
    return Spectral(
      energy: triple.energy,
      shadow: triple.shadow,
      glow: triple.glow,
    );
  }
}
