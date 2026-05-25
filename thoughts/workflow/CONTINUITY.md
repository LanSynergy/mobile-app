# Continuity Ledger

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

## 2026-05-24 — PlayerSettingsStore + pagination + scrubber tests
*Goal:* Deliver commits 8/9/10 from Deep Review: refactor `player_settings_store`, client-side pagination, AudioVisualScrubber tests
*Commits:* (verify with git log)
*Key decisions:*
- Extracted `PlayerSettingsStore` from `player_service.dart` into own file
- Added `LIMIT/OFFSET` support in `LocalDb._queryTracks()` for pagination
- Removed `_positionTracker.start()` from `AfPlayerService.test()` constructor — prevents `FakeAsync` timer error in widget tests
- Replaced all `pumpAndSettle()` with `pump()` in scrubber tests — vsync ticker never settles
