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
- [x] `flutter test` — all 24 tests pass

---

# UI & UX Improvements — Progress

## Settings Screen
- [x] Samsung One UI–style grouped card layout
- [x] Colored circular icon backgrounds per category
- [x] Section labels above card groups
- [x] Dynamic version from PackageInfo
- [x] Source code link (url_launcher)
- [x] Licenses page (Flutter built-in showLicensePage)
- [x] Server section: user info, switch server, sign out with confirmation

## Library
- [x] Liked songs tab (fetches favorite tracks from Jellyfin/Navidrome)
- [x] `favoriteTracks` method added to MusicBackend interface
- [x] Jellyfin: `GET /Users/{id}/Items?Filters=IsFavorite&IncludeItemTypes=Audio`
- [x] Navidrome: `getStarred2.view` → parse `starred2.song`

## Bug Fixes
- [x] Navidrome stream uses `format=raw` to skip server-side transcoding
- [x] Progress bar resets on track change (force-emit Duration.zero on track switch)
- [x] Lyrics scroll resets on track change (clear _lastScrolledIndex)
- [x] Like button shows error snackbar on failure
- [x] Back gesture shows "press again to exit" confirmation on home tab
- [x] Hero album banner respects long titles (min-height + maxLines: 3)
- [x] EQ/DSP screen scrollable when master switch is off

## Quality
- [x] `flutter analyze` — 0 issues
- [x] `flutter test` — 27 tests pass
- [x] `.gitattributes` for consistent LF line endings
- [x] `core.autocrlf=input` for cross-platform compatibility
