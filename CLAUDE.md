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
- Real-time FFT spectrum for the artwork visualizer (`Player.stream.spectrum`).
- Spectral color extraction from artwork (`palette_generator`).
- Lock-screen / notification media-session integration (`audio_service`).
- Cover-art file cache (`cached_network_image`).
- Local settings: audio-quality preference, crossfade, sleep timer.

**Strict consequence:** stream URLs MUST use
`/Audio/{id}/stream?Static=true` — the direct-stream endpoint. The
universal endpoint (`/Audio/{id}/universal`) triggers server-side
transcoding to HLS, which (1) wastes the server's CPU, (2) gives a
codec that may not decode cleanly, and (3) was the cause of the
"track plays but position never advances" bug fixed in PR #4.

**Strict consequence #2:** favorites, play counts, and playlist contents
are server-owned even though the heart icon flips locally first. The
client does optimistic UI then `POST/DELETE /Users/{id}/FavoriteItems/
{itemId}`. On HTTP error, revert. Never store favorite state only on-device.

## 2. Tech stack (exact versions)

| Layer | Choice | Notes |
|---|---|---|
| Framework | Flutter **3.41.9 stable**, Dart **3.11.5** | `flutter --version` must match. CI pins this. |
| State | `flutter_riverpod` ^2.6 | `FutureProvider.autoDispose`, `StateNotifierProvider`. No `ChangeNotifier`. |
| Routing | `go_router` ^14.7 | Shell route with bottom nav. See `lib/app/router.dart`. |
| HTTP | `dio` ^5.7 + `dio_cache_interceptor` ^3.5 | One Dio per `JellyfinClient`. Auth header baked into `BaseOptions.headers`. |
| Audio | `mpv_audio_kit` ^0.1.3 | libmpv-backed player. Replaces `just_audio` + `audio_session`. |
| Lock-screen | `audio_service` ^0.18 | `AfPlayerService extends BaseAudioHandler`. Bridged to mpv via `MpvAudioHandler` pattern. |
| Storage | `flutter_secure_storage` ^9.2 (creds + deviceId), `shared_preferences` ^2.3 (settings) | Never store creds in shared_preferences. |
| Discovery | `multicast_dns` ^0.3.2 | mDNS scan for `_jellyfin._tcp`. |
| Imagery | `cached_network_image` ^3.4, `flutter_svg` ^2.0, `palette_generator` ^0.3 | All cover art through `cached_network_image`. |
| Fonts | `google_fonts` ^6.2 | Inter Variable + JetBrains Mono. |

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

// State streams
player.stream.position    // Stream<Duration>
player.stream.playing     // Stream<bool>
player.stream.shuffle     // Stream<bool>
player.stream.loop        // Stream<Loop>  (Loop.off / Loop.file / Loop.playlist)
player.stream.rate        // Stream<double>
player.stream.spectrum    // Stream<FftFrame> — 64 bands, post-DSP, ~30 fps
player.stream.coverArt    // Stream<CoverArt?> — embedded art bytes
player.stream.metadata    // Stream<Map<String, String>>
player.stream.playlist    // Stream<Playlist>

// DSP
await player.setAudioEffects(AudioEffects(superequalizer: ..., acompressor: ...));
await player.setReplayGain(ReplayGainSettings(mode: ReplayGain.track));
await player.setGapless(Gapless.weak);

// Loop enum values
Loop.off       // no looping
Loop.file      // repeat current track
Loop.playlist  // repeat entire queue
```

## 3. Source-tree map

```
lib/
├─ main.dart                ← runApp + first-frame boot trace + AudioService init
├─ app/
│  ├─ app.dart              ← Root MaterialApp.router
│  ├─ router.dart           ← go_router config (shell + nested routes)
│  └─ theme.dart            ← ThemeData built from design tokens
├─ design_tokens/           ← Single source of truth for §4 visual spec
│  ├─ colors.dart           ← OKLCH-derived sRGB hexes
│  ├─ motion.dart           ← Five duration tiers, five easing curves (§4.2)
│  ├─ spacing.dart          ← 4-pt grid, mini-player insets
│  ├─ radii.dart            ← Pill / md / lg corner rules
│  ├─ typography.dart       ← Inter Variable scale
│  └─ tokens.dart           ← Re-exports for `import '../../design_tokens/tokens.dart';`
├─ core/
│  ├─ audio/
│  │  ├─ player_service.dart        ← AfPlayerService: mpv_audio_kit + audio_service bridge
│  │  ├─ play_actions.dart          ← Cross-cutting play entry points (playQueue, playAlbum, etc.)
│  │  ├─ jellyfin_playback_reporter.dart ← POST /Sessions/Playing* lifecycle
│  │  ├─ live_update_service.dart   ← Android 16+ Live Update chip
│  │  └─ spectral_extractor.dart    ← palette_generator → Spectral triple
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
│  ├─ beat_pulse_artwork.dart ← FFT-driven artwork pulse (fftSpectrumProvider)
│  ├─ waveform.dart         ← Waveform scrubber widget
│  └─ …
└─ utils/
   ├─ log.dart              ← afLog() wrapper around dart:developer.log
   ├─ oklch.dart            ← OKLCH → sRGB conversion
   └─ time_format.dart      ← Duration formatting helpers
```

## 4. Design spec — non-negotiables

### 4.1 Colour
- Indigo scale (`AfColors.indigo50…900`) is derived from **OKLCH**. Do not
  eyeball-adjust hexes. Derive new colors in `lib/utils/oklch.dart` first.
- `AfColors.surfaceBase = #0B0B14`. `textPrimary` is white with 92% alpha.

### 4.2 Motion (`lib/design_tokens/motion.dart`)
- **Exactly five** duration tiers: `instant 80ms`, `quick 160ms`,
  `standard 240ms`, `expressive 400ms`, `long 600ms`. Material defaults
  (200/300/500ms) are forbidden — `test/design_tokens_test.dart` enforces this.
- Exactly five easing curves: `easeStandard`, `easeEmphasized`, `easeOut`,
  `easeIn`, `linear`. Audio-coupled animations (waveform, progress ring,
  lyric scroll, artwork pulse) MUST use `linear`.

### 4.3 Mini-player rules
- **56 dp tall, 12 dp horizontal margin, 16 dp gap to bottom nav.**
- `AfSpacing.bottomInsetWithMiniAndNav` is the canonical bottom-inset for
  every scrollable.
- Visible only when the queue is non-empty.

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
- **`DeviceId` is a per-install random 16-byte value** in `flutter_secure_storage`.
- Non-ASCII bytes in the header are replaced with `_`.

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

### 5.3 Router-level auth redirects

`go_router` is wired with a `refreshListenable` that fires when
`authProvider` changes. The `redirect` callback sends signed-in users
to `/home` and anonymous users to `/`. Every onboarding route must
start with `/onboarding/`.

## 6. Build, run, lint, test

```bash
flutter pub get
flutter run --debug
flutter analyze --no-fatal-infos   # 0 errors, 0 warnings
flutter test
flutter build apk --release
flutter build apk --release --split-per-abi
adb logcat -c && adb logcat -s flutter
```

## 7. Debug trace conventions

Use `afLog('<category>', '<message>')` from `lib/utils/log.dart`.

| Prefix | When |
|---|---|
| `aetherfin:boot` | Boot ordering, auth restoration |
| `aetherfin:http →/←/✕` | HTTP request / response / error |
| `aetherfin:error` | Caught exception + stacktrace |
| `aetherfin:data` | Provider data provenance (`source=live\|demo`) |
| `aetherfin:audio` | Player state transitions |

## 8. Data layer conventions

- `JellyfinClient` is the **only** file that speaks HTTP.
- All endpoints assert `userId` via `_assertUser()`.
- No `json_serializable`. Models are hand-written in `lib/core/jellyfin/models/`.
- Image URLs embed the `tag` query param for HTTP cacheability.

## 9. PR & CI rules

- Run `flutter analyze --no-fatal-infos` and `flutter test` before pushing.
- Do **not** force-push to `main`.
- Do **not** disable plugins or change the auth header shape to "fix" a 500.

## 10. Things AI agents have gotten wrong before

1. **"Just send Token="" — it's cleaner."** No. Omit the field entirely.
2. **"Static DeviceId is fine."** No. Per-install random value in secure_storage.
3. **"Use `/Search/Hints`."** No. Use `/Users/{id}/Items?searchTerm=…`.
4. **"Material animation defaults are fine."** No. Five durations, five curves, tests enforce it.
5. **"Use `just_audio` for playback."** No. The audio engine is now `mpv_audio_kit`. `AfPlayerService` wraps it.
6. **"Loop modes are `LoopMode.off/all/one`."** No. mpv_audio_kit uses `Loop.off / Loop.playlist / Loop.file`.
7. **"Build a parallel HTTP client."** Don't. Add a method to `JellyfinClient`.
8. **"Hydrate `AuthNotifier` asynchronously."** No. Load auth in `main()` and inject via `initialAuthProvider`.
9. **"go_router will figure out where to send a signed-in user."** No. Without `redirect:` + `refreshListenable`, you land on WelcomeScreen.
10. **"`context.pop()` is safe on any screen."** No. Guard with `canPop()` on screens reached via `context.go()`.

## 11. Glossary

- **`RunTimeTicks`**: Jellyfin duration unit. 1 tick = 100 ns. Divide by 10 for microseconds.
- **`PrimaryImageTag`**: Short hash for HTTP cache-busting on image URLs.
- **`Loop.off / Loop.file / Loop.playlist`**: mpv_audio_kit loop enum (replaces `just_audio`'s `LoopMode`).
- **`FftFrame`**: mpv_audio_kit spectrum frame — `bands: Float32List` (64 values in [0,1]).
- **`AfPlayerService`**: The app's audio handler. Extends `BaseAudioHandler` (audio_service) and wraps `Player` (mpv_audio_kit).

---

When something here becomes wrong, update this file in the same PR that
makes the change wrong. CLAUDE.md drifting from reality is worse than no
CLAUDE.md at all.
