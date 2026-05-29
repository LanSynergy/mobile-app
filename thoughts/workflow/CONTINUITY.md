# Continuity Ledger

## 2026-05-29 — Add forNtimes (repeat 2) to QS media player cycle
*Goal:* Add 4th repeat state (repeat 2 times) to QS media player repeat cycle, with proper icon and labels.
*Commits:* 2d58952
*Key decisions:*
- `ic_repeat_ntimes.xml`: fill-based loop arrow + "2" path indicator inside arrow
- `onToggleRepeat` cycle: off → playlist → file → forNtimes → off (was missing forNtimes)
- Kotlin label: "ntimes" → "Repeat 2"
- viewportWidth experiments abandoned; badge at top-right was too small at 20dp
- All 384 tests pass, `flutter analyze`: 0 errors

## 2026-05-29 — Workflow optimization v2: lean plans, session bootstrap, auto-prune
*Goal:* Add 3 workflow optimizations: plans no longer embed inline code (saves 70-80% plan size), session bootstrap checkpoint file for instant context recovery, and auto-prune policy for old artifacts.
*Commits:* 20238b2
*Key decisions:*
- Plans describe WHAT and WHERE but not the full code — implementer reads source
- `thoughts/workflow/BOOTSTRAP.md` updated after every session with HEAD + test state
- Completed plans/designs moved to `thoughts/.legacy/` after commits land
- Per-session ledgers pruned after their entry is in CONTINUITY.md (keep 30 days in .legacy)
- All 383 tests pass, `flutter analyze`: 0 errors, 0 warnings

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
