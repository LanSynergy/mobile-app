# TODO

## Crossfade between tracks

Smooth audio crossfade when transitioning between tracks (configurable duration).

- mpv_audio_kit may support this via `--audio-crossfade` or custom filter chain
- Settings UI: crossfade duration slider (0–12 seconds, 0 = disabled)
- Should respect gapless mode setting (crossfade overrides gapless when enabled)

## Android Auto / Car mode

- Implement `MediaBrowserService` for Android Auto integration
- Browse library (albums, artists, playlists) from car head unit
- Playback controls from steering wheel / head unit
- Voice search support

## Visualizer pre-DSP tap

- Current FFT spectrum is post-DSP (reflects processed audio)
- Ideally show the raw signal before EQ/effects are applied
- Blocked on mpv_audio_kit adding a pre-DSP tap point
- Document as known limitation until library update

## mpv_audio_kit position observation

- observe_property for time-pos doesn't fire on some devices
- Currently using elapsed-time extrapolation as workaround
- getRawProperty('time-pos') also returns null/0 on affected devices
- May need to file upstream issue with mpv_audio_kit
- Investigate if this is related to aaudio driver or spectrum pipeline

---

# Completed

## Offline track cache (Server mode)
- [x] Save raw audio bytes to app-private storage after track finishes playing
- [x] Cache manifest stored in SQLite via Drift (`CacheEntries` table)
- [x] Redirect network stream URLs to `file://` cached URIs on cache hit
- [x] LRU eviction when cache size exceeds configured maximum limit
- [x] Settings UI for toggling cache on/off, selecting maximum cache size, and clearing cache
- [x] Automatic cleanup of orphaned temp download files on startup

## UI/UX
- [x] Hero album carousel — swipeable PageView with dot indicator
- [x] Bottom nav restyled — Google-style sliding pill background
- [x] Queue/Lyrics routes — NoTransitionPage to fix out-of-frame rendering
- [x] Bottom sheet drag handles — removed duplicates (theme provides one)

## UI/UX (continued)
- [x] Gradient background on Now Playing screen (AnimatedContainer + spectral colors)
- [x] Translucent queue screen with frosted-glass effect
- [x] Context menus converted from bottom sheets to dialogs (album 3-dot + track long-press)
- [x] Bottom sheet drag handles — per-sheet manual handles (theme provides `showDragHandle: false`)
- [x] Reduced dialog content padding from 24px to 16px all sides
- [x] More sheet redesign — volume icon, track details non-fullscreen
- [x] Lucide icons — replaced hugeicons across all UI

## Skeleton Loading
- [x] Reusable `ShimmerLayout` base widget
- [x] Dedicated skeleton widgets for all 11 screens
- [x] Shimmer animation with `LinearGradient`

## Bug fixes
- [x] musicBackendProvider autoDispose — releases HTTP client on sign-out
- [x] HttpClient leak in artwork download — try/finally ensures close
- [x] Nudge stacking — generation counter cancels stale chains
- [x] pruneDeletedFiles limit — SQL prefix query replaces allTracks()
- [x] Album ID parsing — lastIndexOf(':') supports colons in names
- [x] Nudge retries never reset — reset on playing=true
- [x] Playlist sync race — generation counter replaces Future.delayed
- [x] Constructor async calls — catchError guards on setAudioDriver/setAudioBuffer
- [x] Completed listener — async + awaited pause()/jumpAndPlay()
- [x] playQueue partial failure — _player.stop() to clear mpv playlist
- [x] _hex() in home_screen — try-catch with length validation + fallback color
- [x] Position extrapolation — capped at 1h when duration is zero
- [x] Concurrency and operation serialization — Sequential queue serialization, playback controls loading guards, position leaks prevention, and sequential track additions
- [x] Shuffle & loop serialization — `_queueLock` in `setAfLoopMode`, `completed` handler, `skipToNext/Previous/QueueItem`
- [x] Loop.file double-handling — removed redundant `_jumpAndPlay` when mpv handles loop-file internally
- [x] QS media session stuck on `playing=true` after track ends — `shouldAdvancePosition` guard + `trackEnded` fallback
- [x] QS progress bar runs forever after queue end — speed zero on pause, `playing=false` throttle fix
- [x] Equalizer phantom active state — scroll safety timer + idle listener for scroll boundary detection
- [x] Seek-after-complete doesn't resume playback — `wasCompletedAtEnd` detection + `play()` call in seek handler
- [x] Hero card Play button clipped — `RenderFlex` overflow fix when album title wraps
- [x] UI lag on Samsung S901E — removed redundant `_player.stream.position` listener
- [x] MoreItem icon/text vertical alignment fix
- [x] Queue initial load capped to 30 forward tracks + overflow caching for shuffle
- [x] `reorderQueue` allows insertion at end (index = length)
- [x] Smart Queue & Spotify-like Autoplay Similar Tracks (supporting Local scored similarity query, Jellyfin InstantMix, and Navidrome similar songs)


## Code Quality
- [x] All 363 info-level lints fixed — `flutter analyze --no-fatal-infos` reports 0 issues
- [x] 12 stricter lint rules added to `analysis_options.yaml`
- [x] Exact dependency versions pinned in `pubspec.yaml`
- [x] Hand-rolled save/load triples replaced with typed `SettingsKey<T>` descriptors
- [x] `CoverCacheManager` with LRU eviction for cover art
- [x] Orphan cover-art temp files cleaned up on startup
- [x] Client-side pagination with infinite scroll for library tracks
- [x] Widget tests for `AudioVisualScrubber` with FFT spectrum mocking
- [x] ScrollDirection explicit import fix
- [x] Kotlin migration: built-in Kotlin plugin + override to 2.2.20

## CI/CD
- [x] APK naming standardization for Telegram delivery
- [x] Telegram delivery via appleboy/telegram-action

## Android Native Integrations & UX (May 2026)
- [x] Android home screen widget with dynamic track info, playback state, and reactive favorite toggle
- [x] Dynamic app widget theming utilizing Palette API for artwork color extraction and contrast adjustments
- [x] Standard notification action buttons for shuffle and loop modes to bypass Android 13+ custom action issues
- [x] Dynamic launcher icon customization UI (Default, Midnight Accent, Emerald Sunset, Crimson Wave, Golden Sands)
- [x] Smart Bluetooth reconnection handler with a 5-minute auto-resume playback window
- [x] Reactive two-way favorite synchronization between the Flutter player session and the native MethodChannel

