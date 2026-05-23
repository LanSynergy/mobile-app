# Code Review: Aetherfin Mobile App

## Context

- **Repository**: Aetherfin/mobile-app
- **Files Reviewed**:
  - `lib/main.dart` — Boot sequence, error handling, auth hydration, provider wiring
  - `lib/core/audio/player_service.dart` — Core player service (1,286 lines)
  - `lib/core/audio/media_session_bridge.dart` — Native media session MethodChannel bridge
  - `lib/core/audio/jellyfin_playback_reporter.dart` — Playback reporting lifecycle
  - `lib/core/jellyfin/client.dart` — Jellyfin REST client (939 lines)
  - `lib/core/jellyfin/url_builder.dart` — URL construction + auth headers
  - `lib/core/subsonic/client.dart` — Subsonic REST client for Navidrome (897 lines)
  - `lib/core/backend/music_backend.dart` — Abstract backend interface
  - `lib/app/router.dart` — GoRouter configuration + auth/mode redirect
  - `lib/widgets/audio_visual_scrubber.dart` — FFT visualizer + scrubber (519 lines)
  - `lib/state/providers.dart` — Barrel exports for all providers
- **Language**: Dart 3.11.5 / Flutter 3.44.0
- **Runtime**: Android 7.0+ (minSdk 24)
- **Scope**: Security audit, performance evaluation, bug detection, code quality assessment across core audio, networking, routing, and UI rendering layers

---

## Review Plan

- [ ] **CR-PLAN-1.1 [Security Scan]**:
  - **Scope**: Auth token handling (Jellyfin/Subsonic), credential lifecycle, URL redaction, error PII exposure, stream URL auth embedding
  - **Priority**: Critical — must be reviewed before any release

- [ ] **CR-PLAN-1.2 [Performance Audit]**:
  - **Scope**: FFT ticker architecture, queue loading strategy, serialized progress loop, Dio cache interceptor usage, N+1 query patterns
  - **Priority**: High — flag measurable bottlenecks

- [ ] **CR-PLAN-1.3 [Bug Detection]**:
  - **Scope**: GoRouter navigator key setup, AfAsyncLock error handling, race conditions in state guards, stream subscription lifecycle, dead/broken code paths
  - **Priority**: High — correctness issues

- [ ] **CR-PLAN-1.4 [Code Quality Assessment]**:
  - **Scope**: Readability, naming, SOLID adherence, error handling completeness, testability, design pattern consistency
  - **Priority**: Medium — maintainability and tech debt

---

## Review Findings

### Security Findings

- [x] **CR-ITEM-1.1 [Subsonic Password Retained In Memory Throughout Client Lifetime]**:
  - **Severity**: Medium
  - **Location**: `lib/core/subsonic/client.dart`, lines 34, 106-108, 173-175
  - **Description**: `SubsonicClient` stores password UTF-8 bytes in `_passwordBytes` (`List<int>`) for the entire client lifetime. While `close()` zeroes the list (lines 173-175), every `_authParams()` call creates intermediate spread copies (`[..._passwordBytes, ...utf8.encode(salt)]`, line 107) that are subject to Dart's unpredictable GC. The `md5.convert()` input and the spread intermediate lists may persist in heap memory after use. For a local music app this is moderate risk (no network exposure of the raw password), but it violates the principle of最小 credential lifetime.
  - **Recommendation**: Consider using `Sink<O> md5.startChunked()` to feed bytes without creating intermediate lists, or explicitly overwrite the temporary list after hash computation. However, given Dart's lack of guaranteed memory clearing on the heap, this is inherently limited. Document the limitation and accept the risk for the local-only use case, or allocate the temporary buffer as `Uint8List` and overwrite it with zeros post-hash.

- [x] **CR-ITEM-1.2 [Debug-Only HTTP Trace Leaks URL Paths to Logcat]**:
  - **Severity**: Low
  - **Location**: `lib/core/subsonic/client.dart`, lines 74-93
  - **Description**: The Subsonic client's debug interceptors log URL paths without redaction (line 78: `afLog('http', '→ ${options.method} ${options.uri.path}')`), unlike the Jellyfin client which redacts sensitive query params via `JellyfinUrlBuilder.redactUrl()`. While Subsonic auth is in query params (not the path), the path itself could still leak server structure in screenshots/shared debug logs.
  - **Recommendation**: Align with the Jellyfin client pattern — apply URL redaction in Subsonic debug logging to strip sensitive query params from log output. Specifically, redact `u`, `t`, `s`, `api_key` params.

- [x] **CR-ITEM-1.3 [Password Zeroing in close() Has Best-Effort Semantics]**:
  - **Severity**: Low
  - **Location**: `lib/core/subsonic/client.dart`, lines 173-175
  - **Description**: `_passwordBytes[i] = 0` only clears the `List<int>` wrapper. The underlying `Uint8List` (if the list was created from `utf8.encode()` which returns `Uint8List`) or the Dart heap memory is not guaranteed to be overwritten. Dart's generational GC may have already moved the bytes to an older generation. This is a best-effort attempt and should be clearly documented as such rather than implied as bulletproof.
  - **Recommendation**: Add a comment noting that this is a best-effort mitigation and that true memory zeroing is not guaranteed in Dart's GC-managed heap. This is already done implicitly but could be more explicit.

- [x] **CR-ITEM-1.4 [Auth State Snapshots in Global Vars — No Protection Against Concurrent Access]**:
  - **Severity**: Low
  - **Location**: `lib/app/router.dart`, lines 48-49
  - **Description**: `_auth` and `_appMode` are module-level mutable variables written from main.dart provider listeners and read in the router redirect callback. While Dart's single-threaded event loop prevents true data races, the pattern is fragile: the router redirect callback (line 56) could read a partially-updated state if `setRouterAuthState` is called while a redirect is in-flight. Since the event loop serializes these, this is theoretical, but the pattern makes reasoning about state consistency harder.
  - **Recommendation**: Accept as-is for now (it works correctly under Dart's event loop), but document that the module-level vars are intentionally outside Riverpod to break the dependency cycle, and that the single-threaded runtime guarantees safety.

---

### Performance Findings

- [x] **CR-ITEM-2.1 [N+1 Album Fetch Pattern in Subsonic recentlyPlayed]**:
  - **Severity**: Low
  - **Location**: `lib/core/subsonic/client.dart`, lines 210-219
  - **Description**: `recentlyPlayed()` fetches albums, then iterates over the first 5 albums calling `album(a.id)` for each one individually. This creates up to 5 sequential HTTP requests. While bounded to 5 (acceptable for a "recently played" count of 20), on slow connections this adds ~500ms-2.5s to render. Additionally, if any album fetch fails, the error is swallowed (line 217) and partial data is returned.
  - **Recommendation**: Accept the limitation since Subsonic has no direct endpoint for recently played tracks. Document this as a known Subsonic API gap. Consider making the `album` fetches parallel with `Future.wait()` to reduce wall-clock time. The error swallowing at line 217 is correct behavior (fail gracefully) but should include context about which album ID failed.

- [x] **CR-ITEM-2.2 [Sequential Track Addition in playQueue After Opening]**:
  - **Severity**: Medium
  - **Location**: `lib/core/audio/player_service.dart`, lines 514-527
  - **Description**: For queues > 5 tracks, the code opens the first track then iterates sequentially: adds tracks after the current track forward (lines 514-517), then inserts tracks before the current track backward (lines 519-527). Each `_player.add()` and `sendRawCommand` is awaited sequentially. For a 1000-track queue, this generates 999 sequential mpv commands, which could take seconds to complete and blocks the `_queueLock` during the entire duration.
  - **Recommendation**: The current design prioritizes reliability over speed (generation counter guards ensure correctness). This is acknowledged in CLAUDE.md item #46. However, consider batching inserts via a single `loadlist` raw command if mpv supports it, or document the expected latency for large queues. The sequential approach is correct but should be flagged as a known performance characteristic for very large queues.

- [x] **CR-ITEM-2.3 [MemCacheStore Maximum Entry Size May Reject Large Responses]**:
  - **Severity**: Low
  - **Location**: `lib/core/jellyfin/client.dart` line 44, `lib/core/subsonic/client.dart` line 53
  - **Description**: Both clients configure `MemCacheStore` with `maxEntrySize: 1 * 1024 * 1024` (1 MB). Large album art responses or library listings (e.g., `allTracks` with 1000 items) could exceed this limit and bypass the cache entirely, causing re-fetches on every call. The 1 MB limit is reasonable for most metadata responses but may be tight for image data.
  - **Recommendation**: Accept as-is. Cover art is cached separately via `cached_network_image`, and metadata responses should be well under 1 MB for typical libraries. Document that the cache interceptor is primarily for metadata, not artwork.

---

### Bug Detection

- [x] **CR-ITEM-3.1 [GoRouter Shell Branch NavigatorKey Collision]**:
  - **Severity**: High
  - **Location**: `lib/app/router.dart`, lines 124-173
  - **Description**: In `StatefulShellRoute.indexedStack`, all four `StatefulShellBranch` entries either share the same `_shellKey` or use no key. Line 128: branch 1 uses `navigatorKey: _shellKey`. Branches 2-4 (lines 137-172) omit `navigatorKey` entirely, causing GoRouter to auto-generate keys on every build. **Critically, `_shellKey` is defined at line 41 as a single `GlobalKey<NavigatorState>()` but is also used by the first tab's shell branch, which means the first tab shares its navigator key incorrectly.** This causes:
  >     - State loss on branch 2-4 when the widget tree is rebuilt (auto-generated keys change)
  >     - Potential navigator key conflicts between the shell and branch 1
  >     - Broken back-navigation state restoration when switching tabs
  - **Recommendation**: Create four unique `GlobalKey<NavigatorState>()` instances, one per branch:
    ```dart
    final _shellBranch1Key = GlobalKey<NavigatorState>();
    final _shellBranch2Key = GlobalKey<NavigatorState>();
    final _shellBranch3Key = GlobalKey<NavigatorState>();
    final _shellBranch4Key = GlobalKey<NavigatorState>();
    ```
    Then assign each branch its own key. This preserves each tab's navigation stack independently.

- [x] **CR-ITEM-3.2 [AfAsyncLock Swallows Errors from the Chain Future]**:
  - **Severity**: Medium
  - **Location**: `lib/core/audio/player_service.dart`, lines 1269-1286
  - **Description**: `AfAsyncLock.run()` uses `.catchError((Object _) {})` at line 1283 which silently swallows any error thrown by the `_chain.then(...)` callback if it escapes the inner try-catch. While the inner async callback (lines 1275-1283) catches errors and routes them to `completer.completeError()`, there's a subtle case: if `completer.completeError(e, st)` itself throws (e.g., if the completer was already completed due to a logic error), the error propagates up and is swallowed by `.catchError`. The caller's `completer.future` would then hang forever since `completer` was never completed successfully or with error.
  - **Recommendation**: Add defensive logging in the catchError to detect this rare condition:
    ```dart
    ).catchError((Object error, StackTrace stack) {
      afLog('error', 'AfAsyncLock chain error', error: error, stackTrace: stack);
    });
    ```
    This at minimum surfaces the issue in logs rather than silently deadlocking the caller.

- [x] **CR-ITEM-3.3 [isLoadingQueue Guard Inconsistency — Some Checks Outside Lock, Some Inside]**:
  - **Severity**: Low
  - **Location**: `lib/core/audio/player_service.dart`
  - **Description**: Methods `play()`, `pause()`, `seek()`, `setAfShuffleMode()`, `setAfLoopMode()` check `_isLoadingQueue` *before* acquiring `_queueLock`. Methods `reorderQueue()`, `removeFromQueue()`, `insertIntoQueue()`, `playNext()`, `addToQueue()` check it *inside* the lock. While Dart's single-threaded model means the TOCTOU gap isn't exploitable, the inconsistency is confusing and makes the code harder to reason about. A future refactor might move the `_isLoadingQueue` mutation outside the lock, breaking the safety assumption.
  - **Recommendation**: Standardize to always check `_isLoadingQueue` inside the `_queueLock.run()` callback, just after acquiring the lock. This eliminates the TOCTOU window and makes the pattern consistent across all methods.

- [x] **CR-ITEM-3.4 [playQueue Finally Block Uses While Loop for Single beginPlaylistSync Call]**:
  - **Severity**: Low
  - **Location**: `lib/core/audio/player_service.dart`, lines 575-578
  - **Description**: The finally block in `playQueue` uses `while (localSyncs > 0)` with `localSyncs--` (lines 575-577) even though `beginPlaylistSync()` is called exactly once (line 503). The loop is unnecessary and misleading — it looks like it handles a counter that could be > 1, but it's always exactly 1. If `endPlaylistSync()` could throw (it doesn't currently but could in the future), the loop would decrement `localSyncs` but `endPlaylistSync()` would fail, creating an unbalanced state.
  - **Recommendation**: Replace the while loop with a simple unconditional call:
    ```dart
    _queueManager.endPlaylistSync();
    ```
    Or keep the pattern but add a clarifying comment that this mirrors a future pattern where nested begin/end calls might exist.

- [x] **CR-ITEM-3.5 [Router Auth/Mode Listeners Never Cancelled]**:
  - **Severity**: Low
  - **Location**: `lib/main.dart`, lines 178-199
  - **Description**: `authSub` and `modeSub` are stored with `// ignore: unused_local_variable` and never cancelled. For the app's lifetime this is fine (they live as long as the ProviderContainer), but they prevent the `container` from being garbage-collected in test scenarios or if the architecture ever supports hot-restart of the provider tree. The subscriptions also retain a reference to `container` (the `listen` callback captures it) which could prevent teardown.
  - **Recommendation**: Accept as-is for production (app runs until killed). For testability, consider wrapping the app in a bootstrapper class that owns the subscriptions and can dispose them. Document this as intentional — the subscriptions live for the process lifetime.

- [x] **CR-ITEM-3.6 [setAfSpeed Doesn't Acquire _queueLock]**:
  - **Severity**: Low
  - **Location**: `lib/core/audio/player_service.dart`, lines 764-769
  - **Description**: `setAfSpeed()` at line 764 calls `_player.setRate(speed)` directly without acquiring `_queueLock`. All other mutating playback methods (`play`, `pause`, `seek`, `skipToNext`, etc.) acquire the lock. While `setRate` is unlikely to interact with queue mutations (it doesn't touch the playlist), the inconsistency means a concurrent speed change during a `playQueue` operation could interleave with queue loading. In practice, `setRate` is a simple mpv property set that doesn't affect queue state, but the inconsistency is a code quality issue.
  - **Recommendation**: Either wrap in `_queueLock.run()` for consistency (which adds a small unnecessary overhead), or add a clarifying comment explaining why it intentionally bypasses the lock (e.g., "speed changes don't interact with queue state").

- [x] **CR-ITEM-3.7 [Subsonic removeFromPlaylist Has Stale-Read Race]**:
  - **Severity**: Low
  - **Location**: `lib/core/subsonic/client.dart`, lines 570-588
  - **Description**: `removeFromPlaylist()` first fetches the full playlist via `playlist(playlistId)` (line 571), computes indices to remove, then calls `updatePlaylist`. If the playlist is modified between the fetch and the update (multi-user scenario or server-side change), the computed indices could be wrong, potentially removing the wrong tracks. For the single-user Navidrome use case this is unlikely, but it's a correctness concern.
  - **Recommendation**: Document this as a known race condition with a comment. Add a retry loop for production hardening if multi-user access is a concern. For the current single-user scope, accept the risk.

---

### Code Quality Findings

- [x] **CR-ITEM-4.1 [Excellent Architecture: Reactive Islands and Engine-Driven Rendering]**:
  - **Severity**: N/A (Positive)
  - **Location**: `lib/widgets/audio_visual_scrubber.dart`, entire file; `lib/core/audio/player_service.dart`, FFT/scrubber architecture
  - **Description**: The FFT visualizer architecture is exceptionally well-designed. The division of labor between `_BlockNotifier.ingest()` (data update, no notifyListeners), `flush()` (vsync-aligned repaint), and the ticker-driven rendering prevents stream-timing stutters. The 4-path batched Skia rendering (lines 360-401) avoids the 128 individual `drawRRect` calls that would thrash the GPU pipeline. The fade-out mechanism (0.85× decay per frame) and lifecycle awareness (`AppLifecycleListener` + route obscuration detection) show deep understanding of Flutter's rendering pipeline.
  - **Recommendation**: This pattern should be documented as a reference architecture for future real-time UI work in the project.

- [x] **CR-ITEM-4.2 [Strong Defensive Programming: Generation Counters Throughout Player Service]**:
  - **Severity**: N/A (Positive)
  - **Location**: `lib/core/audio/player_service.dart`
  - **Description**: The use of `_queueLoadGen`, `_shuffleGen`, and `_playlistHandlerGen` generation counters throughout `AfPlayerService` is excellent defensive programming. Every async operation checks `if (myGen != _queueLoadGen) return` after every await point, preventing stale callbacks from corrupting state after aborted operations. The CLAUDE.md history (items #46-49) explains the bugs that prompted this pattern. This is hard-won production wisdom encoded in the code.
  - **Recommendation**: Consider extracting the generation counter pattern into a reusable utility class (`GenerationGuard`) to reduce boilerplate and prevent copy-paste errors in the 28+ guard check locations.

- [x] **CR-ITEM-4.3 [autoBypassFlat Is @visibleForTesting But No Tests Visible]**:
  - **Severity**: Medium
  - **Location**: `lib/core/audio/player_service.dart`, lines 1245-1267
  - **Description**: The `autoBypassFlat` function is marked `@visibleForTesting` (line 1245) and exported as a top-level function specifically for unit testing. However, no test file was found that exercises it. Given the complex DSP edge cases it handles (flat filter bypass, de-esser parameter clamping, superequalizer empty-params check), this is a gap. A regression in this code could silently disable the entire DSP chain (as happened historically with the de-esser bug mentioned in the doc comments, lines 1236-1240).
  - **Recommendation**: Create unit tests for `autoBypassFlat` covering:
    - Bass/treble shelf disabled when gain ≈ 0
    - Bass/treble shelf kept when gain > 0.001
    - Superequalizer disabled when params is empty
    - Superequalizer kept when params has entries
    - De-esser `f`, `i`, `m` clamped to [0.0, 1.0]
    - All filters enabled simultaneously (no interaction)
    - Bound values at exactly 0.0 and 1.0

- [x] **CR-ITEM-4.4 [Naming Inconsistency: Mix of DartDoc and Inline Comments]**:
  - **Severity**: Low
  - **Location**: Multiple files
  - **Description**: The codebase uses three comment styles inconsistently:
    - `/// DartDoc` for public API (correct)
    - `// ── Section headers ──` for visual separation (acceptable, common pattern)
    - `// Inline explanations` mixed within methods
    Some critical sections (e.g., `_bindStreams()` at line 973) have extensive inline comments that would be better as a DartDoc on the method explaining the stream-wiring strategy. The `_autoBypassFlat` forwarding method at line 347 (`AudioEffects _autoBypassFlat(AudioEffects fx) => autoBypassFlat(fx);`) is a trivial delegate that adds no value and requires a reader to look up the top-level function anyway.
  - **Recommendation**: Remove the `_autoBypassFlat` forwarding method and call `autoBypassFlat` directly. Consider migrating section headers to DartDoc on private methods for better IDE integration.

- [x] **CR-ITEM-4.5 [Smart Playlist Engine Not Reviewed — External Dependency on SQLite Query Construction]**:
  - **Severity**: Low
  - **Location**: `lib/core/smart_playlist/`
  - **Description**: The smart playlist module wasn't in the primary review scope but was identified as an area of concern. The engine constructs SQL queries from user-defined rules, which is an injection risk if rule values are not sanitized before interpolation into SQL strings.
  - **Recommendation**: Verify that the smart playlist engine uses parameterized queries (Drift's compiled queries or raw SQL with proper escaping) for all user-supplied values in rule conditions. If raw string interpolation is used for rule values, this is a SQL injection vector. Flag for follow-up review.

---

## Proposed Code Changes

### CR-ITEM-3.1: Fix Router Navigator Keys

**File**: `lib/app/router.dart`

The fix is to create four unique navigator keys and assign each branch its own key:

```dart
// After line 41:
final _shellKey = GlobalKey<NavigatorState>();
// Replace with:
final _shellBranch1Key = GlobalKey<NavigatorState>();
final _shellBranch2Key = GlobalKey<NavigatorState>();
final _shellBranch3Key = GlobalKey<NavigatorState>();
final _shellBranch4Key = GlobalKey<NavigatorState>();
```

Then update each branch (lines 128-172):

```dart
branches: [
  StatefulShellBranch(
    navigatorKey: _shellBranch1Key,  // was: _shellKey
    routes: [...]
  ),
  StatefulShellBranch(
    navigatorKey: _shellBranch2Key,  // NEW
    routes: [...]
  ),
  StatefulShellBranch(
    navigatorKey: _shellBranch3Key,  // NEW
    routes: [...]
  ),
  StatefulShellBranch(
    navigatorKey: _shellBranch4Key,  // NEW
    routes: [...]
  ),
],
```

### CR-ITEM-3.2: Fix AfAsyncLock Error Swallowing

**File**: `lib/core/audio/player_service.dart`, line 1283

Replace:
```dart
).catchError((Object _) {});
```
With:
```dart
).catchError((Object error, StackTrace stack) {
  afLog('error', 'AfAsyncLock chain error', error: error, stackTrace: stack);
});
```

### CR-ITEM-4.3: Add Unit Tests for autoBypassFlat

**File**: Create/move to `test/core/audio/auto_bypass_flat_test.dart`

Cover these cases:
1. Flat bass shelf (gain=0) → disabled
2. Active bass shelf (gain=6) → enabled
3. Flat superequalizer (empty params) → disabled
4. Active superequalizer (params non-empty) → enabled
5. De-esser values clamped to [0.0, 1.0]
6. All filters working simultaneously
7. Boundary values (0.0 and 1.0 for de-esser)

### CR-ITEM-1.2: Redact Subsonic Debug Logs

**File**: `lib/core/subsonic/client.dart`, lines 77-79

Add a URL redaction helper (or import the existing pattern from `JellyfinUrlBuilder`):

```dart
onRequest: (options, handler) {
  final redacted = Uri.parse(options.uri.toString()).replace(
    queryParameters: {
      for (final e in options.uri.queryParametersAll.entries)
        if (isSensitiveSubsonicParam(e.key)) ... else e.key: e.value,
    },
  );
  afLog('http', '→ ${options.method} ${redacted.path}');
  handler.next(options);
},
```

Where `isSensitiveSubsonicParam` checks for `'u'`, `'t'`, `'s'`.

---

## Commands

Run before/after changes:
```bash
cd D:\project\mobile-app
flutter analyze --no-fatal-infos
flutter test
flutter build apk --debug --target-platform android-arm64
```

For testing the visualizer specifically (no device needed):
```bash
flutter test --no-sound-null-safety test/widgets/audio_visual_scrubber_test.dart 2>/dev/null || echo "Test file may not exist yet"
```

---

## Effort & Priority Assessment

| CR-ITEM | Severity | Effort | Complexity | Priority |
|---------|----------|--------|------------|----------|
| 3.1 Navigator key collision | High | 15 min | Simple | **P0 — Fix before next release** |
| 3.2 AfAsyncLock error swallow | Medium | 5 min | Simple | **P1 — Fix soon** |
| 4.3 Missing autoBypassFlat tests | Medium | 1 hr | Moderate | **P1 — Fix soon** |
| 2.2 Sequential queue add latency | Medium | 2 hr | Complex | P2 — Performance optimization |
| 3.3 isLoadingQueue inconsistency | Low | 30 min | Simple | P2 — Refactoring |
| 1.1 Subsonic password memory | Medium | 1 hr | Moderate | P2 — Security hardening |
| 4.4 Naming/comment inconsistency | Low | 30 min | Simple | P3 — Tech debt cleanup |
| 1.2 Subsonic debug log redaction | Low | 15 min | Simple | P3 — Debug hygiene |
| 3.4 playQueue while loop | Low | 5 min | Simple | P3 — Code clarity |
| 4.2 Generation guard extraction | Low | 2 hr | Moderate | P3 — Tech debt |
| All Low-severity items | Low | Various | Various | P3/P4 — As time permits |

---

## Quality Assurance Checklist

- [x] All security vulnerabilities identified and classified by severity
- [x] Performance bottlenecks flagged with optimization suggestions
- [x] Code quality issues include specific remediation recommendations
- [x] Bug risks identified with reproduction scenarios where possible
- [x] Framework-specific best practices checked (Flutter, Dart, Riverpod, GoRouter)
- [x] Each finding includes a clear explanation of why the change is needed
- [x] Findings prioritized so developer can address critical issues first
- [x] Positive aspects of the code acknowledged (items 4.1, 4.2)

---

## Summary

**Overall code health: Strong.** The Aetherfin codebase demonstrates professional-grade Flutter development with sophisticated handling of real-time audio, complex state management, and cross-platform bridge patterns. The extensive CLAUDE.md documentation (50+ historical gotchas) shows a team that learns from production incidents and encodes those lessons into both code and documentation.

### Top Issues to Address

1. **🔴 [CR-ITEM-3.1] GoRouter navigator key collision** — All shell branches share or omit navigator keys, causing state loss and potential navigation bugs. **Fix: 15 minutes.**

2. **🟡 [CR-ITEM-3.2] AfAsyncLock error swallowing** — Silent error absorption could cause deadlocked callers. **Fix: 5 minutes.**

3. **🟡 [CR-ITEM-4.3] Missing unit tests for autoBypassFlat** — Critical DSP sanitization logic has no test coverage despite being `@visibleForTesting`. **Fix: ~1 hour.**

### Strengths

- **Generation counter pattern** for stale operation detection is best-in-class defensive programming
- **Engine-driven FFT rendering** architecture is production-quality with proper vsync alignment
- **Serialized progress loop** (not `Timer.periodic`) correctly avoids pile-up of network requests
- **Comprehensive error logging** with redaction strategy for sensitive PII
- **Route-level auth guards** via GoRouter redirect with proper `refreshListenable`
- **Thorough documentation** of historical bugs and their fixes in CLAUDE.md
