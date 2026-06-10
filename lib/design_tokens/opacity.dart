/// Opacity tokens — Standardized alpha values.
///
/// Replaces scattered magic numbers (0.5, 0.38, 0.12, etc.)
/// across the codebase. Semantic naming follows Material Design
/// state-based opacity conventions.
abstract final class AfOpacity {
  /// Disabled state — text and icons.
  static const double disabled = 0.38;

  /// Hover state — surface overlay.
  static const double hover = 0.08;

  /// Focus state — surface overlay.
  static const double focus = 0.12;

  /// Pressed state — surface overlay.
  static const double pressed = 0.16;

  /// Dragged state — surface overlay.
  static const double dragged = 0.24;

  /// Subtle overlay — very faint background tint.
  static const double subtle = 0.04;

  /// Light overlay — faint background tint.
  static const double light = 0.06;

  /// Medium overlay — moderate background tint.
  static const double medium = 0.27;

  /// Heavy overlay — strong background tint.
  static const double heavy = 0.55;
}
