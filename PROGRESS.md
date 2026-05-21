# Navidrome Support — Progress

## Architecture
- [x] Create abstract `MusicBackend` interface (`lib/core/backend/music_backend.dart`)
- [x] Add `ServerType` enum (jellyfin, subsonic) to `lib/core/jellyfin/models/server.dart`
- [x] Add `serverType` field to `JellyfinAuth`
- [x] Update `AuthStorage` to persist/restore `serverType`
- [x] Make `JellyfinClient` implement `MusicBackend` with all `@override` annotations

## SubsonicClient
- [x] Create `SubsonicClient` implementing `MusicBackend` (`lib/core/subsonic/client.dart`)
- [x] Subsonic token auth (`md5(password + salt)`)
- [x] Ping / server check
- [x] Albums (getAlbumList2, getAlbum)
- [x] Artists (getArtists, getArtist)
- [x] Tracks (search3 for all tracks)
- [x] Playlists (CRUD)
- [x] Search (search3)
- [x] Favorites (star/unstar, getStarred2)
- [x] Stream URL construction
- [x] Cover art URL construction
- [x] Lyrics (getLyricsBySongId)
- [x] Similar songs (getSimilarSongs2)
- [x] Scrobble / playback reporting
- [x] Genres (getGenres)

## Providers
- [x] Add `musicBackendProvider` (creates JellyfinClient or SubsonicClient based on serverType)
- [x] Keep `jellyfinClientProvider` as convenience alias for Jellyfin-specific ops
- [x] Update all library/search/lyrics/favorites/genre providers to use `MusicBackend`
- [x] Update `spectralProvider` auth headers to use `musicBackendProvider`
- [x] Update `favoriteToggleProvider` to use `musicBackendProvider`

## Onboarding
- [x] Auto-detect server type (probe Jellyfin publicInfo, then Subsonic ping)
- [x] Pass `serverType` through router to sign-in screen
- [x] Support Subsonic login flow in sign-in screen (ping to validate creds)
- [x] Hide API token toggle for Navidrome (not applicable)
- [x] Show Navidrome-specific instructions

## Playback
- [x] Update `PlayActions` to use `musicBackendProvider`
- [x] Update `JellyfinPlaybackReporter` to accept `MusicBackend` instead of `JellyfinClient`
- [x] Update `play_actions.dart` stream URL and auth header resolution
- [x] Update track context menu (play next, add to queue) to use `musicBackendProvider`

## UI Screens
- [x] Update `artwork.dart` auth headers to use `musicBackendProvider`
- [x] Update `now_playing_screen.dart` save-to-playlist to use `MusicBackend`
- [x] Update `playlist_screen.dart` (reorder, remove, rename, delete) to use `MusicBackend`
- [x] Update `album_screen.dart` favorite toggle to use `musicBackendProvider`
- [x] Update `library_scope_screen.dart` to use `musicBackendProvider`

## Quality
- [x] Run `flutter analyze --no-fatal-infos` — 0 errors, 0 warnings
- [x] Run `flutter test` — all 24 tests pass
- [x] Push all changes to `navidrome` branch

## Merge & Documentation
- [x] Merge `navidrome` branch into `main`
- [x] Update CLAUDE.md — multi-backend architecture, Subsonic auth, source-tree, glossary, AI gotchas
- [x] Update README.md — Navidrome support, dual-backend architecture diagram, requirements
- [x] Update PRIVACY.md — dual-backend data handling, Subsonic API section

---

# Audio DSP & Effects — Progress

## Visualizer DSP Bypass
- [ ] Make FFT spectrum ignore audio effects (pre-DSP tap)
  - Note: `mpv_audio_kit` 0.1.3 spectrum is post-DSP (`pcm-tap-frame`).
    No pre-DSP tap available in the library. Documenting as known limitation.

## Equalizer & DSP UI (now_playing_screen.dart)
- [x] Bass shelf (+/- 12 dB)
- [x] Treble shelf (+/- 12 dB)
- [x] Loudness normalization (EBU R128) toggle
- [x] Dynamic compressor with fine-tuning (threshold, ratio, attack, release)
- [x] Noise gate with fine-tuning (threshold, ratio, attack, release)
- [x] De-esser with fine-tuning (intensity, mix, frequency)
- [x] 18-band Superequalizer (ISO graphic EQ) — per-band sliders, 0..4 linear gain
- [x] EQ presets — 8 built-in (Rock, Jazz, Classical, Hip-Hop, Electronic, Vocal, Bass/Treble Boost) + save/delete custom user presets
- [x] Echo / delay (AechoSettings) — multi-tap with pipe-separated delays/decays, in/out gain
- [x] Rubberband pitch & tempo shifting — 0.5x..2.0x sliders
- [x] Crossfeed (headphone) — strength slider
- [x] Stereo widening — delay slider
- [x] Phaser — in/out gain, delay, decay, speed
- [x] Flanger — delay, depth, regen, width, speed
- [x] Chorus — multi-voice with pipe-separated delays/decays/speeds/depths
- [x] Tremolo — frequency, depth
- [x] Vibrato — frequency, depth
- [x] Harmonic exciter — amount slider
- [x] Noise gate — toggle
- [x] Virtual bass — cutoff slider
- [x] Crystalizer (audio sharpener) — intensity slider
- [x] Bit-crusher — bits, mix, samples
- [x] Master on/off switch to bypass all effects
- [x] Reset all button — clears every effect
- [x] Extracted to dedicated full-screen route (/eq-dsp) with Scaffold + AppBar

## ReplayGain (settings_screen.dart)
- [x] Mode picker (Off / Track / Album)
- [x] Preamp adjustment (-15..+15 dB slider)
- [x] Fallback gain (-15..0 dB slider)
- [x] Clip prevention toggle

## Gapless & Prefetch (settings_screen.dart)
- [x] Gapless mode picker (Full / Weak / Off)
- [x] Prefetch next track toggle

## Persistence
- [x] ReplayGain mode — persisted via PlayerSettingsStore
- [x] ReplayGain preamp, fallback, clip — persisted
- [x] Gapless mode — persisted via PlayerSettingsStore
- [x] Prefetch playlist — persisted via PlayerSettingsStore
- [x] Audio effects bundle — JSON-serialized to shared_preferences
- [x] All settings restored on app startup via applyPersisted()

## Quality
- [x] `flutter analyze --no-fatal-infos` — 0 errors, 0 warnings
- [x] `flutter test` — all 96 tests pass

---

# Local Media Player Mode — Progress

## Phase 1: Foundation
- [x] Add drift and path dependencies
- [x] Create AppMode enum and appModeProvider
- [x] Persist app mode in shared_preferences (AppModeStore)
- [x] Create AppDatabase — Drift schema for tracks/folders/favorites/playlists
- [x] Create SafPlugin.kt — Android platform channel (folder picker, file listing, metadata, cover art)
- [x] Create SafPicker — Dart bridge with typed models

## Phase 2: Metadata Scanning
- [x] MetadataScanner — SAF file listing + tag extraction + cover art caching
- [x] LocalLibrary — high-level query interface
- [x] Cover art extraction (embedded tags → cache dir)
- [x] Incremental scan (lastModified check)
- [x] Scan progress reporting via StateProvider

## Phase 3: Onboarding & Mode Selection
- [x] ModeSelectScreen — server vs local choice
- [x] LocalSetupScreen — folder picker + scan progress
- [x] Router routes for /onboarding/mode and /onboarding/local-setup
- [x] Router redirect respects AppMode
- [x] Remove demo mode — delete DemoLibrary, replace all fallbacks

## Phase 4: Library Integration
- [x] Local-mode providers (localAlbums, localArtists, localTracks, localGenres)
- [x] Library screen uses local providers when appMode == local
- [x] Home screen uses local providers in local mode
- [x] Search queries local SQLite DB in local mode
- [x] Album/artist detail providers handle local:* IDs

## Phase 5: Playback
- [x] PlayActions handles local mode (content:// URIs, no auth headers)
- [x] Artwork widget loads file:// cover art from disk
- [x] Playback reporting disabled in local mode
- [x] Favorites work in local mode (stored in local SQLite via Drift)
- [x] Playlists work in local mode (stored in local SQLite via Drift)
- [x] LocalBackend implements MusicBackend — same provider interface as server backends

## Phase 6: Settings & Polish
- [x] Music folders section in settings (local mode only)
- [x] Re-scan library button
- [x] Switch mode option (returns to onboarding)
- [x] Docs updated (README, PROGRESS)

## Quality
- [x] flutter analyze — 0 issues
- [x] flutter test — 96 tests pass


---

# Smart Playlists — Progress

## Core
- [x] SmartPlaylist model (rules, combinators, sort, limit)
- [x] SmartPlaylistDb — SQLite CRUD storage
- [x] SmartPlaylistEngine — resolves via SQL (local) or client-side filter (server)
- [x] Providers: smartPlaylistDbProvider, smartPlaylistsProvider, smartPlaylistTracksProvider

## UI
- [x] SmartPlaylistListScreen — Samsung One UI grouped card style
- [x] SmartPlaylistDetailScreen — header card with play/shuffle + track list
- [x] SmartPlaylistEditScreen — sectioned form (name, match mode, rules, sort & limit)
- [x] Navigation entry point in Library > Playlists tab (both server and local mode)
- [x] Routes: /smart-playlists, /smart-playlist/new, /smart-playlist/:id, /smart-playlist/:id/edit

---

# Playback & UI Fixes (May 2026)

## Progress Bar / Position Tracking
- [x] Expose getRawProperty('time-pos') and getRawProperty('duration') on AfPlayerService
- [x] Elapsed-time extrapolation when mpv's observe_property doesn't fire
- [x] durationStreamProvider — uses mpv's actual duration, falls back to track metadata
- [x] Reset position/duration to zero on track change (prevents stale value flicker)

## Instant Playback
- [x] Large queues (>5 tracks): open() target immediately, add() rest in background
- [x] Suppress playlist sync during queue building (prevents wrong track display)
- [x] Extended suppression window (500ms) to catch delayed mpv playlist events

## A-B Loop
- [x] abLoopAProvider / abLoopBProvider StateProviders (bypass broken observe_property)
- [x] Button uses getRawPosition() for actual position
- [x] Button rebuilds via ref.watch (orange when A set, accent when A+B active)
- [x] Reset on track change
- [x] More sheet dialog also uses getRawPosition()

## Mini Player
- [x] Hidden when keyboard is open (viewInsets.bottom check)
- [x] Always mounted with AnimatedSlide/AnimatedOpacity for instant appearance
- [x] Shows immediately when playback starts from any screen

## Audio
- [x] 200ms audio buffer default (prevents jittering during background/Doze)
- [x] Auto-pause on Bluetooth disconnect / headphone unplug (audioDevice stream)
- [x] setAudioDriver('aaudio') in constructor before _bindStreams()

## Notification
- [x] Download artwork to local file for notification background (auth-protected URLs)
- [x] LiveUpdate notification disabled (Android 16 MediaStyle already promoted)
- [x] POST_NOTIFICATIONS permission request for stock Android 13+

## Local Library
- [x] Prune deleted files during rescan (pruneDeletedFiles called in scanAll)
- [x] Playlists tab added to local mode sections (for smart playlists access)

## Settings
- [x] Sample rate dialog shows actual value when Auto selected
- [x] Bit depth dialog shows actual value when Auto selected
- [x] "Matches the source file" subtitle on Auto options

## Misc
- [x] Removed placeholder ask_sheet.dart (unused AI search mock)
- [x] Build ID generator uses stderr.writeln (resolves avoid_print lint)
- [x] Release workflow auto-increments +N build number
- [x] flutter analyze: No issues found

---

# Iterative Bug Fixes (May 2026)

## Resource Management
- [x] `musicBackendProvider` changed to `autoDispose` — releases HTTP client + cache on sign-out
- [x] `_downloadArtworkForNotification` HttpClient closed in `try/finally` — prevents socket leak on download failure
- [x] Cover art temp files cleaned up when switching sources — prevents disk space leak

## Playback Engine
- [x] `_nudgeRetries` reset to 0 when `playing` becomes true — fixes auto-advance permanently disabled after 3 failures
- [x] Playlist sync race condition fixed with generation counter (`_suppressPlaylistSyncGen`) — replaces fragile `Future.delayed` boolean
- [x] Nudge stacking prevented with generation counter (`_nudgeGen`) — rapid seeks/play no longer stack 30+ `setAudioDevice` calls

## Data Integrity
- [x] Album ID parsing uses `lastIndexOf(':')` instead of `split(':')` — supports colons in album names
- [x] Local search query normalized (trim + lowercase) before `library.search()` — consistent results
- [x] `pruneDeletedFiles` uses SQL prefix query instead of `allTracks()` — fixes orphaned tracks beyond 5000 limit

## UI
- [x] SubsonicApiError humanized on sign-in screen (code 40 → "Wrong username or password")
- [x] Queue and Lyrics routes use `NoTransitionPage` — fixes out-of-frame rendering
- [x] Bottom sheet duplicate drag handles removed — theme's `showDragHandle: true` was stacking with manual handles
- [x] Bottom nav restyled with Google-style sliding pill background (`indigo900` pill behind active tab)
- [x] Hero album section converted to swipeable PageView carousel (up to 5 albums, dot indicator, `viewportFraction: 0.92`)

## Quality
- [x] flutter analyze — 0 issues
- [x] flutter test — 96 tests pass

---

# Defensive Fixes (May 2026)

## Async Safety
- [x] `setAudioDriver`/`setAudioBuffer` in constructor wrapped with `.catchError()` — prevents unhandled crash on native plugin failure
- [x] `completed` stream listener made `async` — `pause()` and `_jumpAndPlay()` properly awaited
- [x] `_jumpAndPlay(nextIdx)` awaited in completed listener (was unawaited `Future<void>`)

## Playback Consistency
- [x] `playQueue` catch block calls `_player.stop()` — clears mpv playlist on partial failure
- [x] Position extrapolation capped at 1h when `duration == Duration.zero` — prevents absurd progress on wake

## Data Validation
- [x] `_hex()` in home_screen converted to try-catch with length validation + `AfColors.indigo600` fallback — matches `search_screen.dart` defensive pattern

## Quality
- [x] flutter analyze — 0 issues (was 0, still 0)
- [x] flutter test — 96 tests pass (no regressions)
