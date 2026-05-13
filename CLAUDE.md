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
- Real-time FFT spectrum + client-side DSP for the visualizer.
- FFT-driven artwork pulse (sub-bass transient detector).
- Spectral color extraction from artwork (`palette_generator_master`).
- Lock-screen / notification media-session integration (`audio_service`).
- Cover-art file cache (`cached_network_image`).
- Local settings: audio-quality preference, sleep timer, EQ/DSP, ReplayGain.

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
await player.setShuffle(true);   // calls mpv playlist-shuffle
await player.setShuffle(false);  // calls mpv playlist-unshuffle

// Queue manipulation
await player.playNext(media);    // insert after current track
await player.addToQueue(media);  // append to end of queue

// State streams (core)
player.stream.position    // Stream<Duration>
player.stream.playing     // Stream<bool>
player.stream.shuffle     // Stream<bool>
player.stream.loop        // Stream<Loop>  (Loop.off / Loop.file / Loop.playlist)
player.stream.rate        // Stream<double>
player.stream.spectrum    // Stream<FftFrame> — 64 bands, post-DSP, ~120 fps
player.stream.coverArt    // Stream<CoverArt?> — embedded art bytes
player.stream.playlist    // Stream<Playlist>
player.stream.completed   // Stream<bool>
player.stream.buffering   // Stream<bool>

// Playback state (extended)
player.mpvPlaybackStateStream  // Stream — raw mpv playback state
player.bufferingStream         // Stream<bool>
player.bufferingPercentageStream // Stream<double>

// Volume
player.volumeStream       // Stream<double>
player.setVolume(double)
player.muteStream         // Stream<bool>
player.setMute(bool)

// Quality info
player.audioBitrateStream   // Stream<int?>
player.audioParamsStream    // Stream<AudioParams?>

// Gapless
player.prefetchStateStream  // Stream
player.setGapless(Gapless)
player.setPrefetchPlaylist(bool)

// Errors
player.errorStream          // Stream<String?>

// A-B loop
player.setAbLoopA / setAbLoopB / setAbLoopCount
player.abLoopAStream        // Stream<Duration?>
player.abLoopBStream        // Stream<Duration?>
player.remainingAbLoopsStream // Stream<int?>

// DSP / Audio effects
player.setAudioEffects(AudioEffects)
player.updateAudioEffects(AudioEffects)
player.audioEffectsStream   // Stream<AudioEffects>

// ReplayGain
player.setReplayGain(ReplayGainMode)
player.replayGainStream     // Stream<ReplayGainMode>

// Spectrum configuration — engine handles all bounce physics in C++
await player.setSpectrum(SpectrumSettings(
  fftSize: 2048,
  bandCount: 64,
  bandLowHz: 20.0,
  bandHighHz: 20000.0,
  attackSmoothing: 0.8,   // Fast attack for punch
  releaseSmoothing: 0.1,  // Slow release for bouncy decay
  minDb: -105.0,          // Very wide range for maximum dynamic headroom
  maxDb: 35.0,
  emitInterval: Duration(milliseconds: 8), // ~120 fps emission
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
│  │  │                               playNext() and addToQueue() for context-menu actions.
│  │  │                               Shuffle: setShuffle(true/false) → mpv playlist-shuffle/unshuffle.
│  │  │                               Syncs _trackQueue via _player.stream.playlist.first after command.
│  │  │                               Track-ID guard in playlist listener prevents displayed song change.
│  │  │                               _originalQueue stores unshuffled order.
│  │  ├─ play_actions.dart          ← Cross-cutting play entry points
│  │  │                               PlayActions.playQueue shuffles before loading when shuffle is ON.
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
│  │                            settings/ sections: Server, Appearance, Audio output
│  │                            (current output info, sample rate, bit depth, exclusive mode),
│  │                            Network & cache (cache duration, audio buffer, keep audio active),
│  │                            Audio processing (ReplayGain picker), About.
│  │                            queue/ auto-scrolls to currently playing track on open.
│  │                            Long-press context menus on track rows (Play next, Add to queue,
│  │                            Go to album, Go to artist) and album tiles (Play album, Go to artist).
├─ state/
│  └─ providers.dart        ← All Riverpod providers in one file (intentional)
├─ widgets/                 ← Shared visual atoms
│  ├─ mini_player.dart      ← 56 dp floating mini-player
│  ├─ audio_visual_scrubber.dart ← Combined FFT visualizer + progress scrubber.
│  │                          _BlockNotifier: power-8 curve, vsync-aligned flush.
│  │                          Engine-driven rendering: ingest() updates data only (no
│  │                          notifyListeners). Ticker runs at vsync, calls flush() which
│  │                          fires notifyListeners when dirty.
│  │                          _ScrubNotifier: drag state.
│  │                          Two Stack layers: _CombinedBarPainter (path-batched, 4 draw calls) +
│  │                          _ScrubOverlayPainter.
│  │                          Lifecycle-aware (AppLifecycleListener + route obscure detection).
│  │                          Ticker drives repaints at vsync; 300ms silence timer for fade-out
│  │                          (0.85× decay). Scrubber drag race fix with _isDragging flag.
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
Artwork (240dp, spectral glow BoxShadow, FFT-driven scale pulse)
Metadata (title + artist + favorite + quality chip)
AudioVisualScrubber (120dp — FFT bars + scrubber overlay merged)
Time labels (position / remaining)
Transport controls (shuffle, prev, play/pause, next, repeat)
Utility row (lyrics, save, queue, more)
```

The utility row was reduced from 6 icons to 4. The **"More"** button opens
a popup dialog containing: Sleep timer, Playback speed, Audio output,
Equalizer & DSP.

### 4.5 EQ dialog (inline, from More menu)

Accessible via Now Playing → More → Equalizer & DSP. Controls:
- Bass shelf: -12 dB to +12 dB
- Treble shelf: -12 dB to +12 dB
- Loudness normalization toggle (EBU R128, target -16 LUFS)
- Dynamic compressor toggle
- Reset all button

Uses `player.updateAudioEffects(AudioEffects(...))` API. State is streamed
via `player.audioEffectsStream`.

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

## 9. Visualizer + scrubber architecture (engine-driven rendering)

The visualizer and progress scrubber are merged into a single widget
(`AudioVisualScrubber` at `lib/widgets/audio_visual_scrubber.dart`) with
two painter layers in a `Stack`. The architecture is engine-driven:
`ingest()` updates data only (no notifyListeners). A ticker runs at vsync
and calls `flush()` which fires notifyListeners when dirty. Power-8 curve.
300ms silence timer triggers fade-out (0.85× decay). Path-batched painter
(4 draw calls). Scrubber drag race fix with `_isDragging` flag.

### 9.1 Signal pipeline (`_BlockNotifier`)

The engine's native C++ EMA (attack 0.8, release 0.1) handles all bounce
physics. The client does NO smoothing — it renders bands directly with
only a power curve for visual compression.

```
Player.stream.spectrum (64 bands, ~120 fps, engine-smoothed)
    │
    ▼  ingest() — data update only, no notifyListeners
for each band i:
  raw = bands[i].clamp(0, 1)
  smoothed[i] = pow(raw, 8.0)    ← power-8 compression
totalEnergy = mean(smoothed)
_dirty = true
    │
    ▼  flush() — called by ticker on every vsync (60 fps)
if (_dirty):
  _dirty = false
  notifyListeners()              ← triggers repaint, frame-aligned
```

**Why vsync-aligned:** Stream events arrive from Dart's async zone, not
aligned to Flutter's vsync. If an event arrives right after a vsync, the
repaint waits until the next one — halving perceived frame rate. The ticker
guarantees frame-aligned repaints at a steady 60 fps.

**Fade-out:** When audio stops (300ms silence timer), `startFadeOut()` sets
a flag. The ticker's `flush()` detects it and runs `_tickFadeOut()` which
decays bars at 0.85× per frame until they reach zero. Ticker self-stops
when no energy remains.

**Lifecycle awareness:**
- `AppLifecycleListener` stops the ticker on `onPause`, resumes on `onResume`.
- `ModalRoute.secondaryAnimation` detects when another screen covers Now
  Playing; `_shouldRender` guards drop FFT frames entirely when obscured.

### 9.2 Rendering (two painter layers)

Layer 1 — `_CombinedBarPainter` (repaint: `Listenable.merge([fft, scrub])`):
- Path-batched: 4 `Path` objects (top/reflection × played/unplayed) drawn
  with 4 `drawPath` calls instead of ~128 individual `drawRRect` calls.
  Eliminates Skia pipeline thrashing from constant color switches.
- 64 solid rounded bars, bottom-anchored, growing upward (80% max of half-height)
- Reflection: 40% height, 35% opacity, grows downward
- Per-bar color: `playedColor` if bar center ≤ playhead, else `unplayedColor`

Layer 2 — `_ScrubOverlayPainter` (repaint: `_ScrubNotifier` only):
- 3dp rounded track (unplayed: textTertiary 20% opacity)
- Gradient tail: transparent → `playedColor` across the filled portion
- Playhead flare: ambient glow circle + horizontal "star" streak
- White-hot 4dp core during drag

### 9.3 Scrubber drag race fix

`_ReactiveProgressState` has an `_isDragging` flag that suppresses
`positionStreamProvider` rebuilds during the drag gesture. Without this,
the engine keeps emitting position ticks at 30-60 Hz while the user drags,
causing the playhead to stutter between the drag position and the engine's
real position. The lock holds until `seek()` resolves.

### 9.4 Key invariants

- The engine handles ALL smoothing/physics in C++. The client applies only
  a power-8 curve for visual compression — no lerp, no AGC, no treble boost.
- `bandCount: 64` in `SpectrumSettings` must match `_BlockNotifier.bins = 64`.
- `ingest()` never calls `notifyListeners()`. Only `flush()` does (on vsync).
- No shaders are allocated per bar. Path batching keeps GPU state changes to 4.
- Both `shouldRepaint` methods only check color props — the repaint flow is
  driven by the `Listenable` passed to `super(repaint:)`.

## 10. Artwork pulse architecture

The artwork bumps on kick drums via a transient detector on FFT bin 0.

```
_bassAverage += (rawBass - _bassAverage) × 0.05       ← running baseline
if (rawBass > _bassAverage × 1.5 && rawBass > 0.02 && _cooldown == 0):
  _scale.value = 1.06                                 ← +6% bump
  _cooldown    = 15                                   ← ~250ms lockout
  ticker.repeat()
    │
    ▼  spring decay each frame
_scale.value = 1.0 + (_scale.value - 1.0) × 0.85
ticker stops when scale < 1.001
    │
    ▼  ValueListenableBuilder → Transform.scale
```

Lives in `_ReactiveArtworkState` inside `now_playing_screen.dart`.
`ValueNotifier<double>` + `Transform.scale` — no `setState`, no parent rebuild.

## 11. Build, run, lint, test

```bash
flutter pub get
flutter run --debug
flutter analyze --no-fatal-infos   # 0 errors, 0 warnings
flutter test
flutter build apk --release
flutter build apk --release --split-per-abi
adb logcat -c && adb logcat -s flutter
```

## 12. Debug trace conventions

Use `afLog('<category>', '<message>')` from `lib/utils/log.dart`.
PII (usernames, server URLs) must be redacted in release builds.

| Prefix | When |
|---|---|
| `aetherfin:boot` | Boot ordering, auth restoration |
| `aetherfin:http →/←/✕` | HTTP request / response / error |
| `aetherfin:error` | Caught exception + stacktrace |
| `aetherfin:data` | Provider data provenance (`source=live\|demo`) |
| `aetherfin:audio` | Player state transitions |

## 13. Data layer conventions

- `JellyfinClient` is the **only** file that speaks HTTP.
- All endpoints assert `userId` via `_assertUser()`.
- No `json_serializable`. Models are hand-written in `lib/core/jellyfin/models/`.
- Image URLs embed the `tag` query param for HTTP cacheability.
- Search queries are normalized (trim + lowercase) before hitting the provider. Minimum 2 characters.

## 14. PR & CI rules

- Run `flutter analyze --no-fatal-infos` and `flutter test` before pushing.
- Do **not** force-push to `main`.
- Do **not** disable plugins or change the auth header shape to "fix" a 500.
- CI is manual trigger only (`workflow_dispatch`). Gradle daemon is stopped before the build step to prevent file-watcher collisions.

## 15. Things AI agents have gotten wrong before

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
18. **"Use `AudioMotionVisualizer` or `Waveform` widgets."** These were deleted. The combined widget is `AudioVisualScrubber`.
19. **"The visualizer should apply its own client-side DSP (log, treble boost, AGC, lerp)."** No. The engine's native C++ EMA handles all bounce physics. The client applies only a power-8 curve for visual compression and renders via vsync-aligned ticker. Adding client-side smoothing fights the engine and causes lag.
20. **"Create a shader per bar inside `paint()`."** No. That's 64 allocations/frame at 60fps — causes raster-thread GC lag. Pre-compute shaders once per `paint()` call.
21. **"Subscribe to `spectrumStream` in `didChangeDependencies`."** No. It fires on every ancestor dependency change and causes stream churn. Subscribe once in `initState` via `addPostFrameCallback`.
22. **"The battery channel is `dev.aetherfin.aetherfin/battery`."** No. It's `aetherfin.battery_opt` (matches `BatteryOptPlugin.CHANNEL_NAME`).
23. **"Drive the artwork pulse by continuously scaling with bin 0 amplitude."** No. That flickers on every frame. Use a transient detector with running baseline + cooldown + spring decay.
24. **"Implement shuffle by rebuilding the queue in Dart."** No. Use mpv's native `setShuffle(true/false)` which calls `playlist-shuffle`/`playlist-unshuffle` without interrupting playback. Sync `_trackQueue` by awaiting `_player.stream.playlist.first` after the command. Store `_originalQueue` for unshuffle.
25. **"The utility row has 6 icons."** No. It's 4: Lyrics, Save, Queue, More. Sleep timer, playback speed, audio output, and EQ are behind the More popup.
26. **"Apply EQ/DSP via a separate audio pipeline."** No. Use `player.updateAudioEffects(AudioEffects(...))`. The engine handles DSP natively.

## 16. Glossary

- **`RunTimeTicks`**: Jellyfin duration unit. 1 tick = 100 ns. Divide by 10 for microseconds.
- **`PrimaryImageTag`**: Short hash for HTTP cache-busting on image URLs.
- **`Loop.off / Loop.file / Loop.playlist`**: mpv_audio_kit loop enum.
- **`FftFrame`**: mpv_audio_kit spectrum frame — `bands: Float32List` (64 values in [0,1], post-DSP).
- **`AfPlayerService`**: The app's audio handler. Extends `BaseAudioHandler` (audio_service) and wraps `Player` (mpv_audio_kit).
- **`_pendingPlayNudgeIdx`**: State machine field in `AfPlayerService`. Set when playlist index changes; cleared when `playing=true` fires. Prevents `Future.delayed` for auto-advance.
- **`AudioVisualScrubber`**: Combined FFT visualizer + progress scrubber widget. Owns `_BlockNotifier` (signal DSP) and `_ScrubNotifier` (drag state). Two `RepaintBoundary` layers.
- **`_BlockNotifier`**: `ChangeNotifier` inside `AudioVisualScrubber`. Applies power-8 curve to engine bands. `ingest()` updates data only; `flush()` fires `notifyListeners()` on vsync via ticker. 300ms silence timer triggers fade-out (0.85× decay per frame).
- **`_ScrubNotifier`**: `ChangeNotifier` inside `AudioVisualScrubber`. Owns drag state and display progress.
- **`Spectral`**: Runtime color triple (`energy`, `shadow`, `glow`) extracted from current artwork. Lives in `currentSpectralProvider`. Never hardcode these values.
- **`BatteryOptPlugin`**: Kotlin `ActivityAware` plugin on channel `aetherfin.battery_opt`. Fires `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` on first HomeScreen visit.
- **Reactive islands**: Architecture pattern in `NowPlayingScreen` where high-frequency streams (position, FFT) are isolated to leaf `ConsumerWidget`s so the top-level scaffold doesn't rebuild on every tick.
- **`AudioEffects`**: mpv_audio_kit model for DSP state — bass shelf, treble shelf, loudness normalization, dynamic compressor. Streamed via `audioEffectsStream`, mutated via `updateAudioEffects`.
- **`ReplayGainMode`**: mpv_audio_kit enum for ReplayGain behavior (off, track, album). Set via `setReplayGain`, observed via `replayGainStream`.
- **`_originalQueue`**: Field in `AfPlayerService` storing the unshuffled track order. Restored when shuffle is toggled off via mpv's `playlist-unshuffle`.
- **`playNext()` / `addToQueue()`**: `AfPlayerService` methods for inserting tracks relative to the current position. Used by long-press context menus on track rows and album tiles.

---

When something here becomes wrong, update this file in the same PR that
makes the change wrong. CLAUDE.md drifting from reality is worse than no
CLAUDE.md at all.
