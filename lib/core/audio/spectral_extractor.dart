import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:cached_network_image/cached_network_image.dart'
    show CachedNetworkImageProvider;
import 'package:flutter/painting.dart' show FileImage, ImageProvider;
import 'package:palette_generator_master/palette_generator_master.dart';

import '../../design_tokens/colors.dart';
import '../../utils/log.dart';
import '../../utils/oklch.dart';
import '../../utils/url.dart';

/// Extracts the spectral accent triple from an artwork URL.
///
/// Sampling strategy:
///   1. Use `PaletteGeneratorMaster` to get 16 quantized colors with
///      population counts, plus pre-computed targets (vibrant, muted, etc.)
///   2. Pick the best color using a composite score of chroma × population
///      weight — not just highest chroma (which picks tiny accent pixels).
///   3. Build the triple from the actual sampled L/C/H, not hardcoded values.
///   4. If no sample qualifies, fall back to the default spectral.
class SpectralExtractor {
  static const int _cacheLimit = 64;
  final Map<String, Spectral> _cache = <String, Spectral>{};
  final Map<String, Future<Spectral>> _inFlight = {};

  Future<Spectral> fromImageUrl(
    String imageUrl, {
    Map<String, String>? headers,
  }) async {
    final key = stableImageCacheKey(imageUrl);

    final pending = _inFlight[key];
    if (pending != null) return pending;

    final future = _extract(key, imageUrl, headers);
    _inFlight[key] = future;
    try {
      return await future;
    } finally {
      // ignore: unawaited_futures
      _inFlight.remove(key);
    }
  }

  Future<Spectral> _extract(
    String key,
    String imageUrl,
    Map<String, String>? headers,
  ) async {
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return cached;
    }

    try {
      final ImageProvider provider;
      if (imageUrl.startsWith('file://')) {
        provider = FileImage(File(imageUrl.substring('file://'.length)));
      } else {
        provider = CachedNetworkImageProvider(
          imageUrl,
          headers: headers,
          cacheKey: key,
        );
      }
      final palette = await PaletteGeneratorMaster.fromImageProvider(
        provider,
        maximumColorCount: 16,
      );
      final result = _pickBestSpectral(palette);
      _cache[key] = result;
      if (_cache.length > _cacheLimit) {
        _cache.remove(_cache.keys.first);
      }
      return result;
    } catch (e, stack) {
      afLog(
        'spectral',
        'palette extraction failed for ${redactSensitiveQueryParams(imageUrl)}',
        error: e,
        stackTrace: stack,
      );
      return Spectral.fallback;
    }
  }

  /// Picks the best spectral triple from the palette.
  ///
  /// Strategy priority:
  ///   1. Vibrant color from the palette (if it has decent population)
  ///   2. Highest chroma × population score across all quantized colors
  ///   3. Fallback to default
  Spectral _pickBestSpectral(PaletteGeneratorMaster palette) {
    final pColors = palette.paletteColors;
    if (pColors.isEmpty) return Spectral.fallback;

    final totalPopulation = pColors.fold<int>(
      0,
      (sum, c) => sum + c.population,
    );
    if (totalPopulation == 0) return Spectral.fallback;

    // ── Strategy 1: Use the palette's vibrant target if it exists ──
    final vibrant = palette.vibrantColor;
    if (vibrant != null) {
      final oklch = srgbToOklch(vibrant.color);
      if (oklch.c >= 0.05 && oklch.l >= 0.15 && oklch.l <= 0.85) {
        return _buildFromSample(oklch);
      }
    }

    // ── Strategy 2: Score all quantized colors ──
    final candidates = <_ScoredColor>[];
    for (final pc in pColors) {
      final oklch = srgbToOklch(pc.color);
      if (oklch.c < 0.04) continue; // grey
      if (oklch.l < 0.12 || oklch.l > 0.88) continue; // near-black/white
      // Score: chroma-weighted by population share.
      // sqrt(population) to avoid a single dominant-but-dull color winning.
      final popShare = pc.population / totalPopulation;
      final score = oklch.c * math.sqrt(popShare);
      candidates.add(_ScoredColor(oklch, score));
    }

    if (candidates.isEmpty) return Spectral.fallback;
    candidates.sort((a, b) => b.score.compareTo(a.score));
    final best = candidates.first;

    return _buildFromSample(best.oklch);
  }

  /// Builds the full spectral palette from an actual OKLCH sample.
  ///
  /// All variants share the same hue — they differ only in lightness
  /// and chroma, so the palette always feels cohesive.
  Spectral _buildFromSample(OklchColor sample) {
    final h = sample.h;
    final c = sample.c;

    // Energy: boost chroma, clamp lightness for contrast.
    final energyL = sample.l.clamp(0.45, 0.72);
    final energyC = math.max(c, 0.10);
    final energy = OklchColor(energyL, energyC, h).toColor();

    // Shadow: same hue, very dark, low chroma.
    final shadow = OklchColor(0.18, c * 0.35, h).toColor();

    // Glow: same hue, light, moderate chroma.
    final glowL = math.min(sample.l + 0.15, 0.85);
    final glow = OklchColor(glowL, c * 0.55, h).toColor();

    // Primary: same as energy — main UI accent for theme.
    final primary = energy;

    // Secondary: hue-shifted +20°, slightly lower chroma.
    final secondaryHue = (h + 20) % 360;
    final secondary = OklchColor(
      energyL.clamp(0.40, 0.65),
      math.max(energyC * 0.75, 0.08),
      secondaryHue,
    ).toColor();

    // Muted: same hue, low chroma, medium lightness.
    final muted = OklchColor(0.45, c * 0.30, h).toColor();

    // Link: same hue, lighter than primary, moderate chroma.
    final linkL = math.min(energyL + 0.12, 0.78);
    final link = OklchColor(linkL, energyC * 0.85, h).toColor();

    // Warning: same hue as energy (replaces static semanticWarning).
    final warning = energy;

    return Spectral(
      energy: energy,
      shadow: shadow,
      glow: glow,
      primary: primary,
      secondary: secondary,
      muted: muted,
      link: link,
      warning: warning,
    );
  }

  /// Synchronous fallback used in widget tests / preview mode.
  Spectral fromColors(Iterable<Color> samples) {
    final hue = pickSpectralHue(samples);
    if (hue == null) return Spectral.fallback;
    return _buildFromSample(OklchColor(hue.l, hue.c, hue.h));
  }
}

class _ScoredColor {
  const _ScoredColor(this.oklch, this.score);
  final OklchColor oklch;
  final double score;
}
