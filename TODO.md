# TODO

## Offline track cache

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

## Local media player mode

Support playing audio files directly from the device storage without requiring a Jellyfin server connection.

### Requirements

- Browse and play local audio files (MP3, FLAC, OPUS, WAV, M4A, OGG, etc.)
- Scan device storage for music (MediaStore or manual folder picker)
- Read embedded metadata (title, artist, album, duration) from file tags
- Read embedded cover art from file tags
- Integrate with the existing queue, shuffle, repeat, and visualizer
- Local files should work alongside Jellyfin streaming (hybrid mode)
- No server required — app should be fully functional offline with local files

### Implementation notes

- mpv_audio_kit already supports `file://` and `content://` URIs natively
- Metadata extraction: use mpv's `metadata` stream or a dedicated tag reader package
- Cover art: mpv's `stream.coverArt` already extracts embedded art from local files
- Library UI: could reuse existing grid/list views with a "Local" tab or a separate "Device" source
- Storage access: `file_picker` for folder selection, or `SAF` (Storage Access Framework) for persistent access
- Database: need local SQLite (via `drift` or `sqflite`) to cache scanned metadata so the library doesn't re-scan on every launch
- Consider: should local and Jellyfin libraries be merged into one view, or kept separate?

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
