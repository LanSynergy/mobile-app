# Continuity Ledger

## 2026-05-26 — Native-fication Research & Architectural Plans
*Goal:* Deeply research opportunities to native-fy Aetherfin's media framework, local scanning, custom actions, and background downloads. Produce 5 detailed implementation plans, and execute the first plan (Audio Focus & Headphone Disconnection).
*Commits:* None (local build/test verification complete)
*Key decisions:*
- Created 5 plans in `thoughts/shared/plans/` (with `_agy` suffix).
- Implemented and verified the first plan: **Native Audio Focus & Headphone Disconnection (Becoming Noisy) Handling**.
  - Wrote dynamic registration of broadcast receiver and audio focus listener in Kotlin.
  - Linked native events to Dart MethodChannels via `duck` and `unduck` method calls.
  - Verified with a dedicated unit test suite; all 19 tests in `test/player_service_test.dart` pass and analyzer reports 0 issues.
- Decided to omit/drop Android 16 Live Updates Dart implementation as it causes double notification rendering on modern Android versions, as reported by user.

## 2026-05-25 — Namida-Inspired UX Refinements
*Goal:* Complete the implementation of 5 UX refinements: Queue History, forNtimes loop, shuffle next, playlist undo, and M3U export/import.
*Commits:* fa6177c
*Key decisions:*
- Queue History table persisted in SQLite via Drift DB v4 migration, auto-cleanup capped at 10 items.
- forNtimes Loop intercept in player completed stream handler enables ntimes repetition before advancing.
- Shuffle Next (shuffleTail) shuffles remaining queue tracks, leaving past tracks untouched.
- M3U Export/Import utilizes a simplified self-contained temp storage and pasted text content dialog path.
- All lints cleaned up to achieve 0 static analyzer issues and all 346 tests pass.

## 2026-05-25 — Info-level lint cleanup + fatal info lints in CI
*Goal:* Fix all 8 `curly_braces_in_flow_control_structures` info-level lints and make `flutter analyze` report info issues as fatal (remove `--no-fatal-infos`)
*Commits:* 53ef709
*Key decisions:*
- Removed `--no-fatal-infos` from all 4 references in CLAUDE.md — info lints now block CI
- Fixed 8 lint violations across 5 files: `smart_playlist_engine.dart`, `cast_picker_screen.dart`, `utility_row.dart`, `settings_sections.dart`, `save_to_playlist_sheet.dart`
- Verify gate: `dart format` (dry-run) → `flutter analyze` → `flutter test` — all pass clean

## 2026-05-25 — Workflow pipeline optimization
*Goal:* Add verify gate, consolidate ledgers, fix formatting drift, add relative-position anchors and rolling ledger conventions
*Commits:* 9d4e346
*Key decisions:* Use `dart format --set-exit-if-changed` for format gate before analysis, rolling ledger at `thoughts/workflow/CONTINUITY.md` with 5-entry pruning, relative-position anchors in plans instead of line numbers, `thoughts/.legacy/` for 30-day archive retention, formatting drift auto-fixed across 198 files

## 2026-05-25 — Scan progress UI + queue flush
*Goal:* Implement scan progress indicator and `stopAndClear()` queue flush per `thoughts/shared/plans/2026-05-25-scan-progress-and-queue-flush.md`
*Commits:* fb177c7
*Key decisions:*
- `stopAndClear()` calls `_queueManager.clear()` after `_player.stop()` — ensures in-memory queue state resets before player stop
- `_startScan()` takes nullable `folderUri` — avoids duplicating scan logic; `null` = full rescan
- Progress callback passed as `onProgress:` named param to `LocalLibrary`
- `playerServiceProvider` overridden in widget test via `ProviderContainer`

## 2026-05-24 — Native queue engine rewrite
*Goal:* Complete native queue engine rewrite (Plans 1 & 2), fix shuffle blink regression, prepare v0.3.0
*Commits:* 552d00c, de728a0, a1864bf, 46fc091
*Key decisions:*
- `AfQueueEngine` — 285-line pure-Dart queue engine; 2-track sliding window (`open()` + `add()`)
- `AfQueueManager` simplified to thin stream wrapper (105 lines)
- `AfPlayerService` simplified from 1413→1035 lines — removed `_jumpAndPlay`, `_pendingPlayNudgeIdx`, `_playlistHandlerGen`, `_nudgeRetries`, `_queueLoadGen`, `_isLoadingQueue`
- Shuffle blink fix: removed `emitCurrentTrack` + `onTrackChanged` from `setAfShuffleMode` — current track doesn't change on shuffle toggle
- `_queueLock` only guards `openAll` now
