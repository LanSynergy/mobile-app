# Continuity Ledger

## 2026-05-31 — Optimization audit: all 9 batches committed
*Goal:* Execute 9-batch optimization audit covering shared_dio_client retry interceptor, home_screen section extraction, album_screen consumer granularity, artwork_manager cache fix, local_db_tracks + smart_playlist_db query opt, schema v10 indexes, favorite_providers TrackFavoriteOverride, shared FFT provider.
*Commits:* ddff930, 63aea6f, c388b05, 5bb7386, 1f7121b, 7c889e8, 78db855
*Key decisions:*
- `fftFrameProvider` wraps `spectrumStream.asBroadcastStream()` — visualizer + artwork pulse share one mpv subscription
- `bassEnergyProvider` derives sub-bass max from first 7 FFT bands for transient detection
- Both consumers use `ref.listen(fftFrameProvider, ...)` instead of direct stream subscriptions
- Removing `StreamSubscription` fields (now managed by Riverpod ref lifecycle)
- Schema v10 migration uses `m.database.customStatement()` for `CREATE INDEX` (Migrator lacks `createIndex` for non-table-class indexes)

## 2026-05-29 — Add forNtimes (repeat 2) to QS media player cycle
*Goal:* Add 4th repeat state (repeat 2 times) to QS media player repeat cycle, with proper icon and labels.
*Commits:* 2d58952
*Key decisions:*
- `ic_repeat_ntimes.xml`: fill-based loop arrow + "2" path indicator inside arrow
- `onToggleRepeat` cycle: off → playlist → file → forNtimes → off (was missing forNtimes)
- Kotlin label: "ntimes" → "Repeat 2"
- All 384 tests pass, `flutter analyze`: 0 errors

## 2026-05-29 — Workflow optimization v2: lean plans, session bootstrap, auto-prune
*Goal:* Add 3 workflow optimizations: plans no longer embed inline code (saves 70-80% plan size), session bootstrap checkpoint file for instant context recovery, and auto-prune policy for old artifacts.
*Commits:* 20238b2
*Key decisions:*
- Plans describe WHAT and WHERE but not the full code — implementer reads source
- `thoughts/workflow/BOOTSTRAP.md` updated after every session with HEAD + test state
- Completed plans/designs moved to `thoughts/.legacy/` after commits land

## 2026-05-29 — Fix 7 flutter analyze issues (curly_braces, cancel_subscriptions, unused_import)
*Goal:* Fix all 7 info/warning issues across 3 files: home_screen.dart (curly braces), player_providers.dart (StreamSubscription disposal), global_mini_player_overlay_test.dart (unused import).
*Commits:* 84f3424, ac08a11

## 2026-05-29 — Fix failing test after mini_player state refactor
*Goal:* Fix `mini_player_progress_ring_test.dart` which failed because `_ReactiveProgressRingState.initState()` reads `playerServiceProvider` directly for position stream subscription.
*Commits:* 28e0133
*Key decisions:*
- Rewrote test to use `createMockPlayer()` + `AfPlayerService.test()` pattern
- All 383 tests pass, `flutter analyze`: 0 errors, 0 warnings
