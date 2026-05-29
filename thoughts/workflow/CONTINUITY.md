# Continuity Ledger

## 2026-05-29 — Fix 7 flutter analyze issues (curly_braces, cancel_subscriptions, unused_import)
*Goal:* Fix all 7 info/warning issues across 3 files: home_screen.dart (curly braces), player_providers.dart (StreamSubscription disposal), global_mini_player_overlay_test.dart (unused import).
*Commits:* 84f3424, ac08a11

## 2026-05-29 — Fix failing test after mini_player state refactor
*Goal:* Fix `mini_player_progress_ring_test.dart` which failed because `_ReactiveProgressRingState.initState()` reads `playerServiceProvider` directly for position stream subscription (added in mini_player state refactor).
*Commits:* 28e0133
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

