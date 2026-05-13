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
