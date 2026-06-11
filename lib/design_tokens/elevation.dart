import 'package:flutter/widgets.dart';

/// Elevation tokens — Standardized shadow system.
///
/// Replaces hardcoded [BoxShadow] values scattered across widgets.
/// Each level provides a single shadow with increasing blur and offset.
///
/// For spectral/glow effects (Now Playing), use [spectralGlow].
abstract final class AfElevation {
  /// No shadow.
  static const List<BoxShadow> none = [];

  /// Subtle elevation — cards at rest, list items.
  static const List<BoxShadow> sm = [
    BoxShadow(color: Color(0x1A000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  /// Medium elevation — raised cards, floating elements.
  static const List<BoxShadow> md = [
    BoxShadow(color: Color(0x24000000), blurRadius: 8, offset: Offset(0, 2)),
  ];

  /// Large elevation — dialogs, bottom sheets.
  static const List<BoxShadow> lg = [
    BoxShadow(color: Color(0x33000000), blurRadius: 16, offset: Offset(0, 4)),
  ];

  /// Extra-large elevation — modals, overlays.
  static const List<BoxShadow> xl = [
    BoxShadow(color: Color(0x40000000), blurRadius: 24, offset: Offset(0, 8)),
  ];

  /// Spectral glow effect for Now Playing artwork and play button.
  ///
  /// Returns a list of 2 shadows with the given [color] scaled by [energy].
  /// [energy] should be between 0.0 and 1.0 (typically from spectral analysis).
  static List<BoxShadow> spectralGlow(Color color, double energy) {
    final opacity = energy.clamp(0.0, 1.0);
    return [
      BoxShadow(
        color: color.withValues(alpha: 0.3 * opacity),
        blurRadius: 24 + opacity * 8,
      ),
      BoxShadow(
        color: color.withValues(alpha: 0.15 * opacity),
        blurRadius: 48 + opacity * 8,
      ),
    ];
  }
}
