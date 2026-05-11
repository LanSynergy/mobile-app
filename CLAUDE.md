# CLAUDE.md — Aetherfin Project Guide

This document is the **single source of truth** for AI coding agents working
on Aetherfin (Claude, Devin, Cursor, GPT, etc.). Read this end to end before
making changes. It captures the constraints, conventions, and gotchas
discovered while building the v1 client and is updated as we learn more.

## 1. What Aetherfin is

A native-feeling Android music player backed by a self-hosted **Jellyfin**
server. The only first-class platform is Android. iOS may follow but is not
considered when making trade-offs. The app is a single Flutter binary that
talks to Jellyfin over HTTP.

> **North star:** Spotify's polish, Apple Music's typography, Soulseek's
> respect for the listener. Aetherfin must read as a *premium music* app,
> not "a Jellyfin client."

## 2. Tech stack (exact versions)

| Layer | Choice | Notes |
|---|---|---|
| Framework | Flutter **3.41.9 stable**, Dart **3.11.5** | `flutter --version` must match. The CI workflow pins this. |
| State | `flutter_riverpod` ^2.6 | `FutureProvider.autoDispose`, `StateNotifierProvider`. No `ChangeNotifier`. |
| Routing | `go_router` ^14.7 | See `lib/app/router.dart` — shell route with bottom nav. |
| HTTP | `dio` ^5.7 + `dio_cache_interceptor` ^3.5 | One Dio per `JellyfinClient`. Auth header is baked into `BaseOptions.headers`. |
| Audio | `just_audio` ^0.10 + `audio_service` ^0.18 | Lock-screen controls; deferred init after first frame. |
| Storage | `flutter_secure_storage` ^9.2 (creds + deviceId), `shared_preferences` ^2.3 (settings) | Never store creds in shared_preferences. |
| Discovery | `multicast_dns` ^0.3.2 | mDNS scan for `_jellyfin._tcp` on the local network. |
| Imagery | `cached_network_image` ^3.4, `flutter_svg` ^2.0, `palette_generator` ^0.3 | All cover art renders through `cached_network_image`. |
| Fonts | `google_fonts` ^6.2 | Inter Variable + JetBrains Mono. Fetched at runtime, cached on disk. |

The min Android SDK is **21** (Android 5.0). Built with **Java 17** + Gradle
in CI. Local Java 17 is required.

## 3. Source-tree map

```
lib/
├─ main.dart                ← `runApp` + first-frame boot trace + AudioService kick
├─ app/
│  ├─ app.dart              ← Root MaterialApp.router
│  ├─ router.dart           ← go_router config (shell + nested routes)
│  └─ theme.dart            ← ThemeData built from design tokens
├─ design_tokens/           ← The single source of truth for §4 visual spec
│  ├─ colors.dart           ← OKLCH-derived sRGB hexes — DO NOT modify without spec change
│  ├─ motion.dart           ← Five duration tiers, five easing curves (§4.2)
│  ├─ spacing.dart          ← 4-pt grid, mini-player insets
│  ├─ radii.dart            ← Pill / md / lg corner rules
│  ├─ typography.dart       ← Inter Variable scale
│  └─ tokens.dart           ← Re-exports for `import '../../design_tokens/tokens.dart';`
├─ core/
│  ├─ audio/                ← PlayerService (just_audio + audio_service) + play actions
│  ├─ demo/                 ← `DemoLibrary` — bundled albums/artists for the onboarding preview
│  ├─ jellyfin/
│  │  ├─ client.dart        ← The only file that speaks HTTP to Jellyfin
│  │  ├─ auth_storage.dart  ← secure_storage wrappers (token, userId, deviceId)
│  │  ├─ discovery.dart     ← mDNS scan + public-info probe
│  │  └─ models/            ← Plain Dart classes — NO json_serializable codegen
│  └─ lyrics/               ← LRC parser (sync + unsynced)
├─ features/                ← One folder per top-level screen
│  ├─ home/        library/  album/      artist/
│  ├─ search/      queue/    now_playing/ lyrics/
│  ├─ onboarding/  profile/  settings/    cast_picker/  sleep_timer/
├─ state/
│  └─ providers.dart        ← All Riverpod providers in one file (intentional)
├─ widgets/                 ← Shared visual atoms (Tile, TrackRow, SectionHeader, GenreTile, MiniPlayer…)
└─ utils/                   ← oklch.dart, etc.
```

The deliberate "everything in `providers.dart`" decision: providers are
small, depend on each other heavily, and there are <30 of them. Splitting
across files made cross-references painful. Don't split it without a real
reason.

## 4. Design spec — non-negotiables

The design spec is a separate document (`docs/SPEC.md` in any future PR;
currently lives in the user's notes). What MUST hold true in code at all
times:

### 4.1 Colour
- Indigo scale (`AfColors.indigo50…900`) is derived from **OKLCH** with
  fixed lightness/chroma steps. Do not eyeball-adjust hexes. To add a new
  color, derive it in `lib/utils/oklch.dart` first.
- `AfColors.surfaceBase = #0B0B14`. `textPrimary` is white with 92% alpha.
- Quality-chip "lossless" = `AfColors.tealAccent`, "lossy" = `slate500`,
  "transcoded" adds 1dp `AfColors.warningAmber` border.

### 4.2 Motion (`lib/design_tokens/motion.dart`)
- **Exactly five** duration tiers: `instant 90ms`, `quick 180ms`,
  `standard 240ms`, `expressive 360ms`, `slow 500ms`. The 200/300/500ms
  Material defaults are forbidden — `test/design_tokens_test.dart` enforces
  this.
- Exactly five easing curves: `easeStandard`, `easeEntrance`, `easeExit`,
  `easeEmphasis`, `easeOvershoot`. Any new animation must pick from these.

### 4.3 Mini-player rules
- **56 dp tall, 12 dp horizontal margin, 16 dp gap to bottom nav** —
  `AfSpacing.bottomInsetWithMiniAndNav` is the canonical bottom-inset for
  every scrollable so content never hides under it.
- Visible only when the queue is non-empty. Tapping it opens Now Playing
  with a shared-element hero on the artwork.
- Slides up with `AfCurves.easeEntrance` over `AfDurations.standard`.

### 4.4 Profile rules (Settings → Profile)
Phases 1–8 of the spec require:
1. Avatar = first letter of Jellyfin display name, indigo-tinted.
2. Server name + Jellyfin version chip under the display name.
3. "Listening on" device row.
4. Quality preference selector (Auto / Lossless / Lossy / Data-saver).
5. Crossfade slider (0–12 s).
6. Lock-screen art selector (Album / Artist / Off).
7. "Sign out" — destructive red, double-confirm.
8. App version + git short SHA at the bottom.

If you're changing the profile screen, walk through this list before
shipping.

## 5. Jellyfin auth — battle-tested format

Every Jellyfin request carries:

```
Authorization: MediaBrowser UserId="…", Token="…", Client="Aetherfin", Device="Android", DeviceId="…", Version="0.1.0"
Content-Type: application/json
User-Agent: Aetherfin/0.1.0 (Android)
Accept: application/json
```

Rules learned the hard way:
- **`UserId` and `Token` are OMITTED entirely before login.** Sending
  `Token=""` triggers HTTP 500 in some plugin-heavy installs.
- **Send only `Authorization`** — not `X-Emby-Authorization`. Sending both
  confuses certain plugins' middleware.
- **Field order matches Finamp**: `UserId, Token, Client, Device, DeviceId,
  Version`.
- **`DeviceId` is a per-install random 16-byte value** persisted in
  `flutter_secure_storage`. Never reuse `"aetherfin-android"` or any other
  static value — Jellyfin keys session/device records on this, and a stale
  record from a previous install will crash session creation.
- Non-ASCII bytes in the header are replaced with `_` (defensive).

The canonical implementation lives in `_buildAuthHeader()` at
`lib/core/jellyfin/client.dart:120`. **Do not duplicate this logic.** Build
a fresh `JellyfinClient` instead if you need to override headers.

### 5.1 If `AuthenticateByName` returns 500
Almost always a server-side issue — confirmed by reproducing with `curl`:
```bash
curl -i -X POST 'http://SERVER/Users/AuthenticateByName' \
  -H 'Authorization: MediaBrowser Client="curl", Device="curl", DeviceId="curl-001", Version="1.0.0"' \
  -H 'Content-Type: application/json' \
  -d '{"Username":"u","Pw":"p"}'
```
If `curl` also returns 500, the server has stale `UserManager`/
`SessionManager` state. **Restart the Jellyfin Docker container.** This is
the known fix and it has solved every instance we've seen.

**Do not** disable plugins, downgrade Jellyfin, or modify our header to
work around it — those are all dead-ends.

## 6. Build, run, lint, test

```bash
# One-time
flutter pub get
flutter pub run flutter_launcher_icons     # regenerates Android adaptive icon

# Dev loop
flutter run --debug                        # connects to running emulator/device
flutter analyze --no-fatal-infos           # lint — must report 0 errors, 0 warnings
flutter test                               # all 6 tests must pass
flutter build apk --release                # produces build/app/outputs/flutter-apk/app-release.apk

# Connected device
adb logcat -c && adb logcat -s flutter     # boot + HTTP trace (see §7)
```

CI is `.github/workflows/build-apk.yml`. It runs on every PR + on `main`,
produces a debug APK, and uploads it as a workflow artifact. To download an
APK from a PR: open the PR's "Checks" → "build" → "Artifacts" →
`app-debug-apk.zip`.

## 7. Debug trace conventions

The app emits structured log lines so that an `adb logcat -s flutter`
output is enough to diagnose most issues without attaching a debugger.

| Prefix | When | Example |
|---|---|---|
| `aetherfin:boot` | Boot ordering, AudioService init | `aetherfin:boot first frame painted — kicking AudioService init` |
| `aetherfin:http →` | Outgoing request (method, URL, headers redacted, body redacted if auth-sensitive) | `aetherfin:http → POST http://srv/Users/AuthenticateByName` |
| `aetherfin:http ←` | Successful response (status, method, URL) | `aetherfin:http ← 200 GET http://srv/System/Info/Public` |
| `aetherfin:http ✕` | Failed response (status, method, URL) | `aetherfin:http ✕ 500 POST http://srv/Users/AuthenticateByName` |
| `aetherfin:error` | Caught exception with full Dio error + stacktrace | (multi-line block) |

When adding new diagnostics:
- Always go through `print('aetherfin:<category> …')`. No `debugPrint`,
  no `log()`, no `developer.log`.
- Redact tokens and any header containing `auth`.
- Redact bodies for endpoints whose path contains `authenticate`.

## 8. Data layer conventions

- `JellyfinClient` is the **only** file that speaks HTTP. Anything that
  needs Jellyfin data goes through a method here.
- All endpoints assert `userId` is set via `_assertUser()`. They throw
  `StateError` if called pre-auth. Providers always check
  `jellyfinClientProvider != null` before calling.
- Pagination is not implemented yet. Lists default to `limit: 20` (home /
  recent rails) or `limit: 200` (library tabs). Add pagination only when
  a user-visible "load more" is added to the UI.
- Image URLs are built via `_buildImageUrl()` which embeds the `tag` query
  param. This makes URLs cacheable and lets `cached_network_image` reuse
  decoded images across screens.
- **No `json_serializable`**. Models are hand-written. The surface is small
  and codegen makes the build slower without meaningful benefit.

When the user is signed out (no `JellyfinClient`), providers fall back to
`DemoLibrary` so the onboarding preview screens have something to render.
Live screens should never hit `DemoLibrary` — they should be empty/loading
states until auth lands.

## 9. PR & CI rules

- Branch name: `devin/<timestamp>-<short-slug>` (see Devin git guidelines).
  Other agents may use their own prefix; just keep timestamps for sort
  order.
- Always run `flutter analyze --no-fatal-infos` and `flutter test` before
  pushing. CI runs the same.
- The PR body must follow `.github/PULL_REQUEST_TEMPLATE.md` if present.
- Do **not** force-push to `main`. `--force-with-lease` is okay on your
  own feature branches.
- Do **not** disable plugins, downgrade Jellyfin, or change the auth header
  shape to "fix" a 500. Reproduce with `curl` first — see §5.1.

## 10. Things AI agents have gotten wrong before

A non-exhaustive list of footguns. Read this before you do something that
seems obvious.

1. **"Just send Token="" — it's cleaner."** No. Omit the field entirely.
   (§5.)
2. **"Static DeviceId is fine for an Android app."** No. Per-install
   random value, persisted in secure_storage. (§5.)
3. **"`/Users/{id}/Items?searchTerm=…` doesn't work, use `/Search/Hints`."**
   No. `/Search/Hints` returns half-typed BaseItemDto shapes and is harder
   to parse. Stick with the standard items endpoint.
4. **"Material defaults are fine for animation curves."** No. There are
   exactly five durations and five curves and `test/design_tokens_test.dart`
   asserts it. (§4.2.)
5. **"The launcher icon doesn't matter."** It does — `pubspec.yaml`
   contains a `flutter_launcher_icons` config and the brand assets live in
   `assets/brand/`. Run `flutter pub run flutter_launcher_icons` after any
   icon change.
6. **"Use `Provider` for genres; they're static."** They're not — once
   signed in we hit `/MusicGenres`. Use `FutureProvider.autoDispose`.
7. **"Build a parallel HTTP client for endpoint X."** Don't. Add a method
   to `JellyfinClient`.

## 11. Glossary

- **Jellyfin item type**: `Audio`, `MusicAlbum`, `MusicArtist`, `Playlist`,
  `MusicGenre`. These are the only types Aetherfin renders.
- **`RunTimeTicks`**: Jellyfin's duration unit. 1 tick = 100 ns. Divide
  by 10 to get microseconds and then build a `Duration`.
- **`PrimaryImageTag`**: A short hash Jellyfin returns alongside an item.
  Including it in the image URL makes the URL change when the image
  changes — perfect for HTTP caching.
- **`Latest` endpoint** (`/Users/{id}/Items/Latest`): paged-list of items
  recently added to a user's library. Different from a normal item query
  with `SortBy=DateCreated` — `Latest` already returns deduped, grouped
  results that match what the Jellyfin web "Latest Music" row shows.

---

When something here becomes wrong, update this file in the same PR that
makes the change wrong. CLAUDE.md drifting from reality is worse than no
CLAUDE.md at all.
