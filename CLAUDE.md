# CLAUDE.md — Aetherfin Project Guide

This document is the **single source of truth** for AI coding agents working
on Aetherfin. Read this end to end before making changes. It captures the
constraints, conventions, and gotchas discovered while building the client
and is updated as we learn more.

## 1. What Aetherfin is

A native-feeling Android music player backed by a self-hosted **Jellyfin**
server. The only first-class platform is Android. iOS may follow but is not
considered when making trade-offs.

> **North star:** Spotify's polish, Apple Music's typography, Soulseek's
> respect for the listener. Aetherfin must read as a *premium music* app,
> not "a Jellyfin client."

### 1.1 Mental model — what runs where

Treat Jellyfin as a **file source + library state store**, nothing else.
**Aetherfin is the player.**

**Jellyfin (server) is responsible for:**
- Storing audio files and serving the original bytes byte-for-byte.
- Catalog metadata: titles, artists, albums, genres, durations, year, artwork.
- Search (`/Users/{id}/Items?searchTerm=…` — never `/Search/Hints`).
- Auth (user accounts + access tokens).
- Per-user state: favorites, play counts, last-played-at, playlists.
- LRC lyric files (stored only; the app parses them).
- "Now Playing" telemetry display — `POST /Sessions/Playing*` exists
  purely so the Jellyfin Dashboard widget shows who's listening to what.

**Aetherfin (app) is responsible for everything else, on-device:**
- All audio **decoding** (libmpv via `mpv_audio_kit`).
- Buffering, gapless transitions, output routing, position tracking.
- Queue management (order, shuffle, repeat, reorder).
- UI rendering for every screen.
- LRC parsing + synced line highlighting.
- Real-time FFT spectrum for the visualizer (`Player.stream.spectrum`).
- Spectral color extraction from artwork (`palette_generator_master`).
- Lock-screen / notification media-session integration (`audio_service`).
- Cover-art file cache (`cached_network_image`).
- Local settings: audio-quality preference, sleep timer.

**Strict consequence:** stream URLs MUST use
`/Audio/{id}/stream?Static=true` — the direct-stream endpoint. The
universal endpoint (`/Audio/{id}/universal`) triggers server-side
transcoding to HLS, which (1) wastes the server's CPU, (2) gives a
codec that may not decode cleanly, and (3) was the cause of the
"track plays but position never advances" bug.

**Strict consequence #2:** stream URLs embed `api_key=<token>` as a query
parameter because FFmpeg/libmpv rejects the `Authorization: MediaBrowser …`
header (it contains commas, which FFmpeg treats as header-list separators).
This is the standard approach for mpv-based Jellyfin clients.

**Strict consequence #3:** favorites, play counts, and playlist contents
are server-owned even though the heart icon flips locally first. The
client does optimistic UI then `POST/DELETE /Users/{id}/FavoriteItems/
{itemId}`. On HTTP error, revert. Never store favorite state only on-device.

## 2. Tech stack (exact versions)

| Layer | Choice | Notes |
|---|---|---|
| Framework | Flutter **3.41.9 stable**, Dart **3.11.5** | `flutter --version` must match. CI pins this. |
| State | `flutter_riverpod` ^2.6 | `FutureProvider.autoDispose`, `StateNotifierProvider`. No `ChangeNotifier` for Riverpod providers. |
| Routing | `go_router` ^14.7 | Shell route with bottom nav. See `lib/app/router.dart`. |
| HTTP | `dio` ^5.7 + `dio_cache_interceptor` ^3.5 | One Dio per `JellyfinClient`. Auth header baked into `BaseOptions.headers`. |
| Audio | `mpv_audio_kit` ^0.1.3 | libmpv-backed player. Replaces `just_audio` + `audio_session`. |
| Lock-screen | `audio_service` ^0.18 | `AfPlayerService extends BaseAudioHandler`. |
| Storage | `flutter_secure_storage` ^9.2 (creds + deviceId), `shared_preferences` ^2.3 (settings) | Never store creds in shared_preferences. |
| Discovery | `multicast_dns` ^0.3.2 | mDNS scan for `_jellyfin._tcp`. |
| Imagery | `cached_network_image` ^3.4, `flutter_svg` ^2.0, `palette_generator_master` ^1.1 | All cover art through `cached_network_image`. |
| Fonts | `google_fonts` ^6.2, `cupertino_icons` ^1.0.8 | Inter Variable + JetBrains Mono. cupertino_icons satisfies transitive font validator. |
| UUID | `uuid` ^4.5 | Fallback device ID generation (cryptographically random). |

The min Android SDK is **24** (Android 7.0). Built with **Java 17** + Gradle
in CI. Local Java 17 is required.

`mpv_audio_kit` downloads `libmpv.so` from GitHub Releases at build time
(~20 MB per ABI, arm64-v8a + x86_64). The first build requires internet
access. Subsequent builds reuse the cached `.so` files.

### 2.1 mpv_audio_kit API surface used

```dart
// Queue replacement
await player.openAll(medias, index: startIndex, play: true);

// Playback control
await player.play();
await player.pause();
await player.seek(position);
await player.next();
await player.previous();
await player.jump(index);
await player.setGapless(Gapless.weak);

// State streams
player.stream.position    // Stream<Duration>
player.stream.playing     // Stream<bool>
player.stream.shuffle     // Stream<bool>
player.stream.loop        // Stream<Loop>  (Loop.off / Loop.file / Loop.playlist)
player.stream.rate        // Stream<double>
player.stream.spectrum    // Stream<FftFrame> — 48 bands, post-DSP, ~60 fps
player.stream.coverArt    // Stream<CoverArt?> — embedded art bytes
player.stream.playlist    // Stream<Playlist>
player.stream.completed   // Stream<bool>
player.stream.buffering   // Stream<bool>

// Spectrum configuration — player owns all DSP
await player.setSpectrum(SpectrumSettings(
  bandCount: 48,       // matches renderer bar count 1:1
  minDb: -40.0,        // signals below -40 dBFS are invisible
  maxDb: -12.0,        // loud peaks approach full height
  attackSmoothing: 0.72,
  releaseSmoothing: 0.16,
  emitInterval: Duration(milliseconds: 16), // ~60 fps
));

// Loop enum values
Loop.off       // no looping
Loop.file      // repeat current track
Loop.playlist  // repeat entire queue
```

## 3. Source-tree map

```
lib/
├─ main.dart                ← runApp + boot trace + AudioService init
│                             Startup timeouts (5s storage, 10s AudioService).
│                             UUID v4 fallback device ID. Release error redaction.
├─ app/
│  ├─ app.dart              ← Root MaterialApp.router
│  ├─ router.dart           ← go_router config (shell + nested routes)
│  └─ theme.dart            ← ThemeData built from design tokens
├─ design_tokens/           ← Single source of truth for §4 visual spec
├─ core/
│  ├─ audio/
│  │  ├─ player_service.dart        ← AfPlayerService: mpv_audio_kit + audio_service bridge
│  │  │                               Throttled playbackState (~2 Hz), _pendingPlayNudgeIdx
│  │  │                               state machine, _jumpAndPlay async/await, _disposed guards.
│  │  ├─ play_actions.dart          ← Cross-cutting play entry points
│  │  ├─ jellyfin_playback_reporter.dart ← POST /Sessions/Playing* lifecycle
│  │  │                               Serialized progress loop (not Timer.periodic), 5s timeouts.
│  │  ├─ live_update_service.dart   ← Android 16+ Live Update chip (in-flight guard)
│  │  └─ spectral_extractor.dart    ← palette_generator → Spectral triple (LRU cache)
│  ├─ battery_opt.dart      ← Dart bridge to BatteryOptPlugin (aetherfin.battery_opt channel)
│  ├─ demo/                 ← DemoLibrary — bundled albums/artists for onboarding preview
│  ├─ jellyfin/
│  │  ├─ client.dart        ← THE ONLY file that speaks HTTP to Jellyfin
│  │  ├─ auth_storage.dart  ← secure_storage wrappers (token, userId, deviceId)
│  │  ├─ discovery.dart     ← mDNS scan + public-info probe
│  │  └─ models/            ← Plain Dart classes — NO json_serializable codegen
│  └─ lyrics/               ← LRC parser (sync + unsynced)
├─ features/                ← One folder per top-level screen
│  ├─ home/        library/  album/      artist/     genre/
│  ├─ search/      queue/    now_playing/ lyrics/
│  ├─ onboarding/  profile/  settings/    cast_picker/  sleep_timer/  playlist/
├─ state/
│  └─ providers.dart        ← All Riverpod providers in one file (intentional)
├─ widgets/                 ← Shared visual atoms
│  ├─ mini_player.dart      ← 56 dp floating mini-player
│  ├─ audio_motion_visualizer.dart ← 48-bar spectrum visualizer
│  │                          _AmaNotifier: neighbor blend only, no client-side DSP.
│  │                          Stream cadence IS the animation loop — no ticker.
│  ├─ waveform.dart         ← Minimal pill progress scrubber (Waveform)
│  │                          3dp track, accent fill, thumb on drag only.
│  │                          No FFT, no ticker.
│  └─ …
└─ utils/
   ├─ log.dart              ← afLog() wrapper around dart:developer.log
   ├─ oklch.dart            ← OKLCH → sRGB conversion
   └─ time_format.dart      ← Duration formatting helpers
```

### 3.1 Android native plugins

```
android/app/src/main/kotlin/dev/aetherfin/aetherfin/
├─ MainActivity.kt            ← Registers LiveUpdatePlugin + BatteryOptPlugin
├─ battery/
│  └─ BatteryOptPlugin.kt     ← MethodChannel: aetherfin.battery_opt
│                               ActivityAware. Methods:
│                               isIgnoringBatteryOptimizations() → bool
│                               requestIgnoreBatteryOptimizations() → bool
└─ live_update/
   └─ LiveUpdatePlugin.kt     ← MethodChannel: aetherfin.live_update
                                Android 16+ ProgressStyle Live Update chip
```

## 4. Design spec — non-negotiables

### 4.1 Colour
- Indigo scale (`AfColors.indigo50…900`) is derived from **OKLCH**. Do not
  eyeball-adjust hexes. Derive new colors in `lib/utils/oklch.dart` first.
- `AfColors.surfaceCanvas = #0B0B14`. `textPrimary` is white with 92% alpha.
- Runtime spectral accent (`Spectral.energy / .shadow / .glow`) is extracted
  from current artwork via `palette_generator_master`. Never hardcode it.

### 4.2 Motion (`lib/design_tokens/motion.dart`)
- **Exactly five** duration tiers: `instant 80ms`, `quick 160ms`,
  `standard 240ms`, `expressive 400ms`, `long 600ms`. Material defaults
  (200/300/500ms) are forbidden — `test/design_tokens_test.dart` enforces this.
- Exactly five easing curves: `easeStandard`, `easeEmphasized`, `easeOut`,
  `easeIn`, `linear`. Audio-coupled animations (visualizer, progress scrubber,
  lyric scroll) MUST use `linear`.

### 4.3 Mini-player rules
- **56 dp tall, 12 dp horizontal margin, 16 dp gap to bottom nav.**
- `AfSpacing.bottomInsetWithMiniAndNav` is the canonical bottom-inset for
  every scrollable.
- Visible only when the queue is non-empty.

### 4.4 Now Playing screen layout (order matters)
```
TopBar (album context + overflow menu)
Artwork (240dp, spectral glow BoxShadow)
Metadata (title + artist + favorite + quality chip)
AudioMotionVisualizer (48-bar spectrum, 96dp tall)
Progress scrubber (3dp pill + time labels)
Transport controls (shuffle, prev, play/pause, next, repeat)
Utility row (sleep, lyrics, speed, output, save, queue)
```

## 5. Jellyfin auth — battle-tested format

Every Jellyfin request carries:

```
Authorization: MediaBrowser UserId="…", Token="…", Client="Aetherfin", Device="Android", DeviceId="…", Version="0.1.0"
Content-Type: application/json
User-Agent: Aetherfin/0.1.0 (Android)
Accept: application/json
```

Rules:
- **`UserId` and `Token` are OMITTED entirely before login.**
- **Send only `Authorization`** — not `X-Emby-Authorization`.
- **Field order matches Finamp**: `UserId, Token, Client, Device, DeviceId, Version`.
- **`DeviceId` is a per-install UUID v4** in `flutter_secure_storage`. Fallback uses `uuid` package (not timestamp).
- Non-ASCII bytes in the header are replaced with `_`.
- **Stream URLs use `api_key=<token>` query param** — NOT the Authorization header. FFmpeg rejects the MediaBrowser header format.

The canonical implementation lives in `_buildAuthHeader()` at
`lib/core/jellyfin/client.dart`. **Do not duplicate this logic.**

### 5.1 If `AuthenticateByName` returns 500
Almost always a server-side issue. Reproduce with `curl`:
```bash
curl -i -X POST 'http://SERVER/Users/AuthenticateByName' \
  -H 'Authorization: MediaBrowser Client="curl", Device="curl", DeviceId="curl-001", Version="1.0.0"' \
  -H 'Content-Type: application/json' \
  -d '{"Username":"u","Pw":"p"}'
```
If `curl` also returns 500, restart the Jellyfin Docker container.

### 5.2 Race-free auth hydration

`main()` reads `AuthStorage().load()` before `runApp` and injects the
result via `ProviderScope` overrides. `AuthNotifier` takes the initial
value through its constructor — no async hydrate, no race window.
Storage IO has a 5s timeout; `AudioService.init` has a 10s timeout.

### 5.3 Router-level auth redirects

`go_router` is wired with a `refreshListenable` that fires when
`authProvider` changes. The `redirect` callback sends signed-in users
to `/home` and anonymous users to `/`. Every onboarding route must
start with `/onboarding/`.

## 6. Navigation rules

- **`context.push()`** for transient/detail screens: `/now-playing`, `/lyrics`, `/queue`, `/album/:id`, `/artist/:id`, `/playlist/:id`, `/settings`, `/sleep`, `/cast`. These sit on the navigation stack; back gesture pops them.
- **`context.go()`** only for top-level shell navigation (tab switches, auth redirects). These replace the stack.
- Mixing `go()` and `push()` incorrectly destroys the back stack. `lyrics_screen.dart` and `queue_screen.dart` both use `push()` to navigate to each other — using `go()` would replace the stack and break the back gesture.

## 7. Notification / lock-screen rules

- Controls: `[skipToPrevious, pause/play, skipToNext]` with `androidCompactActionIndices: [0, 1, 2]`.
- **Never include `MediaControl.stop`** in the controls array — `audio_service` converts it to a `CustomAction` (not a notification button), making index 3 out-of-bounds and dropping the "next" button.
- `MediaAction.stop` goes in `systemActions` (renders as the notification cancel button).
- **Never pass a network `artUri`** to `MediaItem` — `audio_service` tries to download it without auth headers, leaving `mediaMetadata = null` on Android and suppressing the notification. Only pass `file://` URIs from `_persistCover`.
- `androidStopForegroundOnPause: true` — Samsung One UI hides ongoing notifications from demoted services when `false`.

## 8. Background playback (Samsung / Doze)

- Auto-advance uses stream callbacks (`_pendingPlayNudgeIdx` state machine), not `Future.delayed` or `.then()` chaining. Doze throttles both when the screen is off.
- `_jumpAndPlay(index)` uses `async/await` — not `.then()` — so `play()` is not deferred by the Dart scheduler under Doze.
- Race-condition guard: the `playlist` stream listener checks `_player.state.playing` synchronously. If already `false` when the index changes, nudge fires immediately without waiting for the next `playing` event.
- Nudge is bounded to `_maxNudgeRetries = 3` to prevent infinite play loops.
- `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` permission declared in manifest. Battery exemption dialog shown on first HomeScreen visit via `BatteryOpt.requestIgnore()` → `BatteryOptPlugin` (`aetherfin.battery_opt` MethodChannel).

## 9. Visualizer architecture

```
Player.stream.spectrum (48 bands, 60 fps, pre-smoothed by mpv)
    │
    ▼  _AmaNotifier.ingest() — neighbor blend only
out[i] = src[i]*0.84 + src[i-1]*0.08 + src[i+1]*0.08
    │
    ▼  notifyListeners() — stream cadence IS the animation loop, no ticker
_AmaPainter (CustomPainter, repaint: notifier)
    │
    ▼  48 uniform bars, bottom-anchored, growing upward
    max fill = 55% of zone height
    horizontal frequency gradient (single shader, pre-computed once per paint):
      bass (left, 70% opacity) → mid (100%) → treble (right, 85%)
    each bar's color = its frequency position in the gradient
```

**Key rules:**
- The player pipeline owns all DSP. Do not add client-side EMA, decay, or smoothing.
- `_AmaNotifier` has no ticker, no `AnimationController`. The 60 fps stream cadence drives repaints directly.
- The gradient shader is created **once per `paint()` call** against the full zone rect and reused for all 48 bars. Creating a shader per bar (48×/frame) causes raster-thread GC lag.
- `bandCount: 48` in `SpectrumSettings` must match `_AmaNotifier._n = 48`. Do not change one without the other.
- dB window: `minDb: -40.0, maxDb: -12.0`. Signals below -40 dBFS are invisible. Raising `minDb` further reduces sensitivity; lowering it increases it.

### Progress scrubber (`waveform.dart`)

```
_ScrubNotifier (ChangeNotifier) — drag state + display progress
    │
    ▼  notifyListeners() on drag or progress update
_ScrubPainter (CustomPainter, repaint: notifier)
    │
    ▼  3dp rounded track (unplayed: textTertiary 20% opacity)
    accent fill grows left-to-right with progress
    thumb (6dp circle) appears only during drag
```

No FFT, no ticker. Repaints only on drag or external progress updates.
The `peaks` parameter is kept for API compatibility but not rendered.

## 10. Build, run, lint, test

```bash
flutter pub get
flutter run --debug
flutter analyze --no-fatal-infos   # 0 errors, 0 warnings
flutter test
flutter build apk --release
flutter build apk --release --split-per-abi
adb logcat -c && adb logcat -s flutter
```

## 11. Debug trace conventions

Use `afLog('<category>', '<message>')` from `lib/utils/log.dart`.
PII (usernames, server URLs) must be redacted in release builds.

| Prefix | When |
|---|---|
| `aetherfin:boot` | Boot ordering, auth restoration |
| `aetherfin:http →/←/✕` | HTTP request / response / error |
| `aetherfin:error` | Caught exception + stacktrace |
| `aetherfin:data` | Provider data provenance (`source=live\|demo`) |
| `aetherfin:audio` | Player state transitions |

## 12. Data layer conventions

- `JellyfinClient` is the **only** file that speaks HTTP.
- All endpoints assert `userId` via `_assertUser()`.
- No `json_serializable`. Models are hand-written in `lib/core/jellyfin/models/`.
- Image URLs embed the `tag` query param for HTTP cacheability.
- Search queries are normalized (trim + lowercase) before hitting the provider. Minimum 2 characters.

## 13. PR & CI rules

- Run `flutter analyze --no-fatal-infos` and `flutter test` before pushing.
- Do **not** force-push to `main`.
- Do **not** disable plugins or change the auth header shape to "fix" a 500.
- CI is manual trigger only (`workflow_dispatch`). Gradle daemon is stopped before the build step to prevent file-watcher collisions.

## 14. Things AI agents have gotten wrong before

1. **"Just send Token="" — it's cleaner."** No. Omit the field entirely.
2. **"Static DeviceId is fine."** No. Per-install UUID v4 in secure_storage.
3. **"Use `/Search/Hints`."** No. Use `/Users/{id}/Items?searchTerm=…`.
4. **"Material animation defaults are fine."** No. Five durations, five curves, tests enforce it.
5. **"Use `just_audio` for playback."** No. The audio engine is `mpv_audio_kit`. `AfPlayerService` wraps it.
6. **"Loop modes are `LoopMode.off/all/one`."** No. mpv_audio_kit uses `Loop.off / Loop.playlist / Loop.file`.
7. **"Build a parallel HTTP client."** Don't. Add a method to `JellyfinClient`.
8. **"Hydrate `AuthNotifier` asynchronously."** No. Load auth in `main()` and inject via `initialAuthProvider`.
9. **"go_router will figure out where to send a signed-in user."** No. Without `redirect:` + `refreshListenable`, you land on WelcomeScreen.
10. **"`context.pop()` is safe on any screen."** No. Guard with `canPop()` on screens reached via `context.go()`.
11. **"Use `context.go()` to navigate from lyrics to queue."** No. `go()` replaces the stack. Use `push()` for all detail/overlay screens.
12. **"Include `MediaControl.stop` in the notification controls."** No. It becomes a `CustomAction`, breaks `androidCompactActionIndices`, and drops the next button.
13. **"Pass the artwork network URL as `artUri` in `MediaItem`."** No. `audio_service` downloads it without auth headers → `mediaMetadata = null` → notification suppressed. Only pass `file://` URIs.
14. **"Use `Timer.periodic` for progress reporting."** No. It doesn't await the callback — requests pile up. Use a serialized `while (_running)` loop.
15. **"Use `Future.delayed` for auto-advance."** No. Doze throttles it when the screen is off. Use stream callbacks.
16. **"Use `.then()` chaining for jump+play."** No. Doze can defer `.then()` callbacks. Use `async/await` in a named method (`_jumpAndPlay`).
17. **"Set `androidStopForegroundOnPause: false`."** No. Samsung One UI hides the notification when the service is demoted. Keep it `true`.
18. **"Add client-side EMA/smoothing to the visualizer."** No. The player pipeline already owns smoothing. Adding more creates syrupy, detached motion. Trust `SpectrumSettings`.
19. **"Create a shader per bar inside `paint()`."** No. That's 48 allocations/frame at 60fps — causes raster-thread GC lag. Pre-compute one shader per `paint()` call and reuse it.
20. **"Use `beat_pulse_artwork.dart` or `_WaveformNotifier`."** These no longer exist. The visualizer is `audio_motion_visualizer.dart` (`_AmaNotifier`). The scrubber is `waveform.dart` (`_ScrubNotifier`).
21. **"The battery channel is `dev.aetherfin.aetherfin/battery`."** No. It's `aetherfin.battery_opt` (matches `BatteryOptPlugin.CHANNEL_NAME`).

## 15. Glossary

- **`RunTimeTicks`**: Jellyfin duration unit. 1 tick = 100 ns. Divide by 10 for microseconds.
- **`PrimaryImageTag`**: Short hash for HTTP cache-busting on image URLs.
- **`Loop.off / Loop.file / Loop.playlist`**: mpv_audio_kit loop enum.
- **`FftFrame`**: mpv_audio_kit spectrum frame — `bands: Float32List` (48 values in [0,1], post-DSP).
- **`AfPlayerService`**: The app's audio handler. Extends `BaseAudioHandler` (audio_service) and wraps `Player` (mpv_audio_kit).
- **`_pendingPlayNudgeIdx`**: State machine field in `AfPlayerService`. Set when playlist index changes; cleared when `playing=true` fires. Prevents `Future.delayed` for auto-advance.
- **`_AmaNotifier`**: `ChangeNotifier` inside `AudioMotionVisualizer`. Applies neighbor blend to incoming FFT bands. Drives `_AmaPainter` repaints via `repaint:` Listenable. No ticker.
- **`_ScrubNotifier`**: `ChangeNotifier` inside `Waveform`. Owns drag state and display progress. Drives `_ScrubPainter` repaints. No ticker, no FFT.
- **`Spectral`**: Runtime color triple (`energy`, `shadow`, `glow`) extracted from current artwork. Lives in `currentSpectralProvider`. Never hardcode these values.
- **`BatteryOptPlugin`**: Kotlin `ActivityAware` plugin on channel `aetherfin.battery_opt`. Fires `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` on first HomeScreen visit.
- **Reactive islands**: Architecture pattern in `NowPlayingScreen` where high-frequency streams (position, FFT) are isolated to leaf `ConsumerWidget`s so the top-level scaffold doesn't rebuild on every tick.

---

When something here becomes wrong, update this file in the same PR that
makes the change wrong. CLAUDE.md drifting from reality is worse than no
CLAUDE.md at all.
