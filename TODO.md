# TODO

## Offline track cache (Server mode)

Cache fully streamed songs to disk so they don't need to be fetched from the server again on replay.

### Requirements

- Save raw audio bytes to app-private storage after a track finishes streaming completely
- Track manifest (which tracks are cached, file sizes, last-played timestamps)
- Before opening a stream URL, check if the track is cached locally — use `file://` path instead
- LRU eviction when cache exceeds user-configured max size
- Settings UI: toggle on/off, max cache size picker (500 MB / 1 GB / 2 GB / 5 GB / 10 GB), "clear cache" button with current usage display
- Handle partial downloads (don't cache interrupted streams)
- Invalidation strategy: re-fetch if server file changes (compare `PrimaryImageTag` or `DateModified`)

### Implementation notes

- New dependency needed for manifest storage (SQLite via `drift` or simple JSON file)
- Hook into `resolveStreamUrl` in `PlayActions` — check cache before building network URL
- Listen to `player.stream.completed` or track the stream progress to know when a track is fully downloaded
- mpv's `cache-on-disk` might handle some of this natively — investigate before building custom
- File naming: use track ID as filename (GUIDs are unique, no collisions)
- Storage path: `getApplicationSupportDirectory()` / `audio_cache/`

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
