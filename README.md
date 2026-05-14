# Aetherfin

A native-feeling Android music player backed by your self-hosted
[Jellyfin](https://jellyfin.org) server. Aetherfin is the player —
Jellyfin is the file source.

> Spotify's polish. Apple Music's typography. Soulseek's respect for the
> listener.

[![Flutter](https://img.shields.io/badge/Flutter-3.41.9-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.11.5-0175C2?logo=dart)](https://dart.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![Android](https://img.shields.io/badge/Android-7.0%2B-3DDC84?logo=android)](https://developer.android.com)

---

## What it is

Aetherfin streams music from a Jellyfin server you own and decodes it
fully on-device using **libmpv** via
[mpv_audio_kit](https://pub.dev/packages/mpv_audio_kit). No
Aetherfin-operated servers exist. No telemetry. Jellyfin is treated as a
passive file source plus per-user state store (favorites, play counts,
playlists). Everything else — buffering, decoding, queue management,
lyrics, lock-screen controls, sleep timer, spectral color extraction,
real-time FFT visualizer — runs on your phone.

**Why this matters**

- The Jellyfin server's CPU stays cool. Tracks are served as raw bytes
  via `/Audio/{id}/stream?Static=true`. No HLS transcoding round-trip.
- You can play lossless FLAC / ALAC / OPUS / WAV files without quality loss.
- The FFT spectrum visualizer is driven by the actual audio output
  post-DSP — no `RECORD_AUDIO` permission needed.
- Aetherfin keeps working as long as your Jellyfin server is reachable.
  There is no "Aetherfin cloud" to depend on.

## Screenshots

<p align="center">
  <img src="assets/brand/screencapture/Screenshot_20260514_054739.jpg" width="23%" hspace="4" alt="Now Playing">
  <img src="assets/brand/screencapture/Screenshot_20260514_054801.jpg" width="23%" hspace="4" alt="Queue">
  <img src="assets/brand/screencapture/Screenshot_20260514_054809.jpg" width="23%" hspace="4" alt="Library">
  <img src="assets/brand/screencapture/Screenshot_20260514_054837.jpg" width="23%" hspace="4" alt="Lyrics">
</p>

## Features

- **Library, Albums, Artists, Genres, Playlists** browsing
- **Search** across tracks, albums, artists, playlists (debounced, normalized)
- **Queue** with drag-to-reorder, swipe-to-remove, auto-scroll to current track
- **Long-press context menus** on tracks (Play next, Add to queue, Go to album/artist) and albums (Play album, Go to artist)
- **Now Playing** with:
  - Real-time FFT spectrum visualizer (64 bars, engine-driven rendering at 60 fps, path-batched painter)
  - Artwork pulse driven by sub-bass transient detector (bins 1–6, 250ms cooldown, spring decay)
  - Progress scrubber with haptic feedback and drag-race-free seeking
  - Shuffle (native mpv playlist-shuffle, never changes displayed song), loop (off / track / playlist), playback speed (0.5×–2.0×)
  - Favorite toggle, Instant Mix radio
- **Equalizer & DSP** (accessible from Now Playing → More):
  - Bass shelf (-12 to +12 dB)
  - Treble shelf (-12 to +12 dB)
  - Loudness normalization (EBU R128, -16 LUFS)
  - Dynamic compressor (threshold 0.1, ratio 4:1)
  - ReplayGain (off / track / album)
- **Synced lyrics** (LRC parsed on-device, auto-scrolling, displayed on lock-screen)
- **Lock-screen / notification** media controls (prev, play/pause, next)
- **Sleep timer** (presets + end-of-track mode)
- **Audio output routing** (mpv audio device picker)
- **Audio hardware settings** — sample rate, bit depth, exclusive mode, audio buffer
- **Network & cache settings** — cache duration, buffer size, keep-audio-active toggle
- **Save to playlist** / create playlist from Now Playing
- **Playlist management** — reorder, remove, rename, delete
- **mDNS discovery** of Jellyfin servers on the local network
- **Spectral-derived UI accents** — palette sampled from current cover art
- **Gapless playback** — libmpv pre-fetches the next track in the background
- **A-B loop** — repeat a section of a track (API ready, UI pending)
- **Genre detail screens** — tap any genre to browse its albums
- **Offline-friendly metadata cache** (cover art via
  [`cached_network_image`](https://pub.dev/packages/cached_network_image),
  Dio HTTP cache for catalog requests)

## Requirements

- **Android 7.0 (API 24)** or newer.
- A reachable [**Jellyfin 10.8+**](https://jellyfin.org/downloads/server)
  server with at least one music library.
- Network reachability between phone and server (LAN, VPN, or
  publicly-exposed HTTPS — all work).

## Quick start

### Install the APK

1. Download the most recent `app-release.apk` from
   [Releases](https://github.com/Aetherfin/mobile-app/releases) or the
   [latest CI build](https://github.com/Aetherfin/mobile-app/actions/workflows/build-apk.yml).
2. Enable "Install from unknown sources" for your file manager / browser.
3. Open the APK, install, launch.

### First-run onboarding

1. **Discover or enter your server URL** (e.g. `http://192.168.1.10:8096`
   or `https://music.example.com`). mDNS will list nearby Jellyfin
   instances; otherwise type the URL manually.
2. **Sign in** with your Jellyfin username and password.
3. **You're in.** Pick a track. It plays.

## Building from source

```bash
# Prereqs: Flutter 3.41.9 stable, Dart 3.11.5, Java 17, Android SDK
flutter --version    # must say 3.41.9
flutter pub get      # also downloads libmpv.so for Android (~20 MB per ABI)

# Run on a connected device / emulator
flutter run --debug

# Release APK
flutter build apk --release
# → build/app/outputs/flutter-apk/app-release.apk

# Per-ABI APKs (smaller download per device)
flutter build apk --release --split-per-abi
```

### Pre-push checklist

```bash
flutter analyze --no-fatal-infos   # 0 errors, 0 warnings
flutter test                       # all pass
```

CI runs both on every PR. See
[`.github/workflows/build-apk.yml`](.github/workflows/build-apk.yml).

## Architecture (the 30-second version)

```
   ┌────────────────────────────────┐         ┌──────────────────────────────┐
   │   Aetherfin (Android)          │         │   Your Jellyfin server       │
   │                                │         │                              │
   │  libmpv (mpv_audio_kit) ◄──────┼─bytes───┤  /Audio/{id}/stream          │
   │  Queue / shuffle / loop        │         │   ?Static=true&api_key=…     │
   │  Gapless prefetch              │◄─meta───┤  /Users/{id}/Items …         │
   │  FFT spectrum (post-DSP)       │         │  /Users/{id}/FavoriteItems   │
   │  Lyrics parse + sync           │◄─image──┤  /Items/{id}/Images/Primary  │
   │  Lock-screen (audio_service)   │         │                              │
   │  Cover-art file cache          │         │                              │
   │                                │         │                              │
   │  Optimistic favorite UI ───────┼─POST────┤  (server is source of truth) │
   │  Telemetry (display only) ─────┼─POST────┤  /Sessions/Playing[/Progress]│
   └────────────────────────────────┘         └──────────────────────────────┘
```

### Visualizer architecture

The FFT visualizer uses an **engine-driven rendering** model:

1. **Engine-side DSP** — mpv_audio_kit's C++ pipeline handles all smoothing physics (attack 0.8, release 0.1). Emits 64 log-spaced bands at ~120 fps, already dB-normalized to [0, 1].
2. **Client-side rendering** — `ingest()` applies a power-8 curve for visual compression and marks data dirty. A vsync-aligned ticker calls `flush()` at 60 fps, guaranteeing frame-aligned repaints regardless of stream event timing.
3. **Path-batched painter** — 4 `Path` objects (top/reflection × played/unplayed) drawn with 4 `drawPath` calls instead of ~128 individual `drawRRect` calls. Eliminates Skia pipeline thrashing.

The artwork pulse uses a **transient detector** on bins 1–6 (kick/sub-bass region, 22–45 Hz). Running baseline EMA + 1.5× threshold + 250ms cooldown prevents double-kick chatter. Spring decay (0.85× per frame) via `ValueNotifier<double>` + `Transform.scale` — no setState, no parent rebuild.

Full architectural rules live in [`CLAUDE.md`](./CLAUDE.md).

## Privacy

Aetherfin does not operate any servers. The app talks only to the
Jellyfin server you configure. Credentials live in Android's secure
storage on the device. No analytics, no crash-reporting SDK, no ads,
no third-party trackers. Full statement in [PRIVACY.md](./PRIVACY.md).

## License

Aetherfin is open-source under the **MIT License**. See
[LICENSE](./LICENSE) for the full text.

Copyright © 2025 Azrim &lt;mirzaspc@gmail.com&gt;.

Jellyfin is © its respective authors and is licensed separately. This
project is not affiliated with the Jellyfin project.

## Contributing

PRs welcome. Read [CLAUDE.md](./CLAUDE.md) first — it covers the auth
header format, the data-source split, the design tokens, and the
non-negotiable rules.

## Acknowledgements

- [Jellyfin](https://jellyfin.org) — the free software media system this
  app is built around.
- [Finamp](https://github.com/jmshrv/finamp) — prior-art Jellyfin music
  client whose auth-header format we follow.
- [mpv_audio_kit](https://pub.dev/packages/mpv_audio_kit) — the
  libmpv-backed audio engine powering playback, gapless transitions,
  and the real-time FFT spectrum.
- [audio_service](https://pub.dev/packages/audio_service) — lock-screen
  and notification media controls.
