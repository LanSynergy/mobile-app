# Continuity Ledger

## 2026-05-26 — Fix Shuffle Prefetch Mismatch
*Goal:* Fix automatic track completion transitions playing the incorrect next track when shuffle is active.
*Commits:* c8de5f3
*Key decisions:*
- Corrected invalid `mpv` playlist properties (`playlist/current` and `playlist/count`) to the standard `playlist-pos` and `playlist-count` in `player_service.dart`.
- Preserved shuffle mode in `play_actions.dart`'s `playQueue` call to prevent the queue-replacement action from overriding active shuffle states.
- Corrected trigger order for shuffle button handlers in `playlist_screen.dart`, `smart_playlist_detail_screen.dart`, and `album_more_sheet.dart` to first load the new queue and then enable shuffle.
- Verified and fixed tests in `player_service_test.dart` and `play_actions_queue_history_test.dart` to match updated properties and mocks.

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
