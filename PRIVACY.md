# Privacy Policy

**Effective date:** May 11, 2026
**Author / maintainer:** Azrim &lt;mirzaspc@gmail.com&gt;
**Software:** Aetherfin — an open-source Android music player
**Repository:** <https://github.com/Aetherfin/mobile-app>

Short version: **Aetherfin does not collect, transmit, or sell any
personal data.** In server mode, it talks only to the Jellyfin or
Navidrome server you configure. In local mode, it reads files from
your device and never contacts any server. Everything stays on your phone.

The rest of this document explains what data the App handles, where it
lives, and what we (the maintainer) do and do not see.

---

## 1. Who runs Aetherfin

Aetherfin is open-source software maintained by Azrim
(&lt;mirzaspc@gmail.com&gt;). **There is no Aetherfin-operated server, no
account system, and no telemetry pipeline.** The maintainer does not
host, receive, store, or analyze any of your activity.

If you obtain a build of Aetherfin from a source other than the
[official repository](https://github.com/Aetherfin/mobile-app), this
policy describes only the behavior of unmodified upstream builds. Forks
or third-party redistributions may add their own data collection and
are out of scope of this policy.

## 2. What data the App handles

| Data | Where it lives | Who sees it |
|---|---|---|
| **Server URL** (e.g. `http://omahsangar.local:8097` for Jellyfin, `http://192.168.1.10:4533` for Navidrome) | `flutter_secure_storage` on your device | You + your server |
| **Username** | `flutter_secure_storage` on your device | You + your server |
| **Access token** (Jellyfin) or **password** (Navidrome — stored encrypted, used to compute auth tokens/JWTs) | `flutter_secure_storage` on your device | You + your server |
| **User ID** | `flutter_secure_storage` on your device | You + your server |
| **Server type** (Jellyfin or Navidrome/Subsonic) | `flutter_secure_storage` on your device | Only you |
| **Device ID** — random 16-byte value generated on first launch and used as Jellyfin's `DeviceId` for session bookkeeping | `flutter_secure_storage` on your device | Your server |
| **Settings** (audio-quality preference, crossfade, sleep-timer state, sort order, theme overrides, app mode) | `shared_preferences` on your device | Only you |
| **Local music metadata** (title, artist, album, duration — cached from file tags) | `sqflite` database in the App's private directory | Only you |
| **Cover-art image cache** | `cached_network_image` files (server) or extracted art files (local) in the App's private cache directory | Only you |
| **HTTP cache** of catalog requests | Dio cache files in the App's private cache directory | Only you |
| **Lyrics (LRC files)** fetched from your server | In-memory only — not persisted | Only you, while playing |
| **Playback state** (current track, position, queue, queue history) | In-memory + local SQLite DB (QueueHistory table) + lock-screen `MediaSession` | Only you |
| **Last.fm Credentials** (API key, API secret, session key, username) — only if Last.fm connection is set up | `shared_preferences` on your device | You + Last.fm |
| **Diagnostic logs** (`aetherfin:boot`, `aetherfin:http`, `aetherfin:data`, `aetherfin:audio`, `aetherfin:error`) | Standard Android logcat buffer (volatile, capped by the OS) | Only you, when you run `adb logcat` |

**Aetherfin does not send any of the above to the maintainer or any unconfigured third party.** The only network destinations Aetherfin contacts are:
1. The server URL you provide (Jellyfin or Navidrome).
2. The Last.fm API endpoints (`ws.audioscrobbler.com`), **only** if you explicitly choose to connect your Last.fm account in Settings.

## 3. What Aetherfin sends to your server

The App is a client for either the Jellyfin HTTP API or the Subsonic
(Navidrome) API. When you sign in and use the App it sends the same
requests any compatible client would send, including:

### 3a. Jellyfin servers

- **Authentication:** `POST /Users/AuthenticateByName` (your username
  and password) — sent only once per sign-in to obtain an access token.
- **Catalog reads:** `GET /Users/{id}/Items`, `/Users/{id}/Items/Latest`,
  `/Users/{id}/Items/Resume`, `/Items/{id}/Images/Primary`, etc. —
  necessary to render the library, album, artist, and queue screens.
- **Audio streaming:** `GET /Audio/{id}/stream?Static=true` — direct
  byte-for-byte download of the audio file you chose to play.
- **Library state writes:**
  - `POST` / `DELETE /Users/{id}/FavoriteItems/{id}` when you tap the
    heart icon (favorite / un-favorite).
  - `POST /Sessions/Playing`, `POST /Sessions/Playing/Progress`, and
    `POST /Sessions/Playing/Stopped` so your Jellyfin dashboard shows
    what you're currently playing, and so play counts and
    last-played-at timestamps are updated. These can be disabled by
    your Jellyfin server administrator if desired.

### 3b. Navidrome (Subsonic & Native REST APIs) servers

- **Authentication:** 
  - For Subsonic API endpoints: Every request carries query parameters `u` (username), `t` (`md5(password + salt)`), and `s` (random salt). The password itself is never sent over the wire — only the hash.
  - For Navidrome Native REST API features (e.g., play queue synchronization): Authenticates using username and password via `POST /api/auth/login` to obtain a temporary JSON Web Token (JWT) Bearer token, which is sent via the `x-nd-authorization` header for native endpoints.
- **Catalog reads:** `getAlbumList2.view`, `getArtists.view`, `getArtist.view`, `getAlbum.view`, `search3.view`, etc.
- **Audio streaming:** `GET /rest/stream.view?id=…` — direct byte-for-byte download of the audio file.
- **Library state writes:**
  - `star.view` / `unstar.view` when you tap the heart icon.
  - `scrobble.view` to report playback for play counts.
  - Native play queue synchronization (`POST /api/queue`) to sync the active playback queue.

Your server logs and stores this data according to its own
configuration, which is **outside the control of the App and its
maintainer**. Refer to your server administrator for its retention
and access policy.

### 3c. Last.fm API (Optional Third-Party Integration)

If you choose to link a Last.fm account:
- **Authentication:** Authenticates via Last.fm's secure OAuth flow or username/password handshake to retrieve a unique session key. Credentials are saved locally on-device.
- **Playback Scrobbling:** If scrobbling is enabled, the app sends details of the tracks you play (artist, title, album, duration, timestamp) to Last.fm once you have listened to 75% of the song or 4 minutes.
- **Listening Stats & Metadata:** If connected, the app sends search and info text queries (artist, album, track name) to Last.fm to fetch biographies, album wikis, top artist charts, and similar tracks for recommendation radios.

## 4. What Aetherfin does NOT do

- No analytics SDK is integrated (no Firebase Analytics, Mixpanel,
  Amplitude, Sentry, Crashlytics, etc.).
- No advertising SDK is integrated. No ads are served.
- No telemetry, "anonymous usage statistics", "diagnostic data", or
  "improvement program" payloads are sent to the maintainer or any
  third party.
- No background location, contacts, calendar, SMS, or call-log access
  is requested or used.
- The App does not phone home on launch. The only initial network call
  is to the Jellyfin server URL you typed during onboarding.

You can verify this by reading the source code at
<https://github.com/Aetherfin/mobile-app>. The full list of network
endpoints the App touches is enumerated in `lib/core/jellyfin/client.dart`
(Jellyfin) and `lib/core/subsonic/client.dart` (Navidrome).

## 5. Android permissions Aetherfin requests

| Permission | Why |
|---|---|
| `INTERNET` | To talk to your Jellyfin or Navidrome server. |
| `ACCESS_NETWORK_STATE` | So the App can react to your phone being offline. |
| `FOREGROUND_SERVICE` and `FOREGROUND_SERVICE_MEDIA_PLAYBACK` (Android 14+) | So music keeps playing when the App is backgrounded, via Android's standard media session. |
| `WAKE_LOCK` | So the CPU stays awake long enough to decode the next chunk of audio when the screen is off. |

The App does **not** request location, microphone, camera, contacts, or
storage permissions.

## 6. Children's privacy

Aetherfin is not directed to children under 13. The App itself collects
no information from anyone — children or otherwise — and transmits none
to the maintainer. Whether the content on your Jellyfin server is
appropriate for children is a matter for the server's owner.

## 7. Security

Credentials and access tokens are stored using Android's
[`flutter_secure_storage`](https://pub.dev/packages/flutter_secure_storage),
which on modern Android uses the Android Keystore. Encrypted-at-rest
where the OS provides it.

That said, **rooted devices, malware, and physical access by a third
party can defeat any on-device storage**. If you believe your device
has been compromised, sign out from Settings → Profile → Sign out
(which deletes the stored token from secure storage) and revoke the
token in your Jellyfin server's "Devices" dashboard.

## 8. Open-source verifiability

Aetherfin is **open-source under the MIT License**. The entire client
behavior — every HTTP call, every storage write — is visible at:

> <https://github.com/Aetherfin/mobile-app>

If you want to verify the claims in this policy, the relevant files are:

- `lib/core/jellyfin/client.dart` — the only file that issues HTTP
  requests to Jellyfin.
- `lib/core/subsonic/client.dart` — issues HTTP requests to Navidrome (Subsonic API).
- `lib/core/subsonic/navidrome_client.dart` — handles Navidrome native REST API (JWT auth and queue sync).
- `lib/core/jellyfin/auth_storage.dart` — the secure-storage adapter.
- `lib/state/providers.dart` — barrel re-export of 13 domain provider files.
- `lib/main.dart` — bootstrap and initialization.

## 9. Changes to this policy

The maintainer may update this policy from time to time. The current
version is always the file `PRIVACY.md` at the root of the
[Aetherfin repository](https://github.com/Aetherfin/mobile-app). Material
changes — for example, if the App ever started collecting data — will
be called out in the commit message and the release notes for the
build that introduces them.

## 10. Contact

Privacy questions or requests can be sent to **mirzaspc@gmail.com** or
filed as a GitHub Issue on the
[Aetherfin repository](https://github.com/Aetherfin/mobile-app/issues).
