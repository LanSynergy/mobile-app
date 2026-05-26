# Continuity Ledger

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

## 2026-05-26 — Widget palette theming, favorite toggle, smart Bluetooth resume
*Goal:* Implement home screen widget improvements including dynamic artwork-driven theming, favorite toggle, and smart Bluetooth auto-resume within 5-minute disconnect window.
*Commits:* 9def7b1
*Key decisions:*
- Added `palette-ktx:1.0.0` dependency for artwork color extraction.
- Widget background dynamically sets muted Palette color from album art with luminance-based text contrast.
- Favorite button added to widget layout with star on/off state, wired via custom action to Dart's `toggleFavorite`.
- `lastDisconnectionTimeMs` recorded on `ACTION_AUDIO_BECOMING_NOISY` to enable smart window-based auto-resume.
- Bluetooth auto-resume only fires within 5 minutes of last disconnect and when service is not already playing.

## 2026-05-26 — Fix build failure: remove nonexistent setShuffleMode/setRepeatMode on PlaybackStateCompat.Builder
*Goal:* Fix build error caused by a prior edit that called `stateBuilder.setShuffleMode()`/`stateBuilder.setRepeatMode()` — methods that don't exist in `androidx.media:media` at any version (1.6.0, 1.7.0, or even platform `PlaybackState.Builder` on API 34/36). They are not part of the public API.
*Commits:* 4aeb00c
*Key decisions:*
- Replaced nonexistent `stateBuilder.setShuffleMode()`/`stateBuilder.setRepeatMode()` (compile error) with standard `MediaSessionCompat.Callback.onSetShuffleMode()`/`onSetRepeatMode()` overrides.
- The standard notification shuffle/repeat buttons still work — they now route to Flutter via MethodChannel as `setShuffleMode`/`setRepeatMode` commands.
- Bumped `androidx.media:media` from 1.6.0 to 1.7.0.
- Added `/build/` to `android/.gitignore` to prevent build artifacts from being committed.
- Reverted `compileSdk` change — kept the original `flutter.compileSdkVersion` (the hardcoded `36` was not the cause of the error, and `compileSdk = 36` is the same value as flutter.compileSdkVersion for API 36).
