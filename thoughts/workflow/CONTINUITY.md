# Continuity Ledger

## 2026-05-31 — Optimization audit items: schema v11, column projection, TTL cache, batched sync
*Goal:* Implement 5 optimization items from TODO_optimization-auditor.md: OA-DEEP-1.8 (played_at index), OA-DEEP-1.3 (allTracks limit 5000→500), OA-DEEP-1.4 (column projection via rawRowToTrack), OA-DEEP-1.7 (recently-played TTL cache), OA-QUICK-1.10 (batched Last.fm sync).
*Commits:* 6 commits (see git log)
*Key decisions:*
- Schema v10→v11 for `idx_playback_history_played_at` index
- `rawRowToTrack` helper on TrackRepository for raw SQL column projection (skips file_path, file_size, last_modified)
- 5s TTL cache on `_getRecentlyPlayedIds` in SmartQueueManager, invalidated on recordPlayback
- Last.fm sync: batched Future.wait in groups of 5, favorites remain sequential for rate limits

## 2026-05-31 — Fix local mode blank screen after scan + trackFavoriteOverrides worker
*Goal:* Fix "stuck on scanning then blank screen" in local mode. Root cause: `_startScan()` set `localOnboardingCompletedProvider = true` AND called `context.go('/home')` — provider change triggered `notifyAuthChanged()` → redirect returned `/home`, then explicit `go()` raced on stale context. Fix: remove `context.go('/home')`, let redirect handle navigation. Also added `trackFavoriteOverridesProvider` (map-based) so heart buttons can watch per-track overrides without rebuilding on every toggle.
*Commits:* 17d3013
*Key decisions:*
- Provider state change → `onboardingSub` → `notifyAuthChanged()` → redirect returns `/home` — single navigation path
- No explicit `go()` after provider write — prevents double navigation blank screen

## 2026-05-31 — Fix ref.listenManual + artUri priority; all 419 tests pass
*Goal:* Fix pre-existing test failures: audio_visual_scrubber used `ref.listen()` outside build context (→ `ref.listenManual`), artwork_manager artUri had wrong priority (memory cache before embedded cover). Also added `trackFavoriteOverridesProvider` (map-based) to close Batch 8 gap.
*Commits:* bd3deab
*Key decisions:*
- `ref.listen()` inside `initState.addPostFrameCallback` fails in test — must use `ref.listenManual()` which doesn't require build context
- `artUri()` priority: embedded cover (_coverPath) first as highest-quality source, then memory cache, then network cache
- `trackFavoriteOverridesProvider` lives in `favorite_providers.dart`, consumers resolve via `select((map) => map[id])`

## 2026-05-31 — Optimization audit: all 9 batches committed
*Goal:* Execute 9-batch optimization audit covering shared_dio_client retry interceptor, home_screen section extraction, album_screen consumer granularity, artwork_manager cache fix, local_db_tracks + smart_playlist_db query opt, schema v10 indexes, favorite_providers TrackFavoriteOverride, shared FFT provider.
*Commits:* ddff930, 63aea6f, c388b05, 5bb7386, 1f7121b, 7c889e8, 78db855
*Key decisions:*
- `fftFrameProvider` wraps `spectrumStream.asBroadcastStream()` — visualizer + artwork pulse share one mpv subscription
- `bassEnergyProvider` derives sub-bass max from first 7 FFT bands for transient detection
- Both consumers use `ref.listen(fftFrameProvider, ...)` instead of direct stream subscriptions
- Removing `StreamSubscription` fields (now managed by Riverpod ref lifecycle)
- Schema v10 migration uses `m.database.customStatement()` for `CREATE INDEX` (Migrator lacks `createIndex` for non-table-class indexes)

## 2026-05-29 — Add forNtimes (repeat 2) to QS media player cycle
*Goal:* Add 4th repeat state (repeat 2 times) to QS media player repeat cycle, with proper icon and labels.
*Commits:* 2d58952
*Key decisions:*
- `ic_repeat_ntimes.xml`: fill-based loop arrow + "2" path indicator inside arrow
- `onToggleRepeat` cycle: off → playlist → file → forNtimes → off (was missing forNtimes)
- Kotlin label: "ntimes" → "Repeat 2"
- All 384 tests pass, `flutter analyze`: 0 errors
