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

## Widget / Quick Settings tile

- Android home screen widget showing current track + play/pause
- Quick Settings tile for play/pause toggle

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
