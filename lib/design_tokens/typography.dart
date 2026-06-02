import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'colors.dart';

/// Aetherfin type scale — Dark Moody edition.
///
/// Playfair Display for headlines (editorial, warm personality).
/// Inter for body/UI (clean, proven, excellent readability).
/// JetBrains Mono for technical readouts only.
///
/// All sizes in dp (logical pixels). Line height is in dp (NOT unitless).
abstract final class AfTypography {
  // ---------------------------------------------------------------------------
  // Public text styles — never hard-code these in widgets.
  // ---------------------------------------------------------------------------

  static TextStyle get display => _playfair(
    fontSize: 36,
    height: 40 / 36,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
  );

  static TextStyle get titleLarge => _playfair(
    fontSize: 28,
    height: 34 / 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
  );

  static TextStyle get titleMedium => _inter(
    fontSize: 22,
    height: 28 / 22,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
  );

  static TextStyle get titleSmall => _inter(
    fontSize: 17,
    height: 22 / 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
  );

  static TextStyle get bodyLarge =>
      _inter(fontSize: 16, height: 24 / 16, fontWeight: FontWeight.w400);

  static TextStyle get bodyMedium =>
      _inter(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w400);

  static TextStyle get bodySmall => _inter(
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.1,
  );

  /// Section header. UPPERCASE in widget; never bold; never accent.
  static TextStyle get label => _inter(
    fontSize: 11,
    height: 14 / 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.6,
  );

  static TextStyle get caption => _inter(
    fontSize: 10,
    height: 13 / 10,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.2,
  );

  /// Between bodySmall(12) and bodyMedium(14).
  static TextStyle get bodyMediumSmall => _inter(
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.1,
  );

  /// Between titleMedium(22) and titleSmall(17).
  static TextStyle get titleMediumLarge => _inter(
    fontSize: 19,
    height: 24 / 19,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
  );

  /// Tiny label — overline, micro text, timestamps.
  static TextStyle get overline => _inter(
    fontSize: 9,
    height: 12 / 9,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.8,
  );

  /// JetBrains Mono — bitrate, codec, hash readouts only.
  static TextStyle get mono => GoogleFonts.jetBrainsMono(
    textStyle: const TextStyle(
      fontSize: 11,
      height: 14 / 11,
      fontWeight: FontWeight.w500,
      color: AfColors.textPrimary,
    ),
  );

  // ---------------------------------------------------------------------------
  // Material 3 textTheme mapping.
  // ---------------------------------------------------------------------------

  static TextTheme get textTheme => TextTheme(
    displayLarge: display.copyWith(color: AfColors.textPrimary),
    displayMedium: display.copyWith(color: AfColors.textPrimary),
    displaySmall: titleLarge.copyWith(color: AfColors.textPrimary),
    headlineLarge: titleLarge.copyWith(color: AfColors.textPrimary),
    headlineMedium: titleLarge.copyWith(color: AfColors.textPrimary),
    headlineSmall: titleMedium.copyWith(color: AfColors.textPrimary),
    titleLarge: titleLarge.copyWith(color: AfColors.textPrimary),
    titleMedium: titleMedium.copyWith(color: AfColors.textPrimary),
    titleSmall: titleSmall.copyWith(color: AfColors.textPrimary),
    bodyLarge: bodyLarge.copyWith(color: AfColors.textPrimary),
    bodyMedium: bodyMedium.copyWith(color: AfColors.textPrimary),
    bodySmall: bodySmall.copyWith(color: AfColors.textSecondary),
    labelLarge: label.copyWith(color: AfColors.textTertiary),
    labelMedium: label.copyWith(color: AfColors.textTertiary),
    labelSmall: caption.copyWith(color: AfColors.textTertiary),
  );

  // ---------------------------------------------------------------------------
  // Internal helpers — Playfair Display (serif) + Inter (sans).
  // ---------------------------------------------------------------------------

  /// Playfair Display — editorial serif for headlines/display.
  static TextStyle _playfair({
    required double fontSize,
    required double height,
    required FontWeight fontWeight,
    double letterSpacing = 0,
  }) => GoogleFonts.playfairDisplay(
    textStyle: TextStyle(
      fontSize: fontSize,
      height: height,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      color: AfColors.textPrimary,
    ),
  );

  /// Inter — clean sans for body/UI.
  static TextStyle _inter({
    required double fontSize,
    required double height,
    required FontWeight fontWeight,
    double letterSpacing = 0,
  }) => GoogleFonts.inter(
    textStyle: TextStyle(
      fontSize: fontSize,
      height: height,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      color: AfColors.textPrimary,
    ),
  );
}
