import 'package:flutter/material.dart';

/// Aetherfin color tokens — Dark Moody palette.
///
/// Deep blacks, warm amber/terracotta accents, album-art-driven atmosphere.
/// The runtime-extracted spectral accent lives in [Spectral] and is
/// exposed via the `spectralProvider` Riverpod family — never embed
/// spectral values here.
abstract final class AfColors {
  // ---------------------------------------------------------------------------
  // Surface scale — True blacks, no tint
  // Depth via tone, NOT blur, NOT shadow-as-decoration.
  //
  // Spaced ≥12 per channel so any 2-stop gradient between adjacent tokens
  // produces smooth transitions on 8-bit displays without extra stops.
  // ---------------------------------------------------------------------------
  static const surfaceCanvas = Color(0xFF0A0A0A);
  static const surfaceLow = Color(0xFF161616);
  static const surfaceBase = Color(0xFF222222);
  static const surfaceRaised = Color(0xFF2E2E2E);
  static const surfaceHigh = Color(0xFF3A3A3A);
  static const surfaceMax = Color(0xFF464646);
  static const surfaceScrim = Color(0xCC000000);

  // ---------------------------------------------------------------------------
  // Foreground (text on dark canvas)
  // APCA targets: body Lc ≥ 60, secondary ≥ 45, tertiary ≥ 30.
  // ---------------------------------------------------------------------------
  static const textPrimary = Color(0xFFF5F0EB);
  static const textSecondary = Color(0xFFA89F94);
  static const textTertiary = Color(0xFF6B6560);
  static const textDisabled = Color(0xFF4A4540);
  static const textOnPrimary = Color(0xFFFAF7F4);
  static const textLink = Color(0xFFD4A574);

  // ---------------------------------------------------------------------------
  // Accent — Warm amber/terracotta
  // ---------------------------------------------------------------------------
  static const accentPrimary = Color(0xFFD4A574); // Warm amber
  static const accentSecondary = Color(0xFFC86E4B); // Terracotta
  static const accentMuted = Color(0xFF8B7355); // Muted gold

  // Indigo scale kept for spectral fallback only
  static const indigo300 = Color(0xFFA89DEC);
  static const indigo400 = Color(0xFF8276E0);
  static const indigo500 = Color(0xFF6657D7);
  static const indigo600 = Color(0xFF5644C9);
  static const indigo900 = Color(0xFF251F58);

  // ---------------------------------------------------------------------------
  // Semantic — Warm-tinted
  // ---------------------------------------------------------------------------
  static const semanticSuccess = Color(0xFF7DB88F);
  static const semanticWarning = Color(0xFFD4A574);
  static const semanticError = Color(0xFFD4735A);
  static const semanticInfo = Color(0xFF7BA3B8);
  static const semanticOffline = Color(0xFF706A64);

  // ---------------------------------------------------------------------------
  // Glass morphism — translucent white overlays for frosted surfaces.
  // Used by mini-player, now-playing top bar, cast button, track rows.
  // ---------------------------------------------------------------------------
  static const glassFillSubtle = Color(0x0AFFFFFF); // white @ 4%
  static const glassFill = Color(0x0FFFFFFF); // white @ 6%
  static const glassFillStrong = Color(0x14FFFFFF); // white @ 8%
  static const glassBorder = Color(0x0FFFFFFF); // white @ 6%
  static const glassBorderStrong = Color(0x14FFFFFF); // white @ 8%
  static const glassBorderEmphasis = Color(0x1AFFFFFF); // white @ 10%
}

/// Spectral accent triple, extracted from current artwork at runtime.
///
/// Three tokens for three uses — never collapse into a single color.
@immutable
class Spectral {
  const Spectral({
    required this.energy,
    required this.shadow,
    required this.glow,
  });
  final Color energy; // waveform peak fill, lyric highlight, heart glow
  final Color shadow; // Now Playing bottom gradient stop
  final Color glow; // play-button outer glow on Now Playing

  /// Default — used until artwork is parsed.
  static const fallback = Spectral(
    energy: Color(0xFFD4A574), // accentPrimary
    shadow: Color(0xFF1A1410),
    glow: Color(0xFFE8C9A0),
  );

  @override
  bool operator ==(Object other) =>
      other is Spectral &&
      other.energy == energy &&
      other.shadow == shadow &&
      other.glow == glow;

  @override
  int get hashCode => Object.hash(energy, shadow, glow);
}
