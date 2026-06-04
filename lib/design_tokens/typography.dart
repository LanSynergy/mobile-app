import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'colors.dart';

/// Aetherfin type scale — Dark Moody edition.
///
/// Outfit for headlines/display (geometric, modern, premium).
/// DM Sans for body/UI (clean, characterful, excellent readability).
/// JetBrains Mono for technical readouts only.
///
/// All sizes in dp (logical pixels). Line height is in dp (NOT unitless).
abstract final class AfTypography {
  // ---------------------------------------------------------------------------
  // Public text styles — never hard-code these in widgets.
  // ---------------------------------------------------------------------------

  static TextStyle get display => _outfit(
    fontSize: 36,
    height: 40 / 36,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
  );

  static TextStyle get titleExtraLarge => _outfit(
    fontSize: 32,
    height: 38 / 32,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
  );

  static TextStyle get titleLarge => _outfit(
    fontSize: 28,
    height: 34 / 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
  );

  static TextStyle get titleMedium => _dmSans(
    fontSize: 22,
    height: 28 / 22,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
  );

  static TextStyle get titleSmall => _dmSans(
    fontSize: 17,
    height: 22 / 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
  );

  static TextStyle get bodyLarge =>
      _dmSans(fontSize: 16, height: 24 / 16, fontWeight: FontWeight.w400);

  static TextStyle get bodyMedium =>
      _dmSans(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w400);

  static TextStyle get bodySmall => _dmSans(
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.1,
  );

  /// Section header. UPPERCASE in widget; never bold; never accent.
  static TextStyle get label => _dmSans(
    fontSize: 11,
    height: 14 / 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.6,
  );

  static TextStyle get caption => _dmSans(
    fontSize: 10,
    height: 13 / 10,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.2,
  );

  /// Between bodySmall(12) and bodyMedium(14).
  static TextStyle get bodyMediumSmall => _dmSans(
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.1,
  );

  /// Between titleMedium(22) and titleSmall(17).
  static TextStyle get titleMediumLarge => _dmSans(
    fontSize: 19,
    height: 24 / 19,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
  );

  /// Tiny label — overline, micro text, timestamps.
  static TextStyle get overline => _dmSans(
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

  /// JetBrains Mono — micro stat badges (smaller than mono).
  static TextStyle get monoSmall => GoogleFonts.jetBrainsMono(
    textStyle: const TextStyle(
      fontSize: 10,
      height: 13 / 10,
      fontWeight: FontWeight.w500,
      color: AfColors.textPrimary,
    ),
  );

  /// Large initials for profile avatar.
  static TextStyle get avatarInitials => _outfit(
    fontSize: 32,
    height: 38 / 32,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
  );

  // ---------------------------------------------------------------------------
  // Shared button styles.
  // ---------------------------------------------------------------------------

  /// OutlinedButton style for action rows (Play All / Shuffle / Radio).
  static ButtonStyle get outlinedAction => OutlinedButton.styleFrom(
    side: const BorderSide(color: AfColors.accentPrimary, width: 1.5),
    foregroundColor: AfColors.accentPrimary,
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
    labelLarge: label.copyWith(color: AfColors.textSecondary),
    labelMedium: label.copyWith(color: AfColors.textSecondary),
    labelSmall: caption.copyWith(color: AfColors.textTertiary),
  );

  // ---------------------------------------------------------------------------
  // Internal helpers — Outfit (geometric display) + DM Sans (body/UI).
  // ---------------------------------------------------------------------------

  /// Outfit — geometric sans for headlines/display.
  static TextStyle _outfit({
    required double fontSize,
    required double height,
    required FontWeight fontWeight,
    double letterSpacing = 0,
  }) => GoogleFonts.outfit(
    textStyle: TextStyle(
      fontSize: fontSize,
      height: height,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      color: AfColors.textPrimary,
    ),
  );

  /// DM Sans — clean sans for body/UI.
  static TextStyle _dmSans({
    required double fontSize,
    required double height,
    required FontWeight fontWeight,
    double letterSpacing = 0,
  }) => GoogleFonts.dmSans(
    textStyle: TextStyle(
      fontSize: fontSize,
      height: height,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      color: AfColors.textPrimary,
    ),
  );
}
