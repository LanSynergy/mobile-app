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

## 2026-05-26 — Widget palette theming, favorite toggle, smart Bluetooth resume
*Goal:* Implement home screen widget improvements including dynamic artwork-driven theming, favorite toggle, and smart Bluetooth auto-resume within 5-minute disconnect window.
*Commits:* 9def7b1
*Key decisions:*
- Added `palette-ktx:1.0.0` dependency for artwork color extraction.
- Widget background dynamically sets muted Palette color from album art with luminance-based text contrast.
- Favorite button added to widget layout with star on/off state, wired via custom action to Dart's `toggleFavorite`.
- `lastDisconnectionTimeMs` recorded on `ACTION_AUDIO_BECOMING_NOISY` to enable smart window-based auto-resume.
- Bluetooth auto-resume only fires within 5 minutes of last disconnect and when service is not already playing.

## 2026-05-26 — Remove non-functional custom action buttons from notification
*Goal:* Remove 3 custom action buttons (toggleShuffle, cycleRepeat, toggleFavorite) from notification/QS that never worked because Android requires a
`MediaSession`-connected `MediaBrowserService` to route custom actions back to the app. Replace with standard `PlaybackState` API (setShuffleMode/setRepeatMode).
*Commits:* 0df63c8
*Key decisions:*
- Kotlin: removed ACTION_TOGGLE_SHUFFLE/ACTION_CYCLE_REPEAT/ACTION_TOGGLE_FAVORITE constants and onCustomAction() handler.
- Kotlin: wired stateBuilder.setShuffleMode/setRepeatMode instead. Added ACTION_SET_SHUFFLE_MODE/SET_REPEAT_MODE to supported actions.
- Dart media_session_bridge: removed isFavorite from MediaSessionState, removed 3 custom action callbacks and dispatch.
- Dart player_service: removed onFavoriteToggled (dead field).
- Widget layout: removed widget_favorite ImageButton.
- Widget provider: removed isFavorite extra reading and favorite icon sync.
- Tests: removed 3 custom action tests from both media_session_bridge_test.dart and player_service_test.dart.
- Full verify gate passed: 0 format issues, 0 analyze issues, all 350 tests pass.
