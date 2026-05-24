# Aetherfin

Your music. Your server. No compromises.

[![Flutter](https://img.shields.io/badge/Flutter-3.44.0-02569B?logo=flutter)](https://flutter.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![Android](https://img.shields.io/badge/Android-7.0%2B-3DDC84?logo=android)](https://developer.android.com)

Aetherfin is a native Android music player for [Jellyfin](https://jellyfin.org), [Navidrome](https://www.navidrome.org), or your local files. It streams your library, decodes everything on-device with libmpv, and stays out of your way.

No cloud. No telemetry. No transcoding. Just playback.

---

## Screenshots

<p align="center">
  <img src="docs/assets/screencapture/now-playing.jpg" width="23%" hspace="4" alt="Now Playing">
  <img src="docs/assets/screencapture/queue.jpg" width="23%" hspace="4" alt="Queue">
  <img src="docs/assets/screencapture/library.jpg" width="23%" hspace="4" alt="Library">
  <img src="docs/assets/screencapture/lyrics.jpg" width="23%" hspace="4" alt="Lyrics">
</p>

## Demo

https://github.com/user-attachments/assets/ea7d1f7d-a5a7-4c9f-a39f-2236d4e2281f

---

## Why Aetherfin

- **Direct stream** — serves raw bytes from your server. No HLS, no transcoding, no quality loss.
- **Lossless support** — FLAC, ALAC, OPUS, WAV, whatever your library has.
- **Real-time visualizer** — 64-band FFT driven by actual audio output. No microphone permission.
- **Full DSP rack** — 18-band EQ with presets, compressor, echo/delay, phaser, flanger, chorus, pitch shift, and more.
- **Works offline from Aetherfin's perspective** — there's no "Aetherfin cloud." As long as your server is reachable, you're good.

---

## Features

### Playback
- Gapless transitions with background prefetch
- Shuffle, loop (off / track / queue), playback speed (0.5×–2.0×)
- Lock-screen and notification controls (artwork background on Samsung/Android 16)
- Sleep timer with presets and end-of-track mode
- Instant Mix radio (server-generated similar tracks queue)
- A-B loop (tap to set start/end markers, tap again to clear)
- **Local file playback** — play music from device storage via SAF (no server needed)
- Auto-pause on Bluetooth disconnect or headphone unplug
- Instant playback — selected song starts immediately even with large queues

### Audio
- 86-effect DSP rack via mpv's ffmpeg filter pipeline
- 18-band graphic EQ with built-in and custom presets
- Echo/delay, phaser, flanger, chorus, tremolo, vibrato, bit-crusher
- Dynamic compressor, noise gate, de-esser with full parameter control
- Loudness normalization (EBU R128) and ReplayGain (track/album)
- Pitch and tempo shifting (rubberband engine)
- Crossfeed, stereo widening, virtual bass, harmonic exciter
- Master bypass switch

### Library
- Albums, Artists, Songs, Playlists, Genres, Liked songs
- Smart playlists — rule-based auto-updating playlists (works in both server and local mode)
- Search across tracks, albums, artists, playlists
- Long-press context menus (play next, add to queue, go to album/artist)
- Drag-to-reorder queue with swipe-to-remove

### Home
- Swipeable hero album carousel (up to 5 recent albums, dot indicator)
- Recently played tracks, artists, and genres sections

### Now Playing
- FFT spectrum visualizer (64 bars, 60 fps, engine-driven)
- Gradient background that shifts with spectral colors extracted from artwork
- Artwork pulse on kick drums (sub-bass transient detection)
- Synced lyrics (LRC, auto-scrolling)
- Favorite toggle, quality chip, save to playlist
- Translucent queue screen with frosted-glass effect

### Settings
- Audio output: sample rate, bit depth, exclusive mode
- Network: cache duration, buffer size, keep-audio-active
- Server: connection info, switch server, sign out

### UI/UX
- **Lucide icons** throughout — consistent, modern icon set (replaced hugeicons)
- **Skeleton loading** — shimmer placeholder animations on every screen while data loads
- Context menus as dialogs (album 3-dot, track long-press) — cleaner than bottom sheets
- Per-sheet manual drag handles on bottom sheets — avoids floating transparent handles

---

## Install

Grab the latest APK from [Releases](https://github.com/Aetherfin/mobile-app/releases) or the [CI build](https://github.com/Aetherfin/mobile-app/actions/workflows/build-apk.yml).

### Requirements

- Android 7.0+
- **Server mode:** A reachable [Jellyfin 10.8+](https://jellyfin.org/downloads/server) or [Navidrome 0.49+](https://www.navidrome.org/docs/installation/) server
- **Local mode:** Audio files on your device (pick a folder during setup)

### First run

1. Choose mode: **Server** (stream from Jellyfin/Navidrome) or **Local** (play files from device)
2. Server: enter URL + sign in. Local: pick a music folder + scan.
3. Play something

---

## Build from source

```bash
flutter pub get
flutter run --debug

# Release
flutter build apk --release
flutter build apk --release --split-per-abi
```

```bash
# Before pushing
flutter analyze
flutter test
```

---

## How it works

```
┌─────────────────────────────┐       ┌────────────────────────────┐
│  Aetherfin (your phone)     │       │  Your server               │
│                             │       │  (Jellyfin or Navidrome)   │
│  libmpv decoding            │◄─raw──┤  Audio files               │
│  Queue, shuffle, gapless    │       │  Metadata, artwork         │
│  FFT visualizer (post-DSP)  │◄─meta─┤  Favorites, playlists     │
│  Lyrics parsing + sync      │       │  Play counts               │
│  Lock-screen controls       │       │                            │
│  DSP effects chain          │       │                            │
│  Cover art cache            │       │                            │
└─────────────────────────────┘       └────────────────────────────┘
```

The server stores files and metadata. Aetherfin does everything else.

---

## Privacy

No analytics. No ads. No trackers. No Aetherfin servers. The app talks only to the server you configure. Full details in [PRIVACY.md](./PRIVACY.md).

## Community

<p align="center">
  <a href="https://t.me/azrim_ci">
    <img src="https://img.shields.io/badge/Telegram-@azrim__ci-2CA5E0?logo=telegram&style=for-the-badge" alt="Telegram">
  </a>
</p>

## Contributing

PRs welcome. Read [CLAUDE.md](./CLAUDE.md) first — it covers auth, architecture, design tokens, and the rules.

## License

MIT. See [LICENSE](./LICENSE).

## Acknowledgements

- [Jellyfin](https://jellyfin.org) and [Navidrome](https://www.navidrome.org) — the servers
- [mpv_audio_kit](https://pub.dev/packages/mpv_audio_kit) — libmpv audio engine
- Custom Android MediaSession Service — platform-native lock-screen controls via MethodChannel
- [Finamp](https://github.com/jmshrv/finamp) — prior art
