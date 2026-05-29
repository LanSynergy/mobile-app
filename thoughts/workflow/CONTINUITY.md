# Continuity Ledger

## 2026-05-29 — Fix failing test after mini_player state refactor
*Goal:* Fix `mini_player_progress_ring_test.dart` which failed because `_ReactiveProgressRingState.initState()` reads `playerServiceProvider` directly for position stream subscription (added in mini_player state refactor).
*Commits:* 4ea0407
*Key decisions:*
- Rewrote test to use `createMockPlayer()` + `AfPlayerService.test()` pattern matching other test files
- Added `playerServiceProvider.overrideWithValue(service)` and `currentArtworkUriProvider` overrides
- Removed `positionStreamProvider` override (no longer consumed by `_ReactiveProgressRing`)
- All 383 tests pass, `flutter analyze`: 0 errors, 0 warnings

## 2026-05-28 — EOF fallback for broken time-pos observation (position tracker)
*Goal:* Add end-of-track fallback that advances the queue when mpv's completed event never fires (devices with broken time-pos property observation).
*Commits:* 9a8a63f
*Key decisions:*
- Implemented `_checkEndOfTrackFallback()` in player_service.dart position stream listener
- Conditions: position >= 80% duration, !playing, near-EOF state, not already handled
- `_eofFallbackHandledTrackId` guard prevents double-fire for same track
- Guard resets on track change (playQueue, skipToNext, setAfLoopMode, new queue load)
- Added `emitPositionForTesting()` to `AfPositionTracker` for test access to the tracker's stream controller
- 7 tests covering: basic advance, completed-first skip, early-position skip, still-playing skip, double-fire prevention, missing-completed simulation, skipToNext guard reset
- All 361 tests pass, `flutter analyze`: 0 errors, 0 warnings

## 2026-05-28 — Server Client Enhancement: Navidrome native auth + queue sync
*Goal:* Add hybrid Navidrome client with native REST auth, queue sync, OpenSubsonic capabilities probing, and precise listen-time scrobbling.
*Commits:* 00577ce
*Key decisions:*
- Created `NavidromeClient` subclassing `SubsonicClient` with JWT auth via `/api/auth/login`
- Implemented `savePlayQueue` / `getPlayQueue` via Navidrome's `/api/queue` endpoint
- Added OpenSubsonic capabilities probing: `OS_FORM_POST` (x-www-form-urlencoded), `OS_TRANSCODE_DECISION` (pre-stream transcode check)
- Updated `music_backend_providers.dart` to switch on `ServerType.subsonic` → `NavidromeClient`
- Added precise listen-time scrobbling with 75% threshold gate in `jellyfin_playback_reporter.dart`
- Tracked continuous playback duration (`_listenedDuration`) in `player_service.dart`
- All 354 tests pass, `flutter analyze`: 0 errors, 0 warnings

## 2026-05-27 — Auto-Advance Overhaul (Phase 2)
*Goal:* Transition from mpv's 2-track sliding window to a single-track player model, resolving lock-screen and control desynchronization issues.
*Commits:* 96bef1c, <current_commit>
*Key decisions:*
- Switched to a single-track player model in `player_service.dart`.
- Developed `StreamPrefetcher` using `dio` to download stream files to local storage for gapless playback support.
- Completed the transition fade-out/fade-in blending logic in the scrubber/visualizer.
- Added a remaining duration guard (2000ms threshold) in the `completed` stream listener to prevent premature advancing/looping during seeks or network buffering underflows.
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

