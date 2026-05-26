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

---

# Concurrency & Operation Serialization (May 2026)

## Synchronization
- [x] Create `AfAsyncLock` class helper for sequential async operation chain execution
- [x] Serialize all queue mutations (`playQueue`, `setAfShuffleMode`, `reorderQueue`, `removeFromQueue`, `insertIntoQueue`, `playNext`, `addToQueue`) using `_queueLock`

## Concurrency and Leak Prevention
- [x] Sequential additions in `playQueue` one-by-one via `_player.add()` loop with generation checks at each step
- [x] Generation counter (`_queueLoadGen`) and early abort checks in `playQueue` to preempt stale load tasks
- [x] Connect `_isLoadingQueue` callback to `AfPositionTracker` to reset position anchor and ignore raw position during load transitions
- [x] Guard `seek`, `skipToNext`, `skipToPrevious`, and `skipToQueueItem` to prevent concurrent control mutations during active queue load

## Quality
- [x] flutter analyze — 0 issues
- [x] flutter test — all 101 tests pass (including new concurrency tests)

---

# Shuffle & Loop Serialization (May 2026)

## Race conditions fixed
- [x] `setAfLoopMode` `_jumpAndPlay(0)` wrapped in `_queueLock` — prevents playlist event firing during concurrent queue mutation
- [x] `completed` stream handler critical section wrapped in `_queueLock` — atomic queue state read prevents stale `currentIndex`/`currentQueue.length`
- [x] `skipToNext`, `skipToPrevious`, `skipToQueueItem` wrapped in `_queueLock` — serializes skip operations against queue mutations

## Loop.file double-handling fixed
- [x] Removed redundant `_jumpAndPlay(currentIndex)` in completed handler for `Loop.file` — mpv's `loop-file=inf` restarts the file internally. The call triggered a second `playlist-play-index`, causing an audible first-second glitch on each loop.

## Quality
- [x] flutter analyze — 0 issues
- [x] flutter test — all 114 tests pass

---

# UI Revamp & Icon Migration (May 2026)

## Lucide Icons Migration
- [x] Replaced hugeicons + cupertino_icons with `lucide_icons_flutter` for all UI icons
- [x] Import from `package:lucide_icons_flutter/lucide_icons.dart`
- [x] Removed hugeicons dependency entirely

## Now Playing Screen
- [x] Gradient background via `AnimatedContainer` + spectral colors (runtime extracted from artwork)
- [x] Translucent queue screen with frosted-glass effect (`Color(0xB30B0B14)`)
- [x] Improved More sheet — volume icon, track details non-fullscreen, install fix
- [x] Fixed MoreItem icon/text vertical alignment

## Bottom Sheet Redesign
- [x] Moved drag handles from theme to per-sheet manual handles (avoids floating transparent handle)
- [x] Theme sets `showDragHandle: false` with `Colors.transparent` background
- [x] Each sheet (`album_more_sheet`, `track_details_sheet`, `save_to_playlist_sheet`) adds manual drag handle
- [x] Unified container background to `Color(0xB30B0B14)` across all sheets
- [x] Removed `DraggableScrollableSheet` wrapper from `track_details_sheet.dart`

## Context Menu Migration
- [x] Album 3-dot menu converted from bottom sheet to dialog (`af_dialog.dart`)
- [x] Track long-press context menus converted from bottom sheets to dialogs
- [x] Reduced dialog content padding from 24px to 16px on all sides

## Equalizer Fixes
- [x] `_scrollSafetyTimer` (300ms fallback) for scroll-end detection when `ScrollEndNotification` doesn't fire
- [x] `UserScrollNotification idle` listener catches finger-lift at scroll boundary
- [x] `ScrollUpdateNotification` keepalive extends safety timer while actively scrolling
- [x] Seek-after-complete: `seek()` now detects `wasCompletedAtEnd` and calls `play()` to resume playback

## Quality
- [x] flutter analyze — 0 issues
- [x] flutter test — all tests pass

---

# Media Session & QS Fixes (May 2026)

## QS Media Session Fixes
- [x] `shouldAdvancePosition` returns `false` when `isAtQueueEnd && !playing` — prevents stuck `playing=true` state
- [x] `trackEnded` fallback in `_updateMediaSession` overrides transient `playing=true` using position >= duration at queue end
- [x] Speed: use `effectivePlaying ? s.rate : 0.0` (was always `s.rate` — kept progress bar running after queue end)
- [x] Position tracker uses `shouldAdvancePosition` as single truth source
- [x] `_playbackEnded` flag in `AfQueueManager` + `processPlaylistEvent` guard prevents track reinstate after `endPlayback()`

## Quality
- [x] flutter analyze — 0 issues
- [x] flutter test — all tests pass

---

# Skeleton Loading Screens (May 2026)

- [x] Created reusable `ShimmerLayout` base widget (`lib/widgets/skeleton.dart`) with `LinearGradient` shimmer
- [x] Dedicated skeleton widgets for each screen in `lib/widgets/skeletons/`:
  `home_skeleton.dart`, `album_card_skeleton.dart`, `library_skeleton.dart`,
  `album_skeleton.dart`, `artist_skeleton.dart`, `genre_skeleton.dart`,
  `playlist_skeleton.dart`, `track_row_skeleton.dart`, `search_skeleton.dart`,
  `lyrics_skeleton.dart`, `sheet_skeleton.dart`
- [x] Wired skeleton widgets to all screens — shown during data fetch, replaced with content on load

## Quality
- [x] flutter analyze — 0 issues
- [x] flutter test — all tests pass

---

# Code Quality & Infrastructure (May 2026)

## Analyzer
- [x] Expanded `analysis_options.yaml` with 12 stricter lint rules
- [x] Fixed all 363 info-level lints across 94 files via `dart fix --apply` + manual fixes
- [x] `flutter analyze --no-fatal-infos` reports **0 issues** across entire codebase

## Dependency Management
- [x] Pinned exact dependency versions in `pubspec.yaml` (all `: x.y.z` instead of `^x.y.z`)
- [x] Added `lucide_icons` (^0.257.0) and `lucide_icons_flutter` (^3.1.14+1)
- [x] Added `lucide_icons` to Icons section of tech stack

## Settings Refactoring
- [x] Replaced hand-rolled save/load triples with `SettingsKey<T>` typed descriptor pattern
- [x] Each setting has `keyName`, `defaultValue`, `encoder`, `decoder`
- [x] Eliminated save/load boilerplate in `player_settings_store.dart`

## Cover Art Caching
- [x] `CoverCacheManager` with LRU-evicted disk cache for cover art
- [x] Orphan temp file cleanup on startup
- [x] LRU eviction test handles filesystem-dependent directory order

## Client-Side Pagination
- [x] Infinite scroll for library tracks (client-side pagination)
- [x] Load-more-on-scroll pattern for large libraries

## AudioVisualScrubber Tests
- [x] Widget tests for `AudioVisualScrubber` with FFT spectrum mocking
- [x] Verifies rendering with mock `FftFrame` data

## Defensive Fixes
- [x] Hero card Play button: fixed `RenderFlex` overflow when album title wraps to 2 lines
- [x] `ScrollDirection` explicit import for `flutter/rendering.dart`
- [x] QS media session stuck fix: `trackEnded` fallback + speed zero on pause
- [x] Remove redundant `_player.stream.position` listener causing UI lag on Samsung S901E
- [x] Reduce UI lag during active playback (optimized polling)
- [x] Migrate from explicit Kotlin Gradle Plugin to Flutter built-in Kotlin
- [x] Override Kotlin to 2.2.20 in `settings.gradle.kts` to silence deprecation warning
- [x] CI: APK naming standardization, Telegram delivery via appleboy/telegram-action

## Quality
- [x] flutter analyze — 0 issues
- [x] flutter test — all tests pass

---

# Queue Initial Load Fix (May 2026)

## Problem
- `playQueue` with large queues (>5 tracks) had multi-second delay before playback started
- `openAll()` loads all tracks into mpv before returning — O(n) delay proportional to queue size

## Solution
- Cap initial load to **30 forward tracks** (`_queueLoadLimit`) loaded via `open(target, play: true)` + sequential `add()` loop
- Remaining tracks stored in `_cachedOverflow` (in-memory) for shuffle pool expansion
- `_cachedOverflow` used by shuffle engine to replace consumed tracks from the cache
- `_totalTracksCount` tracks total size for accurate index calculations
- Generation counter (`_queueLoadGen`) aborts stale loads on rapid queue changes

## Files Changed
- `lib/core/audio/player_service.dart` — queue splitting, overflow caching, sequential add loop with gen checks
- `lib/core/audio/queue_manager.dart` — overflow storage, total count tracking, shuffle pool expansion from cache

## Quality
- [x] flutter analyze — 0 issues
- [x] flutter test — all tests pass (including new queue_manager_test.dart cases)

---

# Smart Queue & Autoplay (May 2026)

## Problem
- No autoplay logic existed when a playlist or the active playback queue finished; the player simply stopped, leading to a disconnected experience.
- Tapping a single track (such as recently played) played only that single song and stopped, whereas a modern music player (like Spotify) should seed a continuous radio/mix of similar tracks.
- Local mode lacked a real similarity query engine to back an instant mix (simply falling back to shuffling random songs from the same artist).

## Solution
- Persisted an **Autoplay similar tracks** user setting via `PlayerSettingsStore` and wired it into settings UI.
- Hooked `onGetSimilarTracks` into the player completed event handler under `Loop.off` mode. When the queue finishes, similar tracks are requested from the active backend, appended to the queue, and playback is seamlessly continued.
- Overrode `playSingle` to immediately trigger `playInstantMix` (seeding recommendations) when Autoplay is active.
- Refactored Local Mode's similarity engine to run a scored SQL `customSelect` query directly in SQLite, scoring candidate tracks based on matching artist, album artist, genre, and close release era (+/- 5 years), returning recommendations in milliseconds.

## Files Changed
- `lib/core/audio/player_settings_store.dart` — descriptor and persistence functions for autoplay setting
- `lib/state/settings_providers.dart` — provider for autoplay setting
- `lib/main.dart` — load setting at boot and override provider
- `lib/features/settings/settings_sections.dart` / `settings_screen.dart` — added UI toggle for Autoplay
- `lib/core/local/local_db_tracks.dart` / `local_db.dart` — implemented scored similarity SQL query in Drift
- `lib/core/local/local_backend.dart` — updated `instantMix` to query similar tracks
- `lib/core/audio/player_service.dart` — added queue-end callback hook and play continuation logic
- `lib/state/player_providers.dart` — wired completion recommendation fetch hook and filtered duplicate tracks
- `lib/core/audio/play_actions.dart` — updated single play control to fetch recommendations if Autoplay is active

## Quality
- [x] flutter analyze — 0 issues
- [x] flutter test — all 350+ tests pass (no regressions)

---

# Unit Test Performance Optimization (May 2026)

## Problem
- Running unit tests was taking a long time due to real-world delays (9s, 5s, 2s) in `playlist_undo_buffer_test.dart` and `audio_device_manager_test.dart`, causing a slow test feedback loop.

## Solution
- Refactored `test/playlist_undo_buffer_test.dart` and `test/audio_device_manager_test.dart` to use `package:fake_async/fake_async.dart`.
- Replaced real-time `await Future.delayed(...)` calls with synchronous `async.elapse(...)` calls, enabling the tests to execute instantly.
- Reduced overall test suite run time from 50s+ to ~27s.

## Quality
- [x] flutter analyze — 0 issues
- [x] flutter test — all 350 tests pass


