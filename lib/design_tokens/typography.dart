import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'colors.dart';

/// Aetherfin type scale.
///
/// Inter Variable for general copy, JetBrains Mono for technical readouts
/// (bitrate, codec, sample rate, hash). Both shipped via `google_fonts` so
/// they're loaded on first launch and cached on disk.
///
/// All sizes in dp (logical pixels). Line height is in dp (NOT unitless)
/// so it's predictable across devices.
abstract final class AfTypography {
  // ---------------------------------------------------------------------------
  // Public text styles — never hard-code these in widgets.
  // ---------------------------------------------------------------------------

  static TextStyle get display => _inter(
        fontSize: 32,
        height: 38 / 32,
        weight: FontWeight.w700,
        letterSpacing: -0.4,
      );

  static TextStyle get titleLarge => _inter(
        fontSize: 24,
        height: 30 / 24,
        weight: FontWeight.w600,
        letterSpacing: -0.2,
      );

  static TextStyle get titleMedium => _inter(
        fontSize: 20,
        height: 26 / 20,
        weight: FontWeight.w600,
        letterSpacing: -0.1,
      );

  static TextStyle get titleSmall => _inter(
        fontSize: 16,
        height: 22 / 16,
        weight: FontWeight.w600,
      );

  static TextStyle get bodyLarge => _inter(
        fontSize: 16,
        height: 24 / 16,
        weight: FontWeight.w400,
      );

  static TextStyle get bodyMedium => _inter(
        fontSize: 14,
        height: 20 / 14,
        weight: FontWeight.w400,
      );

  static TextStyle get bodySmall => _inter(
        fontSize: 12,
        height: 16 / 12,
        weight: FontWeight.w400,
        letterSpacing: 0.1,
      );

  /// Section header. UPPERCASE in widget; never bold; never indigo.
  static TextStyle get label => _inter(
        fontSize: 12,
        height: 16 / 12,
        weight: FontWeight.w600,
        letterSpacing: 0.4,
      );

  static TextStyle get caption => _inter(
        fontSize: 11,
        height: 14 / 11,
        weight: FontWeight.w400,
        letterSpacing: 0.2,
      );

  /// JetBrains Mono — bitrate, codec, hash readouts only.
  static TextStyle get mono => GoogleFonts.jetBrainsMono(
        fontSize: 11,
        height: 14 / 11,
        fontWeight: FontWeight.w500,
        color: AfColors.textPrimary,
      );

  // ---------------------------------------------------------------------------
  // Material 3 textTheme mapping.
  // ---------------------------------------------------------------------------

  static TextTheme get textTheme => TextTheme(
        displayLarge:  display.copyWith(color: AfColors.textPrimary),
        displayMedium: display.copyWith(color: AfColors.textPrimary),
        displaySmall:  titleLarge.copyWith(color: AfColors.textPrimary),
        headlineLarge: titleLarge.copyWith(color: AfColors.textPrimary),
        headlineMedium: titleLarge.copyWith(color: AfColors.textPrimary),
        headlineSmall: titleMedium.copyWith(color: AfColors.textPrimary),
        titleLarge:    titleLarge.copyWith(color: AfColors.textPrimary),
        titleMedium:   titleMedium.copyWith(color: AfColors.textPrimary),
        titleSmall:    titleSmall.copyWith(color: AfColors.textPrimary),
        bodyLarge:     bodyLarge.copyWith(color: AfColors.textPrimary),
        bodyMedium:    bodyMedium.copyWith(color: AfColors.textPrimary),
        bodySmall:     bodySmall.copyWith(color: AfColors.textSecondary),
        labelLarge:    label.copyWith(color: AfColors.textTertiary),
        labelMedium:   label.copyWith(color: AfColors.textTertiary),
        labelSmall:    caption.copyWith(color: AfColors.textTertiary),
      );

  // ---------------------------------------------------------------------------
  // Internal helper — Inter Variable.
  // ---------------------------------------------------------------------------
  static TextStyle _inter({
    required double fontSize,
    required double height,
    required FontWeight weight,
    double letterSpacing = 0,
  }) =>
      GoogleFonts.inter(
        fontSize: fontSize,
        height: height,
        fontWeight: weight,
        letterSpacing: letterSpacing,
        color: AfColors.textPrimary,
      );
}
