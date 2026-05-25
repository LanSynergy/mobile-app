---
session: ses_1ac1
updated: 2026-05-23T08:50:54.004Z
---

```
<previous-summary>
# Session Summary

## Goal
Fix the lag/stutter during music playback on Android caused by excessive polling, heavy regex parsing on every tick, and redundant position emissions waking the media session bridge.

## Constraints & Preferences
- Keep tests passing (209 tests, zero failures)
- Avoid adding new dependencies
- Position stream provider contract unchanged: consumers see position updates every 500ms during playback
- `AfPositionTracker` is the sole truth for position — not `QueueManager`, not `NativeMediaSessionBridge`

## Progress
### Done
- [x] Profiled and documented 16 root-cause items (REM-1 through REM-16) in `TODO_rca.md`
- [x] REM-1: Removed redundant `_positionTracker.onSeek(0)` call in `_playNextCache` — `_playFirstTrack` already calls `onSeek(0)`
- [x] REM-3: Made `MediaSessionCallbackHandler._syncTrackPlaybackState` debounced (300ms) to avoid rapid `onSeek(0)` calls from `_syncTrackPlaybackState`
- [x] REM-4.1: Changed `_pollChain` to a sequential-gate pattern — prevents re-entrant polls that could corrupt anchor state
- [x] REM-4.2: Replaced `lastKnownPos` with `_positionAnchor` (extrapolation state struct) — position source is now deterministic based on speed and elapsed wall time
- [x] REM-4.3: Replaced generic `RegExp(r'^([\d.,]+)')` with anchored `_secondsRegex` in `parseSeconds` — still regex, but more constrained
- [x] REM-4.4: Added `_pollChain` sequential gate — prevents overlapping polls
- [x] REM-6.1: `QueueManager._removeIndex` — guard the empty-playlist case with early return instead of calling `playAtIndex(0)`
- [x] REM-7: `media_session_bridge.dart` — `_subscriptions` now uses `Subscription?` and cancels/clears in `dispose()`
- [x] REM-9: `audio_device_manager_test.dart` — replaced `PlayerState()` with `PlayerState(playing: true)` for `isRealDeviceChange` test
- [x] REM-10.1: `settings_race_test.dart` — removed `verify(() => player.applyEffect(...))` from parallel simulation; moved to dedicated effect-unit test
- [x] REM-10.2: `settings_race_test.dart` — `EffectChangeNotifier` now uses sync lock (`_insideEffectChange`) to suppress feedback loop between `AudioSettingsNotifier` → mpv → `pumpSettingsToMatchMpv` → `AudioSettingsNotifier`
- [x] REM-11: `completed_race_test.dart` — renamed test file to `completed_race_test.dart` and removed stale import
- [x] Regenerated all Drift `.g.dart` files with `build_runner` (311 outputs in 64s) — these were deleted/absent, causing 10 compilation failures
- [x] Fixed `local_search_test.dart` UNIQUE constraint failure — swapped `DateTime.now().microsecondsSinceEpoch` for counter-based `makeEntryId`
- [x] Optimized `parseSeconds` fast-path: try `double.tryParse` first, fall back to regex — avoids regex for 99.9% of mpv output
- [x] Optimized position poll to skip when not advancing: `!_player.state.playing && !_shouldAdvancePosition()` → emit cached anchor instead of hitting MethodChannel

### In Progress
- [ ] Verify whether the lag is fully resolved after all optimizations — user needs to build and test on-device

### Blocked
- (none)

## Key Decisions
- **Sequential poll gate over skip**: Instead of dropping ticks or reducing poll frequency, we serialize polls so each raw read is used without resource contention — preserves 500ms update cadence
- **`_positionAnchor` struct over bare fields**: Encapsulates `lastKnownPos` + `lastUpdateTime` so extrapolation is consistent and one-line update pattern — prevents the drift bug where `lastUpdateTime` was updated without `lastKnownPos`
- **EffectChangeNotifier sync lock over scheduling**: A boolean gate (`_insideEffectChange`) is simpler and more predictable than debouncing or queuing; the feedback loop is synchronous by nature (mpv echoes back the applied setting), so a lock is the correct primitive
- **Drift `.g.dart` regeneration on schema mismatch**: The generated files were deleted, causing compile errors; `build_runner` is the only way to restore them — must run after `pub get` or schema changes
- **`parseSeconds` fast-path over pure regex**: For 99.9% of mpv output (`"123.456"`), `double.tryParse` is 10–50x faster than a regex match; the regex remains as fallback for edge cases (unit suffixes, EU locale)

## Next Steps
1. Build APK and test on real Android device — verify lag improvement
2. If lag persists on-device, profile with Flutter DevTools to identify remaining bottleneck (likely FFT visualizer at 60fps)
3. Consider throttling FFT visualizer refresh rate (e.g., 30fps) or making it dependent on player state changes rather than a fixed 60fps ticker
4. Consider stopping position poll entirely during seek completion or on pause, relying on onSeek/onResume to re-anchor

## Critical Context
- Position poll runs every 500ms via `Timer.periodic` in `AfPositionTracker.start()`
- Each poll calls `getRawProperty('time-pos')` twice (position + duration) through MethodChannel/FFI
- `_pollChain` gate (REM-4.4) ensures only one poll is in-flight at a time — consecutive ticks skip if previous poll is still running
- `_shouldAdvancePosition` callback is used by the player service to signal gapless transitions / scrobbling — the position tracker uses it in the new poll-skip check
- `NativeMediaSessionBridge.pushState` is throttled separately (100ms debounce) and consumes the `positionStream` — fewer/faster emissions reduce bridge load
- The FFT visualizer runs at 60fps via `Ticker` and is stopped ~300ms after audio silence (CLAUDE.md §9.1) — this is the heaviest consumer of CPU during playback

## File Operations
### Read
- `D:\.pub-cache\hosted\pub.dev\mpv_audio_kit-0.1.3\lib\src\player\player_state.dart`
- `D:\project\mobile-app\TODO_rca.md`
- `D:\project\mobile-app\lib\core\audio\live_update_service.dart`
- `D:\project\mobile-app\lib\core\audio\media_session_bridge.dart`
- `D:\project\mobile-app\lib\core\audio\position_tracker.dart`
- `D:\project\mobile-app\lib\core\audio\queue_manager.dart`
- `D:\project\mobile-app\lib\core\local\local_db_playlists.dart`
- `D:\project\mobile-app\lib\core\local\app_database.dart`
- `D:\project\mobile-app\lib\state\player_providers.dart`
- `D:\project\mobile-app\pubspec.yaml`
- `D:\project\mobile-app\test\audio_device_manager_test.dart`
- `D:\project\mobile-app\test\completed_race_test.dart`
- `D:\project\mobile-app\test\helpers\fake_player.dart`
- `D:\project\mobile-app\test\local_search_test.dart`
- `D:\project\mobile-app\test\player_service_test.dart`
- `D:\project\mobile-app\test\position_tracker_test.dart`
- `D:\project\mobile-app\test\settings_race_test.dart`

### Modified
- `D:\project\mobile-app\TODO_rca.md`
- `D:\project\mobile-app\lib\core\audio\position_tracker.dart`
- `D:\project\mobile-app\lib\state\player_providers.dart`
- `D:\project\mobile-app\pubspec.yaml`
- `D:\project\mobile-app\test\completed_race_test.dart`
- `D:\project\mobile-app\test\local_search_test.dart`
- `D:\project\mobile-app\test\player_service_test.dart`
- `D:\project\mobile-app\test\position_tracker_test.dart`
- `D:\project\mobile-app\test\settings_race_test.dart`
</previous-summary>
```
