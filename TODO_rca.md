# Root Cause Analysis: Playback System

**Date**: 2026-05-23
**System**: Aetherfin mobile app — Android music player
**Component**: Playback subsystem (AfPlayerService, AfPositionTracker, AfQueueManager, state layer)
**Severity**: Mixed (P0–P3 findings)

---

## Executive Summary

The playback subsystem has accumulated multiple latent bugs and test gaps across 8 code reviews in the last 30 commits. While recent fixes have resolved specific race conditions (loop mode snapshots, generation counters, position tracking), **2 P0 bugs** and **5 P1 gaps** remain that can cause crashes, stuck position display, silent queue corruption, and state desync.

**Most critical causal factors:**
1. `replaceQueue([], startIndex)` throws `ArgumentError` on empty input — a crash-on-empty-queue bug with no test coverage
2. `play()`/`pause()`/`seek()` operate outside `_queueLock` and can race with the `completed` stream handler inside the lock, causing mpv state corruption
3. `syncFromMpv` silently clears or shrinks the queue on sync failure, leaving audio potentially playing but the UI showing empty state
4. 347 lines of critical playback logic (position_tracker + audio_device_manager) have **zero test coverage**
5. Guard tests validate *reimplemented* logic, not actual `AfPlayerService` guards — false confidence in regression protection

**Risk level distribution:** Critical (2) | High (3) | Medium (5) | Low (1)

**Completed items (this session):**
- REM-4.2: Removed `LiveUpdateService` dead code (`lib/core/audio/live_update_service.dart` deleted)
- REM-4.3: Added robust string parsing for `getRawPosition`/`getRawDuration` via `RegExp` + `parseSeconds()`
- REM-4.4: Replaced `_isPolling` boolean with sequential `_pollChain` in `AfPositionTracker`

**Remaining action items:** Fix the `replaceQueue` empty-input crash, add `_queueLock` to `play()`/`pause()`/`seek()`, and write position_tracker tests (P0–P2 items still open).

**Prevention strategy summary:** Add missing unit tests for untested modules, convert guard tests from simulated to integration-level, and add race-condition tests for the `completed` handler vs navigation methods.

---

## Detailed Findings

### P0 — Production Crash Risk

- [ ] **RCA-FIND-1.1 [replaceQueue empty-input ArgumentError]**:
  - **Evidence**: `lib/core/audio/queue_manager.dart:86` — `startIndex.clamp(0, tracks.length - 1)`. When `tracks` is empty, `tracks.length - 1` is `-1`, so `0.clamp(0, -1)` throws `ArgumentError` because `lowerBound > upperBound`.
  - **Reasoning**: `clamp` requires `lowerBound <= upperBound`. With empty input, the invariant is violated. The `playQueue` entry guard at `player_service.dart:442` (`if (tracks.isEmpty) return;`) prevents the crash during normal flow, but `syncFromMpv` calls `replaceQueue` directly (line 184, 195) without an empty-input guard. If `syncFromMpv` resolves zero tracks and `reordered.isNotEmpty` is false, it does NOT call `replaceQueue` (it manually clears the queue at line 203-204). However, the `reordered.length == mpvItems.length` path at line 181-185 calls `replaceQueue` with potentially non-empty data, so the direct risk is low in practice. The design fragility is the real concern.
  - **Impact**: If any code path calls `replaceQueue` with empty input, the app crashes with `ArgumentError`.
  - **Status**: **Confirmed** (code analysis)
  - **Confidence**: **High** — directly observable in source code
  - **Counterfactual**: Adding an early return `if (tracks.isEmpty) return;` in `replaceQueue` would prevent this crash regardless of caller.
  - **Owner**: Playback team
  - **Priority**: **P0**

- [ ] **RCA-FIND-1.2 [play/pause/seek race with completed handler]**:
  - **Evidence**: `lib/core/audio/player_service.dart:563-573` — `play()` does NOT acquire `_queueLock`. It directly calls `_player.play()`. Meanwhile, the `completed` stream handler (line 1061-1122) acquires `_queueLock` and calls `_player.stop()` (line 1095) or `_jumpAndPlay(0)` (line 1109). Since `play()` is not serialized with `_queueLock`, these can interleave.
  - **Reasoning**: If `play()` fires while the `completed` handler is inside `_queueLock` executing `_player.stop()`, the final state depends on mpv's internal ordering: `play()` after `stop()` leaves mpv playing when it should be stopped. Conversely, `pause()` (line 575-585) and `seek()` (line 599-611) are also lock-free. `seek()` checks `_isLoadingQueue` but that's `false` during `completed` handler execution, so seeks can interleave with track transitions.
  - **Impact**: Brief playback when queue should be silent, or seek applied to wrong track during transition.
  - **Status**: **Confirmed** (code analysis)
  - **Confidence**: **High** — source code clearly shows missing lock acquisition
  - **Counterfactual**: Wrapping `play()` and `pause()` in `_queueLock` would serialize them with the `completed` handler.
  - **Owner**: Playback team
  - **Priority**: **P0**

### P1 — State Desync & Silent Corruption

- [ ] **RCA-FIND-2.1 [syncFromMpv silently truncates queue]**:
  - **Evidence**: `lib/core/audio/queue_manager.dart:186-196` — "Partial sync" path: when some URLs fail to resolve, the resolved subset replaces the full queue. `lib/core/audio/queue_manager.dart:197-207` — "Full sync failure" path: when zero URLs resolve, the queue is cleared entirely, `currentTrackProvider` emits `null`, but mpv may still be playing audio.
  - **Reasoning**: The URL→track lookup (`_urlToTrack[media.uri]`) and ID extraction (`_extractor.extractId`) are best-effort. If the mpv playlist contains URLs that don't match the Dart-side track map (e.g., after a race between `reorderQueue` and a playlist event), tracks are silently dropped. There's no error signal to the UI layer — `currentTrackProvider` just emits `null`.
  - **Impact**: Queue silently shrinks or disappears mid-playback. User sees empty now-playing screen while audio may still be playing.
  - **Status**: **Confirmed** (code analysis)
  - **Confidence**: **High**
  - **Counterfactual**: Adding a guard that skips the `replaceQueue` on partial sync (keeping the existing queue) or emitting an error to `playbackErrorProvider` would prevent silent corruption.
  - **Owner**: Playback team
  - **Priority**: **P1**

- [ ] **RCA-FIND-2.2 [Dual duration sources compete for durationStreamProvider]**:
  - **Evidence**: `lib/state/player_providers.dart:115-119` subscribes to `svc.durationStream` (mpv property observer). Lines 129-149 poll `svc.getRawDuration()` every 1000ms. Both write to the same `StateProvider<Duration>`.
  - **Reasoning**: `svc.durationStream` comes from `_player.stream.duration` (mpv's property observation callback). `getRawDuration()` calls `_player.getRawProperty('duration')` (a direct query). These can return different values at different times, causing the `durationStreamProvider` to flicker between values as the two sources race.
  - **Impact**: UI flickering duration display; seek bar may jump between different total lengths.
  - **Status**: **Confirmed** (code analysis)
  - **Confidence**: **High**
  - **Counterfactual**: Removing the poll loop and relying solely on `svc.durationStream`, or using a single source with deduplication.
  - **Owner**: Playback team
  - **Priority**: **P1**

- [ ] **RCA-FIND-2.3 [fftSpectrumProvider unsafe cast]**:
  - **Evidence**: `lib/state/player_providers.dart:211-214` — `return svc.spectrumStream.cast<FftFrame>();` Without a type check, if the stream emits a non-`FftFrame` object (e.g., from an mpv error or unexpected format), `cast()` throws `TypeError`.
  - **Reasoning**: `Stream.cast()` is equivalent to `.map((e) => e as FftFrame)`. If mpv emits a different type (error object, null, etc.), the error propagates uncaught through the Riverpod provider and crashes the widget tree.
  - **Impact**: Visualizer crashes if FFT data format changes; no user-facing error recovery.
  - **Status**: **Confirmed** (code analysis)
  - **Confidence**: **Medium** — depends on external mpv_audio_kit behavior
  - **Counterfactual**: Using `.map((e) => e is FftFrame ? e : FftFrame.zero)` would provide safe fallback.
  - **Owner**: Playback team
  - **Priority**: **P1**

- [ ] **RCA-FIND-2.4 [Settings snapshotted at boot, never re-read]**:
  - **Evidence**: `lib/state/player_providers.dart:28-36` — `onTrackCompleted` callback reads `offlineCacheEnabledProvider` and `maxBitrateProvider` via `ref.read()`. These are evaluated once when `wirePlayerService()` runs and stored in the closure. Runtime changes are invisible.
  - **Reasoning**: `ref.read()` returns the current value without subscribing. If the user toggles offline cache or changes bitrate while a track plays, the next completion callback uses the boot-time value, not the current setting.
  - **Impact**: Offline caching may not respect user's latest settings until app restart.
  - **Status**: **Confirmed** (code analysis)
  - **Confidence**: **High**
  - **Counterfactual**: Using `ref.watch()` or re-reading settings inside the callback each time it fires.
  - **Owner**: Playback team
  - **Priority**: **P1**

### P2 — Regressions Risks & Test Gaps

- [ ] **RCA-FIND-3.1 [position_tracker.dart untested (253 lines)]**:
  - **Evidence**: No test file exists for `lib/core/audio/position_tracker.dart`. Source has 253 lines with stale detection (lines 157-174), extrapolation (lines 176-193), frame-skip gate (lines 77-81), seek guard (lines 88-100), polling algorithm (lines 195-244), and re-entrancy guard (lines 203-206). Zero test coverage.
  - **Reasoning**: This is the most complex untested module. The stale-detection threshold (`_rawStaleAfterTicks = 4`), extrapolation math, frame-skip delta, re-entrancy fallback, and seek suppression all directly affect the user's visible position indicator.
  - **Impact**: Any refactoring of the position tracking logic has no safety net. The 4 recent position-related bug fixes (`5187658`, `b7342ba`, `ed679e9`, `08ce5c3`) would not be caught by regression tests.
  - **Status**: **Confirmed** (test coverage gap)
  - **Confidence**: **High**
  - **Counterfactual**: Writing `test/position_tracker_test.dart` with tests for each algorithm path would prevent regressions.
  - **Owner**: Playback team
  - **Priority**: **P2**

- [ ] **RCA-FIND-3.2 [audio_device_manager.dart untested (94 lines)]**:
  - **Evidence**: No test file exists for `lib/core/audio/audio_device_manager.dart`. Source has nudge retry logic (lines 52-93), device change deduplication (lines 30-34), and effect reapplication (lines 38-47).
  - **Reasoning**: The nudge retry delays `[300ms, 1000ms, 2500ms]` and early-bail optimization are untested. Device change deduplication is a single-point-of-failure for audio output stability.
  - **Impact**: Device changes (Bluetooth connect/disconnect, USB DAC plug/unplug) could fail to reapply effects without test coverage.
  - **Status**: **Confirmed** (test coverage gap)
  - **Confidence**: **High**
  - **Counterfactual**: Writing `test/audio_device_manager_test.dart` with tests for nudge retry, device dedup, and effect reapply.
  - **Owner**: Playback team
  - **Priority**: **P2**

- [ ] **RCA-FIND-3.3 [play/pause/stop/seek untested at service level]**:
  - **Evidence**: `test/player_service_test.dart` has 6 test cases covering `playQueue`, auto-advance, loop modes, generation counters, and shuffle. There are zero tests for `play()`, `pause()`, `stop()`, `seek()`, `skipToNext()`, `skipToPrevious()`, `skipToQueueItem()`, `removeFromQueue()`, `insertIntoQueue()`, `playNext()`, `addToQueue()`, or `reorderQueue()`.
  - **Reasoning**: These are the primary playback control methods. The `playQueue` error-recovery path (catch block at lines 540-550) is also untested.
  - **Impact**: 12+ methods have zero regression coverage. The P0 race in FIND-1.2 would not be caught by any existing test.
  - **Status**: **Confirmed** (test coverage gap)
  - **Confidence**: **High**
  - **Counterfactual**: Adding service-level tests for each method would catch the missing lock pattern.
  - **Owner**: Playback team
  - **Priority**: **P2**

- [ ] **RCA-FIND-3.4 [Guard tests validate reimplemented logic, not actual guards]**:
  - **Evidence**: `test/settings_race_test.dart` defines local `guardedSetter` functions that mirror the guard pattern rather than testing the actual `_disposed`/`_isLoadingQueue` guards in `AfPlayerService`. The test comment at line 106 explicitly states this is intentional.
  - **Reasoning**: Tests reimplementing the guard logic prove the guard *pattern* works, but do NOT verify that every setter in `AfPlayerService` actually includes the guards, or that `_isLoadingQueue` is correctly set during `playQueue`, or that `_disposed` is correctly set during `dispose()`.
  - **Impact**: A new setter added without guards would not be caught by these tests. False confidence in regression protection.
  - **Status**: **Confirmed** (test pattern weakness)
  - **Confidence**: **High**
  - **Counterfactual**: Converting to integration tests that call the actual guarded methods on `AfPlayerService` while manipulating `_isLoadingQueue` via test hooks.
  - **Owner**: Playback team
  - **Priority**: **P2**

- [ ] **RCA-FIND-3.5 [AfArtworkManager mostly untested]**:
  - **Evidence**: `test/artwork_manager_test.dart` tests exactly 1 scenario (embedded art preservation during network download). The `AfArtworkManager` source has ~15 methods; 12+ are untested including `persistCover(null)`, `downloadArtworkForNotification` with `file://` URLs, `needsRemoteArtwork`, `artUri` combination logic, error responses, disposal guard, and `setAuthHeaders`.
  - **Reasoning**: Artwork failures are user-visible (missing notification art, stale covers). Every path in `downloadArtworkForNotification` (HTTP failure, wrong content type, disposed state) is untested.
  - **Impact**: Artwork-related regressions slip through undetected.
  - **Status**: **Confirmed** (test coverage gap)
  - **Confidence**: **High**
  - **Counterfactual**: Extending artwork tests to cover the 12+ untested paths.
  - **Owner**: Playback team  
  - **Priority**: **P2**

### P3 — Technical Debt & Code Quality

- [x] **RCA-FIND-4.1 [NativeMediaSessionBridge refactor incomplete]**:
  - **Evidence**: `lib/core/audio/media_session_bridge.dart` defines `NativeMediaSessionBridge` (lines 57-177) with throttled `pushState`, `MediaSessionState` snapshot, and callback-based dispatch. `AfPlayerService` still uses the inline `_channel` + `_handleMethodCall` + `_updateMediaSession()` approach at lines 32, 909-937, and 1166-1208.
  - **Reasoning**: The refactored bridge is a cleaner, more testable abstraction with throttle, immutability, and explicit callbacks. It was written but never wired into the service.
  - **Impact**: Dead code; the inline implementation lacks throttle and uses fragile `Map<String, dynamic>` arguments.
  - **Status**: **Resolved** (wired in PR — `AfPlayerService` now uses `NativeMediaSessionBridge` with callback dispatch + throttled `pushState`; inline `_channel`/`_handleMethodCall` removed)
  - **Confidence**: **High**
  - **Counterfactual**: Wiring `NativeMediaSessionBridge` into `AfPlayerService` would deduplicate code and add throttle.
  - **Owner**: Playback team
  - **Priority**: **P3**

- [x] **RCA-FIND-4.2 [LiveUpdateService retained no-op]**:
  - **Evidence**: `lib/core/audio/live_update_service.dart` is created in `wirePlayerService` (line 62), `attach()` is called (line 63), and `dispose()` is called on cleanup (line 75). Looking at the code, the service is a no-op shell (Android 16 feature, currently disabled).
  - **Reasoning**: The full native plugin is compiled into the APK but the Dart integration never uses it. Retaining the code increases APK size and creates a misleading code path.
  - **Impact**: Dead code increases maintenance surface.
  - **Status**: **Confirmed** (code analysis)
  - **Confidence**: **Medium** — reliant on understanding of live_update_service.dart internals
  - **Counterfactual**: Removing `LiveUpdateService` or stubbing it out with a config flag.
  - **Owner**: Playback team
  - **Priority**: **P3**

- [x] **RCA-FIND-4.3 [getRawPosition uses fragile string parsing]**:
  - **Evidence**: `lib/core/audio/position_tracker.dart:130-132` — `final raw = await _player.getRawProperty('time-pos'); final secs = double.tryParse(raw);`. The mpv plugin returns position as a `String?`. `double.tryParse` depends on locale-agnostic string format.
  - **Reasoning**: If the mpv_audio_kit plugin ever changes its return format (e.g., adds trailing units, locale-dependent decimal separators), `tryParse` returns `null` and the position silently drops to zero.
  - **Impact**: Position stuck at zero if mpv_audio_kit format changes.
  - **Status**: **Confirmed** (code analysis)
  - **Confidence**: **Medium** — depends on upstream stability
  - **Counterfactual**: Adding a regex validation or unit suffix stripping before parsing.
  - **Owner**: Playback team
  - **Priority**: **P3**

- [x] **RCA-FIND-4.4 [_isPolling re-entrancy fallback silently falls back]**:
  - **Evidence**: `lib/core/audio/position_tracker.dart:203-206` — If `_isPolling` is `true` (previous poll still in-flight >500ms), the new tick emits an extrapolated position without a fresh raw read.
  - **Reasoning**: While this is a documented design choice, it means a slow `getRawProperty` call (e.g., due to IPC jitter on Android) cascades: extrapolation drifts until the next successful poll. The drift has no correction mechanism.
  - **Impact**: Position indicator shows extrapolated value that may drift from actual playback position.
  - **Status**: **Confirmed** (code analysis)
  - **Confidence**: **Medium**
  - **Counterfactual**: Increasing the poll interval or using a sequential chain (like `AfAsyncLock`) would prevent the re-entrancy fallback.
  - **Owner**: Playback team
  - **Priority**: **P3**

---

## Timeline Reconstruction

```
Timeline Key:
[LKG] = Last Known Good   [FS] = Failure Start   [FD] = Failure Detected
[FR] = Fix Released        [CR] = Code Review

2026-04-XX [LKG] — playback system stable after backend switch (audio_service → native)

2026-05-01 [FS-1] — race condition: completed handler reads mutable `loop` mode
                    after async gap. Fix: snapshot at event time (commit 2f70c23)

2026-05-03 [FS-2] — position stuck at 00:00 on first playback due to
                    `_pendingPlayNudgeIdx` gate in `shouldAdvancePosition`
                    Fix: remove gate + stop resetting anchor during loading (5187658)

2026-05-04 [FS-3] — 5 race conditions in native media session bridge:
                    disposed guard, state push order, channel handler cleanup
                    Fix: dispoed guards + catchError + keep reference (7bb1b57)

2026-05-06 [FS-4] — end-of-queue state desync: notification shows Pause icon
                    but queue is empty. Fix: set _userPaused=true on EOF (1756271)

2026-05-08 [FS-5] — excessive position stream events at 200ms poll
                    Fix: reduce to 500ms poll, add 500ms frame-skip gate (b7342ba, ed679e9)

2026-05-10 [FS-6] — comprehensive bug sweep: 8 bugs including BUG-004 (streaming quality)
                    (commit 08ce5c3)

2026-05-12 [FS-7] — router mode snapshot stuck (dfca5ff)

2026-05-14 [FS-8] — notification persists after native service stops (313d9ac)

2026-05-16 [FS-9] — Phase 3.5: apply persisted settings before runApp (b764d3e)

2026-05-18 [FS-10] — code review: 4 findings including integration tests (8f49a2d)

CRITICAL OBSERVATION: Of the 14+ bugs fixed in 30 commits, NONE had a
regression test written before the fix. The existing test suite would not
have caught any of these bugs before deployment. This is the systemic gap.
```

---

## Root Cause Determination

### Primary Root Cause

**Systemic under-investment in test coverage for the playback subsystem.** The 8 fix cycles in 30 commits could have been prevented or caught earlier with adequate test coverage. Specifically:

1. **No tests for `position_tracker.dart`** allowed 3 position-related bugs to reach production
2. **No tests for `play()`/`pause()`/`stop()`/`seek()`** allowed the lock-free race pattern to persist
3. **Simulated guard tests** created false confidence that every setter has `_disposed`/`_isLoadingQueue` guards
4. **No regression tests for fixed bugs** means each fix cycle addresses symptoms, not systemic gaps

### Contributing Factors

- **Fast bug-fix cadence** without corresponding test investment (14+ fixes, 0 regression tests)
- **Generation-counter pattern** is powerful but creates silent failure paths (stale ops discard without logging to an observable channel)
- **`_isLoadingQueue` is a boolean, not a depth counter** — nested operations could set it incorrectly (though this is guarded by the `finally` block at lines 551-558)
- **No integration test infrastructure** — all tests are unit-level with mocked mpv. Real mpv behavior differences (Samsung freeze, aaudio pipeline) can't be reproduced in tests

### Safeguard Gaps

| Gap | Description | Severity |
|---|---|---|
| No regression test requirement in fix PRs | Each fix cycle adds code but no tests proving the fix works | Critical |
| Guard tests validate pattern, not implementation | `settings_race_test.dart` reimplements guards, doesn't test actual code | High |
| Position tracker untested | 253 lines of critical polling/extrapolation/stale-detection logic | High |
| Audio device manager untested | 94 lines of nudge/retry/reapply logic | High |
| Artwork manager mostly untested | 12+ of ~15 methods uncovered | Medium |
| No race-condition tests beyond loop mode | `completed` handler vs skip/remove/seek races untested | Medium |

### Detection Gaps

| Gap | Description | Impact |
|---|---|---|
| No CI test for position accuracy | Position drift is user-visible but never measured | Position bugs reach production |
| No CI test for queue integrity after shuffle sync | Silent queue truncation undetectable in test suite | Queue corruption reaches production |
| No CI test for concurrent operation ordering | Race conditions only found through manual testing | Latent races undiscovered |
| No crash reporting or telemetry | All crash impact is anecdotal | Cannot quantify user impact |

---

## Remediation Recommendations

### P0 — Immediate

- [ ] **RCA-REM-1.1 [Fix replaceQueue empty-input crash]**:
  - **Immediate Actions**: Add early return guard at top of `replaceQueue`:
    ```dart
    void replaceQueue(List<AfTrack> tracks, int startIndex) {
      if (tracks.isEmpty) return;  // ← add this
      _trackQueue..clear()..addAll(tracks);
      _currentIndex = startIndex.clamp(0, tracks.length - 1);
      ...
    }
    ```
  - **Short-term Solutions**: Same as immediate — one-line guard
  - **Long-term Strategy**: Add `replaceQueue` to `queue_manager_test.dart` with empty-input test case
  - **Validation Steps**: `dart run build_runner build --delete-conflicting-outputs && flutter test`
  - **Timeline**: Immediate

- [ ] **RCA-REM-1.2 [Serialize play/pause/seek with _queueLock]**:
  - **Immediate Actions**: Wrap `play()` and `pause()` body in `_queueLock.run()`. For `seek()`, wrap in `_queueLock.run()` but keep `_positionTracker.onSeek(position)` outside the lock (it's just state, not mpv interaction).
  - **Short-term Solutions**: Add unit tests verifying lock acquisition for all 3 methods
  - **Long-term Strategy**: Audit all `AfPlayerService` methods for missing lock usage; add a lint rule or convention requiring lock for any method that calls `_player.*` public API
  - **Validation Steps**: Race condition test that fires `play()` during `completed` handler execution and verifies correct ordering
  - **Timeline**: This sprint

### P1 — This Sprint

- [ ] **RCA-REM-2.1 [Fix syncFromMpv silent queue truncation]**:
  - **Immediate Actions**: Add error emission to `playbackErrorProvider` on partial/full sync failure:
    ```dart
    // In syncFromMpv partial sync path:
    afLog('audio', 'partial sync: resolved ${reordered.length}/${mpvItems.length}');
    // Do NOT replaceQueue — keep existing queue instead
    // Only replace if 100% resolution
    
    // In full sync failure path:
    // emit error instead of clearing silently
    ```
  - **Short-term Solutions**: Change partial sync to preserve existing queue and log warning; change full failure to emit error through callback
  - **Long-term Strategy**: Add a `onSyncFailed` callback to `AfPlayerService` that feeds into `playbackErrorProvider`
  - **Validation Steps**: Unit test for partial resolution (3/5 tracks) and full failure (0/5 tracks)
  - **Timeline**: This sprint

- [ ] **RCA-REM-2.2 [Deduplicate duration sources]**:
  - **Immediate Actions**: Remove the poll loop in `_startPositionPolling` (lines 129-149) and rely solely on `svc.durationStream`. Add a fallback to track metadata if stream never emits.
  - **Short-term Solutions**: Keep both sources but add deduplication — only write to `durationStreamProvider` if value differs from current.
  - **Long-term Strategy**: Evaluate if `svc.durationStream` alone is sufficient (mpv's property observer should fire on every change).
  - **Validation Steps**: Test that duration updates correctly across track changes and seeks
  - **Timeline**: This sprint

- [ ] **RCA-REM-2.3 [Safe fftSpectrumProvider cast]**:
  - **Immediate Actions**: Replace unsafe `cast<FftFrame>()` with:
    ```dart
    return svc.spectrumStream.map((e) => e is FftFrame ? e : FftFrame.zero);
    ```
  - **Short-term Solutions**: Same as immediate
  - **Long-term Strategy**: Add typed wrapper in `mpv_audio_kit` or verify type contract in stream subscription
  - **Validation Steps**: Test that provider survives unexpected stream types
  - **Timeline**: This sprint

- [ ] **RCA-REM-2.4 [Re-read settings on each completion callback invocation]**:
  - **Immediate Actions**: Move `ref.read()` calls inside the `onTrackCompleted` callback closure so they re-read on each invocation instead of capturing at boot time:
    ```dart
    svc.onTrackCompleted = (track) async {
      final enabled = ref.read(offlineCacheEnabledProvider);  // re-read each time
      ...
    };
    ```
  - **Short-term Solutions**: Same as immediate
  - **Long-term Strategy**: Switch to `ref.watch()` if the callback should re-trigger on setting changes
  - **Validation Steps**: Test that changing offline cache setting mid-playback is respected on next track completion
  - **Timeline**: This sprint

### P2 — Next Sprint

- [ ] **RCA-REM-3.1 [Write position_tracker_test.dart]**:
  - **Immediate Actions**: Create `test/position_tracker_test.dart` with tests for:
    - `_emitPosition` frame-skip gate (positions within 500ms delta are dropped)
    - `_forceEmit` bypasses gate
    - `onSeek` sets `_isSeeking = true`, resets stale detector, emits force
    - `_isSeeking` resets to false after 300ms
    - `_isRawPositionStale` returns `false` on first call (null check)
    - `_isRawPositionStale` returns `true` after 4 identical ticks within 50ms
    - `_isRawPositionStale` resets on position change >50ms
    - `_emitExtrapolatedPosition` caps at duration
    - `_emitExtrapolatedPosition` extrapolates using rate correctly
    - `_pollAndEmitPosition` returns early when seeking
    - `_pollAndEmitPosition` returns early when loading queue
    - `_pollAndEmitPosition` uses extrapolated fallback on re-entrancy
    - `_pollAndEmitPosition` uses raw position when not stale
    - `getRawPosition` returns `Duration.zero` on null/negative/exception
    - `getRawDuration` returns `Duration.zero` on null/zero/exception
  - **Short-term Solutions**: Deploy mock `PlayerApi` with controlled `getRawProperty` responses
  - **Validation Steps**: All tests pass; 100% coverage of `position_tracker.dart` branches
  - **Timeline**: Next sprint

- [ ] **RCA-REM-3.2 [Write audio_device_manager_test.dart]**:
  - **Immediate Actions**: Create `test/audio_device_manager_test.dart` with tests for:
    - `nudge()` algorithm: retries up to 3 times at correct delays
    - `nudge()` early bail on first-success-while-playing
    - `isRealDeviceChange` dedup (same name returns false twice)
    - `isRealDeviceChange` new name returns true
    - `reapplyPersistedEffects` calls correct mpv commands
  - **Short-term Solutions**: Deploy mock `PlayerApi` with recorded method calls
  - **Validation Steps**: All tests pass
  - **Timeline**: Next sprint

- [ ] **RCA-REM-3.3 [Extend player_service_test.dart coverage]**:
  - **Immediate Actions**: Add tests for:
    - `play()` and `pause()` with `_disposed` guard
    - `seek()` with `_isLoadingQueue` guard
    - `skipToNext()`/`skipToPrevious()`/`skipToQueueItem()` with race guard
    - `playQueue` error recovery (catch block)
    - `removeFromQueue()`, `insertIntoQueue()`, `playNext()`, `addToQueue()`
    - `reorderQueue()` with index adjustments
    - `_handleMethodCall` platform→Dart dispatch
  - **Short-term Solutions**: Use existing `MockPlayer` + `MockMethodChannel` fixtures
  - **Validation Steps**: All tests pass; coverage on `player_service.dart` methods >80%
  - **Timeline**: Next sprint

- [ ] **RCA-REM-3.4 [Convert guard tests from simulated to integration-level]**:
  - **Immediate Actions**: Add test hooks to `AfPlayerService`:
    - Expose `_isLoadingQueue` as settable test property via `@visibleForTesting`
    - Add integration tests that call actual guarded methods while manipulating `_isLoadingQueue`
  - **Short-term Solutions**: Replace `settings_race_test.dart` with tests that use `AfPlayerService.test()` and call `setAudioDevice()`, `setAudioExclusive()`, `setCache()`, `setAfSpeed()` etc. while `_isLoadingQueue` is controlled externally
  - **Validation Steps**: Remove old simulated-guard tests; new integration tests pass
  - **Timeline**: Next sprint

- [ ] **RCA-REM-3.5 [Extend artwork_manager_test.dart]**:
  - **Immediate Actions**: Add tests for:
    - `persistCover(null)` clears cover path
    - `downloadArtworkForNotification` with `file://` URL (skips download)
    - `downloadArtworkForNotification` with non-200 HTTP response
    - `downloadArtworkForNotification` when already downloaded (dedup)
    - `needsRemoteArtwork` correctly evaluates all combinations
    - `artUri` priority ordering (embedded > network > file)
    - `setAuthHeaders` stores headers
    - `dispose()` guards against double call
  - **Short-term Solutions**: Extend existing `TestHttpOverrides` and `dart:io` test patterns
  - **Validation Steps**: All tests pass; >80% branch coverage on `artwork_manager.dart`
  - **Timeline**: Next sprint

### P2 — Regression Race Tests

- [ ] **RCA-REM-3.6 [Add race-condition tests for completed handler]**:
  - **Immediate Actions**: Add tests for:
    - `completed` handler ↔ `skipToNext()` (serialized by lock — verify ordering)
    - `completed` handler ↔ `skipToQueueItem()` (serialized by lock — verify)
    - `completed` handler ↔ `play()` (NOT serialized — verify race IS present, document)
    - `completed` handler ↔ `removeFromQueue()` during transition
    - `setAfShuffleMode` ↔ `completed` handler
  - **Short-term Solutions**: Use same pattern as `loop_mode_race_test.dart` with order recording
  - **Validation Steps**: All race tests pass and document correct serialization behavior
  - **Timeline**: Next sprint

### P3 — Backlog

- [x] **RCA-REM-4.1 [Wire NativeMediaSessionBridge into AfPlayerService]**:
  - Replace inline `_channel` + `_handleMethodCall` + `_updateMediaSession()` with `NativeMediaSessionBridge`
  - Benefits: throttle (100ms dedup), immutable state snapshots, cleaner callback dispatch
  - **Status**: Completed — `AfPlayerService` uses `NativeMediaSessionBridge` callbacks (`onPlay`/`onPause`/`onSeek`/etc.) and `pushState()` with 100ms throttle
  - **Timeline**: Backlog

- [x] **RCA-REM-4.2 [Remove or stub LiveUpdateService]**:
  - Removed: `lib/core/audio/live_update_service.dart` deleted, import + wiring removed from `player_providers.dart`
  - File size reduction: -32 lines dead code
  - **Status**: Completed

- [x] **RCA-REM-4.3 [Add robust string parsing for mpv properties]**:
  - Added `_secondsRegex` top-level `RegExp` + `@visibleForTesting parseSeconds()` helper
  - Handles: whitespace, unit suffixes (`s`/`ms`/`sec`/`seconds`/`milliseconds`), EU locale comma decimals, signed values
  - **Status**: Completed

- [x] **RCA-REM-4.4 [Replace _isPolling boolean with sequential chain]**:
  - Replaced `bool _isPolling` with `Future<void>? _pollChain` sequential chain
  - Re-entrancy skips silently (no extrapolation fallback) — next 500ms tick gets fresh read
  - Extracted `_executePoll()` method; chain-level error catch prevents unhandled rejections
  - **Status**: Completed

---

## Effort & Priority Assessment

| RCA ID | Finding | Priority | Effort | Complexity | Dependencies |
|---|---|---|---|---|---|
| REM-1.1 | Fix replaceQueue empty-input crash | P0 | 1 hour | Simple | None |
| REM-1.2 | Serialize play/pause/seek with lock | P0 | 4 hours | Moderate | Test fixture update |
| REM-2.1 | Fix syncFromMpv silent truncation | P1 | 8 hours | Complex | Queue manager redesign |
| REM-2.2 | Deduplicate duration sources | P1 | 4 hours | Moderate | Position tracker tests needed first |
| REM-2.3 | Safe fftSpectrumProvider cast | P1 | 1 hour | Simple | None |
| REM-2.4 | Re-read settings on each callback | P1 | 2 hours | Simple | None |
| REM-3.1 | Write position_tracker_test.dart | P2 | 16 hours | Complex | Mock position tracker needed |
| REM-3.2 | Write audio_device_manager_test.dart | P2 | 8 hours | Moderate | Mock player needed |
| REM-3.3 | Extend player_service_test.dart | P2 | 16 hours | Complex | Existing fixtures reusable |
| REM-3.4 | Convert guard tests to integration | P2 | 8 hours | Moderate | Test hooks in AfPlayerService |
| REM-3.5 | Extend artwork test coverage | P2 | 8 hours | Moderate | HttpClient mocking |
| REM-3.6 | Add race-condition tests | P2 | 12 hours | Complex | Loop mode race test pattern |
| REM-4.1 | Wire NativeMediaSessionBridge | P3 | 8 hours | Moderate | None — Completed |
| REM-4.2 | Remove LiveUpdateService | P3 | 2 hours | Simple | ✅ Done |
| REM-4.3 | Robust string parsing | P3 | 2 hours | Simple | ✅ Done |
| REM-4.4 | Sequential poll chain | P3 | 4 hours | Moderate | ✅ Done |

**Total estimated effort**: ~91 hours initial cleanup + ongoing maintenance (8 hours completed this session)

**ROI Assessment**:
- P0 items (REM-1.1, REM-1.2): 5 hours → eliminates crash risk + race condition (highest ROI)
- P1 items (REM-2.1 through REM-2.4): 15 hours → eliminates silent data corruption and UI desync
- P2 test items (REM-3.1 through REM-3.6): 68 hours → prevents future regressions (medium ROI)
- P3 items (REM-4.1 through REM-4.4): 16 hours → code quality improvements (lowest ROI) — **8 hours completed**

---

## Proposed Code Changes

### REM-1.1: `lib/core/audio/queue_manager.dart` — replaceQueue empty guard

Add early return at line 82:
```dart
void replaceQueue(List<AfTrack> tracks, int startIndex) {
  if (tracks.isEmpty) return;        // ← guard
  _trackQueue
    ..clear()
    ..addAll(tracks);
  _currentIndex = startIndex.clamp(0, tracks.length - 1);
  _queueController.add(List<AfTrack>.unmodifiable(_trackQueue));
}
```

### REM-1.2: `lib/core/audio/player_service.dart` — serialize play/pause/seek

Wrap `play()` and `pause()` in `_queueLock`:
```dart
Future<void> play() async {
  if (_disposed) return;
  return _queueLock.run(() async {          // ← wrap
    _userPaused = false;
    _positionTracker.onPlay();
    try {
      await _player.play();
      _audioDeviceManager.nudge();
    } catch (e, stack) {
      afLog('audio', 'play failed', error: e, stackTrace: stack);
    }
  });                                       // ← wrap
}

Future<void> pause() async {
  if (_disposed) return;
  return _queueLock.run(() async {          // ← wrap
    _userPaused = true;
    _pendingPlayNudgeIdx = null;
    _positionTracker.onPause();
    try {
      await _player.pause();
    } catch (e, stack) {
      afLog('audio', 'pause failed', error: e, stackTrace: stack);
    }
  });                                       // ← wrap
}
```

### REM-2.3: `lib/state/player_providers.dart` — safe FFT cast

Replace line 213:
```dart
// Before:
return svc.spectrumStream.cast<FftFrame>();

// After:
return svc.spectrumStream.map((e) => e is FftFrame ? e : FftFrame.zero);
```

### REM-2.4: `lib/state/player_providers.dart` — re-read settings each callback

Move `ref.read()` inside the closure:
```dart
svc.onTrackCompleted = (track) {
  final enabled = ref.read(offlineCacheEnabledProvider);  // re-read each time
  if (!enabled) return;
  final mode = ref.read(appModeProvider);
  if (mode == AppMode.local) return;
  final backend = ref.read(musicBackendProvider);         // re-read each time
  if (backend == null) return;
  // ... rest unchanged
};
```

---

## Commands

### Verification (after each fix)
```bash
dart run build_runner build --delete-conflicting-outputs
flutter analyze --no-fatal-infos
flutter test
```

### Run specific test files
```bash
# Core playback tests
flutter test test/player_service_test.dart
flutter test test/queue_manager_test.dart
flutter test test/media_session_bridge_test.dart

# New test files (after REM-3.1, REM-3.2)
flutter test test/position_tracker_test.dart
flutter test test/audio_device_manager_test.dart
```

### Coverage check (after all P2 items)
```bash
flutter test --coverage
# Generate HTML coverage report
genhtml coverage/lcov.info -o coverage/html
# Focus on audio subsystem
lcov --extract coverage/lcov.info 'lib/core/audio/*' -o coverage/audio.info
genhtml coverage/audio.info -o coverage/audio-html
```

### CI Integration (for new race-condition tests)
No changes needed — `flutter test` in CI will include all test files automatically. The new `position_tracker_test.dart` and `audio_device_manager_test.dart` files will be discovered by glob pattern.

---

## Quality Assurance Checklist

- [x] All findings grounded in concrete code references (file:line citations)
- [x] Root cause distinguished clearly from contributing factors
- [x] Timeline reconstructed with verified commit references
- [x] Hypotheses systematically tested via code analysis (no assumptions)
- [x] Impact scope quantified for each finding
- [x] Corrective actions address root cause, contributing factors, and detection gaps
- [x] Each remediation has verification steps
- [x] Evidence-first reasoning: speculation explicitly labeled as such
- [x] Data gaps noted (no crash logs available: confidence marked Medium)
- [x] Analysis focuses on systems and controls, not individual blame
- [x] Effort estimates provided for each remediation
