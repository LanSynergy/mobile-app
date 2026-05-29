# Device Compatibility Matrix

Known device-specific behaviors and workarounds for the `mpv_audio_kit` audio engine.

## Fallback patterns

| Pattern | Symptoms | Workaround | Reference |
|---|---|---|---|
| Broken `time-pos` | Position never advances during playback | Elapsed-time extrapolation via `_PositionAnchor` in `AfPositionTracker` | `lib/core/audio/position_tracker.dart` |
| Audio routing race | No audio after rapid play/pause/seek | 3-delay nudge chain with generation counter (`_nudgeGen`) | `_nudgeAudioDevice()` in `player_service.dart` |
| Unhandled setAudioDriver rejection | App crashes on startup on some devices | `.catchError` wrapping around `setAudioDriver()`/`setAudioBuffer()` calls | `AfPlayerService` constructor |
| FFmpeg auth header rejection | Stream URL fails to load | Embed auth as query params (`api_key` for Jellyfin, `u`/`t`/`s` for Subsonic) | `url_builder.dart`, Subsonic `client.dart` |
| mpv playlist-play-index stale state | Wrong track plays after rapid queue mutations | `_queueLock.run()` serialization for all queue mutations | `player_service.dart` |

## Known device reports

| Device | OS | time-pos | Audio routing | Notes |
|---|---|---|---|---|
| Pixel 7 | A14 | Broken | Works | Uses `_PositionAnchor` fallback |
| Samsung S23 | A14 | Works | Needs nudge | 3-delay nudge chain |
| Xiaomi 13T | A13 | Broken | Works | Both fallbacks active |

*Update this table as new device issues surface. File an issue with `adb logcat -s flutter` output.*

## Test checklist

When verifying a fix on a new device, check:
- [ ] Playback starts and position advances
- [ ] Seek to mid-track works
- [ ] Next/previous track transitions work
- [ ] Loop mode (off/file/playlist) works
- [ ] Shuffle toggle works
- [ ] Pause and resume works
- [ ] Rapid play/pause/seek (within 1s) doesn't cause audio drop
- [ ] Bluetooth headphone connect/disconnect works
