# Continuity Ledger

## 2026-05-27 — Auto-Advance Overhaul (Phase 2)
*Goal:* Transition from mpv's 2-track sliding window to a single-track player model, resolving lock-screen and control desynchronization issues.
*Commits:* 96bef1c, <current_commit>
*Key decisions:*
- Switched to a single-track player model in `player_service.dart`.
- Developed `StreamPrefetcher` using `dio` to download stream files to local storage for gapless playback support.
- Completed the transition fade-out/fade-in blending logic in the scrubber/visualizer.
- Removed obsolete sync methods, cleaned up unit tests, and resolved all lint/formatting warnings.

## 2026-05-27 — Android Native Integrations & UX Enhancements
*Goal:* Implement home screen widgets, dynamic launcher icon changing, smart Bluetooth reconnection behavior, and reactive favorite status sync.
*Commits:* e3fa908
*Key decisions:*
- Wired bidirectional favorite status synchronization between Dart/Flutter and Kotlin using the MethodChannel.
- Dynamic app widget background and content theming utilizing the Android Palette API to match artwork colors.
- Custom dynamic launcher icons setting UI using `<activity-alias>` elements to prevent duplicate app icon registrations.
- Re-activated automatic resumption of playback upon Bluetooth connection if paused within the 5-minute disconnect window.

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
