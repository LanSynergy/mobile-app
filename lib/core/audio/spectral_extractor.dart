import 'dart:ui' show Color;

import 'package:cached_network_image/cached_network_image.dart'
    show CachedNetworkImageProvider;
import 'package:palette_generator_master/palette_generator.dart';

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
///
/// We feed [PaletteGenerator] a [CachedNetworkImageProvider] (instead of
/// a plain `NetworkImage`) so the artwork bytes are reused from the same
/// on-disk cache that `cached_network_image` writes for the cover-art
/// widgets. Without this, every track change triggered a second HTTP
/// fetch of artwork that was already on disk.
class SpectralExtractor {
  /// In-memory cache of previously-extracted spectral palettes, keyed by
  /// `imageUrl`. Palette extraction decodes the artwork bitmap and runs
  /// the k-means-ish algorithm in `palette_generator` — ~30 ms per call
  /// on a mid-range Android. Track skip → spectral re-run → 30 ms hitch
  /// per skip without this cache. Headers don't go into the key because
  /// the same image bytes give the same palette regardless of which
  /// `Authorization` header fetched them.
  ///
  /// Bounded to 64 entries (~64 album covers' worth of palette data is
  /// a few KB total). Once full we evict the oldest entry — LinkedHashMap
  /// preserves insertion order, so the head is the least-recently-added.
  static const int _cacheLimit = 64;
  final Map<String, Spectral> _cache = <String, Spectral>{};

  Future<Spectral> fromImageUrl(
    String imageUrl, {
    Map<String, String>? headers,
  }) async {
    final cached = _cache[imageUrl];
    if (cached != null) return cached;
    final palette = await PaletteGenerator.fromImageProvider(
      CachedNetworkImageProvider(imageUrl, headers: headers),
      maximumColorCount: 16,
    );
    final samples = palette.colors.toList(growable: false);
    Spectral result;
    if (samples.isEmpty) {
      result = Spectral.fallback;
    } else {
      final hue = pickSpectralHue(samples);
      if (hue == null) {
        result = Spectral.fallback;
      } else {
        final triple = buildSpectralTriple(hue.h);
        result = Spectral(
          energy: triple.energy,
          shadow: triple.shadow,
          glow: triple.glow,
        );
      }
    }
    _cache[imageUrl] = result;
    if (_cache.length > _cacheLimit) {
      _cache.remove(_cache.keys.first);
    }
    return result;
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
