import 'package:flutter/animation.dart';

/// Aetherfin motion easing curves — Dark Moody edition.
///
/// FIVE curves only. If you need a sixth, the design system has the
/// right one — search again.
///
/// Audio-coupled animations (waveform, progress ring, lyric scroll) use
/// `linear` ALWAYS. Easing audio time lies about playback position.
abstract final class AfCurves {
  /// `cubic-bezier(0.16, 1, 0.3, 1)` — smooth deceleration.
  /// Page transitions, tab switches.
  static const Curve easeStandard = Cubic(0.16, 1, 0.3, 1);

  /// `cubic-bezier(0.22, 1, 0.36, 1)` — dramatic spatial moves.
  /// Mini-player → Now Playing expand, hero artwork handoff.
  static const Curve easeEmphasized = Cubic(0.22, 1, 0.36, 1);

  /// `cubic-bezier(0.2, 0.8, 0.2, 1)` — iOS-like spring deceleration.
  /// Bottom sheet open, dialog open, modal present.
  static const Curve springPresent = Cubic(0.2, 0.8, 0.2, 1);

  /// `cubic-bezier(0.5, 0, 0.75, 0)` — iOS-like spring dismiss.
  /// Bottom sheet close, dialog close, modal dismiss.
  static const Curve springDismiss = Cubic(0.5, 0, 0.75, 0);

  /// `cubic-bezier(0, 0, 0.2, 1)` — entries.
  static const Curve easeOut = Curves.easeOut;

  /// `cubic-bezier(0.5, 0, 1, 1)` — exits.
  static const Curve easeIn = Curves.easeIn;

  /// `linear` — audio-coupled only.
  /// Waveform fill, progress ring sweep, lyric scroll position.
  static const Curve linear = Curves.linear;
}

/// Aetherfin motion duration tiers — Dark Moody edition.
///
/// iOS-like feel: heavier, springier, more deliberate than stock Material.
/// NEVER use raw ms values — always reference these tiers.
abstract final class AfDurations {
  /// 80 ms — color/opacity micro-feedback (icon press tint).
  static const Duration instant = Duration(milliseconds: 80);

  /// 180 ms — small element transitions, hover states, heart pop.
  static const Duration quick = Duration(milliseconds: 180);

  /// 350 ms — default page/sheet transitions, dialog open.
  static const Duration standard = Duration(milliseconds: 350);

  /// 500 ms — Now Playing expand, hero handoff, sheet open.
  static const Duration expressive = Duration(milliseconds: 500);

  /// 700 ms — onboarding intro animation only.
  static const Duration long = Duration(milliseconds: 700);
}

/// Stagger conventions for grid / list reveals.
abstract final class AfStagger {
  /// 40 ms per item. Top-left → bottom-right (grids) or top → bottom (lists).
  static const Duration perItem = Duration(milliseconds: 40);

  /// 8 items max — items 9+ all run at the same offset as item 8.
  static const int maxStaggered = 8;

  /// Per-item animation duration (fade + 12dp translate).
  static const Duration itemDuration = AfDurations.quick;
}
