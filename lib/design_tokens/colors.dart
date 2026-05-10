import 'package:flutter/material.dart';

/// Aetherfin color tokens.
///
/// Derived from the OKLCH-based design system:
///   - 12-step indigo primary scale (hue 275°)
///   - 6-step surface depth (low-chroma indigo-tinted neutrals)
///   - Dedicated text scale on the Nocturne canvas
///   - Five semantic tokens
///
/// The runtime-extracted spectral accent lives in [Spectral] and is
/// exposed via the `spectralProvider` Riverpod family — never embed
/// spectral values here.
abstract final class AfColors {
  // ---------------------------------------------------------------------------
  // Indigo primary scale (hue 275°)
  // ---------------------------------------------------------------------------
  static const indigo50   = Color(0xFFF5F4FE);
  static const indigo100  = Color(0xFFE8E5FB);
  static const indigo200  = Color(0xFFCDC6F4);
  static const indigo300  = Color(0xFFA89DEC);
  static const indigo400  = Color(0xFF8276E0);
  static const indigo500  = Color(0xFF6657D7);
  static const indigo600  = Color(0xFF5644C9); // Primary action
  static const indigo700  = Color(0xFF453AA1); // Pressed
  static const indigo800  = Color(0xFF332C7A); // Hero card gradient base
  static const indigo900  = Color(0xFF251F58); // Section-tinted surfaces
  static const indigo950  = Color(0xFF181439); // Deep tint for sheets
  static const indigo1000 = Color(0xFF0E0B23); // Reserved emergency depth

  // ---------------------------------------------------------------------------
  // Surface scale — Nocturne (dark)
  // Depth via tone, NOT blur, NOT shadow-as-decoration.
  // ---------------------------------------------------------------------------
  static const surfaceCanvas = Color(0xFF0B0B14);
  static const surfaceLow    = Color(0xFF101020);
  static const surfaceBase   = Color(0xFF15152A);
  static const surfaceRaised = Color(0xFF1B1B36);
  static const surfaceHigh   = Color(0xFF232347);
  static const surfaceMax    = Color(0xFF2C2C57);
  static const surfaceScrim  = Color(0x8F000000);

  // ---------------------------------------------------------------------------
  // Foreground (text on Nocturne canvas)
  // APCA targets: body Lc ≥ 60, secondary ≥ 45, tertiary ≥ 30.
  // ---------------------------------------------------------------------------
  static const textPrimary   = Color(0xFFF2F1F8);
  static const textSecondary = Color(0xFFBFBED0);
  static const textTertiary  = Color(0xFF8C8AA3);
  static const textDisabled  = Color(0xFF5E5C72);
  static const textOnPrimary = Color(0xFFF8F7FB);
  static const textLink      = Color(0xFF9788E6);

  // ---------------------------------------------------------------------------
  // Semantic
  // ---------------------------------------------------------------------------
  static const semanticSuccess = Color(0xFF5DCB87);
  static const semanticWarning = Color(0xFFD7B852);
  static const semanticError   = Color(0xFFE26A53);
  static const semanticInfo    = Color(0xFF6CB1D9);
  static const semanticOffline = Color(0xFF90909E);
}

/// Spectral accent triple, extracted from current artwork at runtime.
///
/// Three tokens for three uses — never collapse into a single color.
@immutable
class Spectral {
  final Color energy; // waveform peak fill, lyric highlight, heart glow
  final Color shadow; // Now Playing bottom gradient stop
  final Color glow;   // play-button outer glow on Now Playing

  const Spectral({
    required this.energy,
    required this.shadow,
    required this.glow,
  });

  /// Default — used until artwork is parsed, on data-saver, on cellular,
  /// or whenever extraction can't surface a chromatic sample.
  static const fallback = Spectral(
    energy: AfColors.indigo500,
    shadow: AfColors.indigo900,
    glow: AfColors.indigo300,
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
