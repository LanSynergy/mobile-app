# Continuity Ledger

## 2026-05-27 — Optimize slow unit tests with fakeAsync
*Goal:* Speed up the unit test suite by eliminating real-world sleeps/delays (9s, 5s, 2s) using fakeAsync.
*Commits:* f90cd37
*Key decisions:*
- Refactored `playlist_undo_buffer_test.dart` and `audio_device_manager_test.dart` to run under `fakeAsync`.
- Replaced `Future.delayed` with synchronous `async.elapse()`, lowering run time from 50s+ to ~27s.

## 2026-05-26 — Native Lucide-based Standard Notification Actions for Shuffle and Repeat
*Goal:* Resolve issue where shuffle and repeat controls do not appear on Android 13+ / Samsung One UI media notifications.
*Commits:* 69a3e00
*Key decisions:*
- Avoided using `PlaybackStateCompat.CustomAction` (which displays inconsistently across various device models/skins).
- Added shuffle and repeat as standard `NotificationCompat.Action` buttons directly to `NotificationCompat.Builder` to construct a consistent 5-button layout (`[Shuffle] [Previous] [Play/Pause] [Next] [Repeat]`).
- Kept the compact view (lock screen / collapsed drawer) to `Previous`, `Play/Pause`, and `Next` using `.setShowActionsInCompactView(1, 2, 3)`.
- Created 5 custom Vector Drawables under `android/app/src/main/res/drawable/` using the exact stroke-based SVG paths from the project's Lucide icons.
- Added custom underline indicator bars to active icons (`ic_shuffle_on`, `ic_repeat_all`, `ic_repeat_one`) and a diagonal slash to `ic_repeat_off` to ensure states are easily readable when tinted by the system UI.
- Wired click events to trigger service broadcast intents that toggle the shuffle/loop state in Dart via the method channel.

## 2026-05-26 — Fix 433px RenderFlex overflow in _MarqueeText
*Goal:* Prevent overflow error when marquee title text scrolls beyond parent column's width constraint
*Commits:* 25d3ad2
*Key decisions:*
- Wrapped the repeating Row (text + gap + text) in an `OverflowBox` to allow the animated marquee content to exceed the parent's width during scroll animation.
- Still pending: the 243px RenderFlex overflow source in the metadata/transport row area.

## 2026-05-26 — Resolve CLAUDE.md Shuffle Contradictions
*Goal:* Address user questions regarding mpv dependency in 2-track sliding window, resolve contradictions in `CLAUDE.md`, and clean up lint/formatting.
*Commits:* f767631
*Key decisions:*
- Updated `CLAUDE.md` to reflect the 2-track sliding window model and Dart-side Fisher-Yates shuffle.
- Explained the necessity of `_syncNextTrackInMpv()` to keep the native prefetch slot in sync for gapless playback while maintaining the queue management/shuffle purely in Dart.
- Fixed a static analysis lint in `router.dart` (enclosed an `if` block in braces) and formatted modified files.

## 2026-05-26 — Native-fication Research & Architectural Plans
*Goal:* Deeply research opportunities to native-fy Aetherfin's media framework, local scanning, custom actions, and background downloads. Produce 5 detailed implementation plans, and execute the first plan (Audio Focus & Headphone Disconnection).
*Commits:* f2d7732, be156c8, 81e38f0, 5581e06, da6bbd4, 6cb9ddd (and others)
*Key decisions:*
- Created 5 plans in `thoughts/shared/plans/` (with `_agy` suffix).
- Implemented and verified the first plan: **Native Audio Focus & Headphone Disconnection (Becoming Noisy) Handling**.
- Implemented **quick settings custom actions** for shuffle, repeat, and favorite.
- Implemented **Android 16 Live Updates** wrapper and streams binding.
- Optimized SAF scanner to use direct cursor queries for 10-50x speedup.
- Fixed shuffle auto-advance bug via `_syncNextTrackInMpv()`.
