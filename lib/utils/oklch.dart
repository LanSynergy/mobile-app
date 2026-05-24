import 'dart:math' as math;
import 'dart:ui';

/// OKLCH / sRGB conversion utilities and the spectral-accent extractor.
///
/// The extraction algorithm follows `aetherfin-design.md` §3.4:
///   1. Sample 16 pixels along a 4×4 grid of the artwork.
///   2. Convert to OKLCH.
///   3. Discard samples with C < 0.05 (greys) and L outside [15%, 85%].
///   4. Pick the highest-chroma remaining sample.
///   5. If none qualify, fall back to indigo.500.
///
/// `extractSpectral` accepts a list of [Color]s already sampled by the
/// caller (e.g. `palette_generator` or a manual decode) so this file
/// stays decoupled from image-loading.

class OklchColor { // 0–360 (degrees)
  const OklchColor(this.l, this.c, this.h);
  final double l; // 0–1
  final double c; // ~0–0.4
  final double h;

  Color toColor({int alpha = 255}) {
    final rgb = oklchToLinearSrgb(l, c, h);
    return Color.fromARGB(
      alpha,
      _gammaEncodeChannel(rgb[0]),
      _gammaEncodeChannel(rgb[1]),
      _gammaEncodeChannel(rgb[2]),
    );
  }

  OklchColor copyWith({double? l, double? c, double? h}) =>
      OklchColor(l ?? this.l, c ?? this.c, h ?? this.h);
}

/// Convert sRGB ([Color]) to OKLab → OKLCH.
OklchColor srgbToOklch(Color color) {
  final r = _gammaDecode((color.r * 255.0).round().clamp(0, 255) / 255);
  final g = _gammaDecode((color.g * 255.0).round().clamp(0, 255) / 255);
  final b = _gammaDecode((color.b * 255.0).round().clamp(0, 255) / 255);

  // Linear sRGB → LMS
  final l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b;
  final m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b;
  final s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b;

  final lc = math.pow(l, 1 / 3).toDouble();
  final mc = math.pow(m, 1 / 3).toDouble();
  final sc = math.pow(s, 1 / 3).toDouble();

  final ll = 0.2104542553 * lc + 0.7936177850 * mc - 0.0040720468 * sc;
  final aa = 1.9779984951 * lc - 2.4285922050 * mc + 0.4505937099 * sc;
  final bb = 0.0259040371 * lc + 0.7827717662 * mc - 0.8086757660 * sc;

  final chroma = math.sqrt(aa * aa + bb * bb);
  var hue = math.atan2(bb, aa) * 180 / math.pi;
  if (hue < 0) hue += 360;

  return OklchColor(ll, chroma, hue);
}

/// OKLCH → linear sRGB.
List<double> oklchToLinearSrgb(double l, double c, double h) {
  final hr = h * math.pi / 180;
  final a = c * math.cos(hr);
  final b = c * math.sin(hr);

  final lc = l + 0.3963377774 * a + 0.2158037573 * b;
  final mc = l - 0.1055613458 * a - 0.0638541728 * b;
  final sc = l - 0.0894841775 * a - 1.2914855480 * b;

  final lr = lc * lc * lc;
  final mr = mc * mc * mc;
  final sr = sc * sc * sc;

  final r = 4.0767416621 * lr - 3.3077115913 * mr + 0.2309699292 * sr;
  final g = -1.2684380046 * lr + 2.6097574011 * mr - 0.3413193965 * sr;
  final bb = -0.0041960863 * lr - 0.7034186147 * mr + 1.7076147010 * sr;

  return [r.clamp(0, 1), g.clamp(0, 1), bb.clamp(0, 1)];
}

double _gammaDecode(double v) =>
    v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();

double _gammaEncodeLinear(double v) =>
    v <= 0.0031308 ? 12.92 * v : 1.055 * math.pow(v, 1 / 2.4).toDouble() - 0.055;

int _gammaEncodeChannel(double v) =>
    (_gammaEncodeLinear(v.clamp(0, 1)) * 255).round().clamp(0, 255);

/// Spectral extraction.
///
/// Caller is expected to feed a pre-sampled list of [Color] from a 4×4 grid
/// over the artwork. We do the OKLCH classification + clamp here. Returns
/// `null` if nothing qualifies — the caller falls back to [Spectral.fallback].
({double l, double c, double h})? pickSpectralHue(Iterable<Color> samples) {
  final candidates = <OklchColor>[];
  for (final color in samples) {
    final oklch = srgbToOklch(color);
    if (oklch.c < 0.05) continue;            // grey
    if (oklch.l < 0.15) continue;            // near-black
    if (oklch.l > 0.85) continue;            // near-white
    candidates.add(oklch);
  }
  if (candidates.isEmpty) return null;
  candidates.sort((a, b) => b.c.compareTo(a.c));
  final pick = candidates.first;
  return (l: pick.l, c: pick.c, h: pick.h);
}

/// Build the three-color spectral triple from a hue:
/// energy: L clamped [0.55, 0.70], C ≥ 0.12.
/// shadow: L 0.22, C 0.08.
/// glow:   L 0.78, C 0.10 (paired with 24% opacity by the consumer).
({Color energy, Color shadow, Color glow}) buildSpectralTriple(double hue) {
  final energy = OklchColor(0.625, 0.16, hue).toColor();
  final shadow = OklchColor(0.22, 0.08, hue).toColor();
  final glow = OklchColor(0.78, 0.10, hue).toColor();
  return (energy: energy, shadow: shadow, glow: glow);
}

/// Picks the most pastel (lowest reasonable chroma) non-grey hue from the
/// palette samples. Prefers hues with chroma in [0.05, 0.12] and lightness
/// in [0.30, 0.80]. Falls back to [pickSpectralHue], then null.
({double l, double c, double h})? pickPastelHue(Iterable<Color> samples) {
  final candidates = <OklchColor>[];
  for (final color in samples) {
    final oklch = srgbToOklch(color);
    if (oklch.c < 0.03) continue;
    if (oklch.l < 0.20) continue;
    if (oklch.l > 0.85) continue;
    candidates.add(oklch);
  }
  if (candidates.isEmpty) return pickSpectralHue(samples);
  candidates.sort((a, b) => a.c.compareTo(b.c));
  final pick = candidates.first;
  return (l: pick.l, c: pick.c, h: pick.h);
}

/// Builds a pastel-optimised accent triple from a hue.
/// accent:  L=0.78, C=0.08 — soft pastel for buttons & active elements
/// muted:   L=0.55, C=0.10 — medium contrast for secondary surfaces
/// shadow:  L=0.20, C=0.05 — dark background gradient stop
({Color accent, Color muted, Color shadow}) buildPastelTriple(double hue) {
  final accent = OklchColor(0.78, 0.08, hue).toColor();
  final muted = OklchColor(0.55, 0.10, hue).toColor();
  final shadow = OklchColor(0.20, 0.05, hue).toColor();
  return (accent: accent, muted: muted, shadow: shadow);
}
