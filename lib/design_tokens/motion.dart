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
  /// Page transitions, tile presses, sheet opens, tab switches.
  static const Curve easeStandard = Cubic(0.16, 1, 0.3, 1);

  /// `cubic-bezier(0.22, 1, 0.36, 1)` — dramatic spatial moves.
  /// Mini-player → Now Playing expand, hero artwork handoff.
  static const Curve easeEmphasized = Cubic(0.22, 1, 0.36, 1);

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
/// FIVE tiers only. Never 200, never 300, never 500.
abstract final class AfDurations {
  /// 60 ms — color/opacity micro-feedback (icon press tint).
  static const Duration instant = Duration(milliseconds: 60);

  /// 120 ms — small element transitions, hover states, heart pop.
  static const Duration quick = Duration(milliseconds: 120);

  /// 200 ms — default page/sheet transitions.
  static const Duration standard = Duration(milliseconds: 200);

  /// 350 ms — Now Playing expand, hero handoff.
  static const Duration expressive = Duration(milliseconds: 350);

  /// 500 ms — onboarding intro animation only.
  static const Duration long = Duration(milliseconds: 500);
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
