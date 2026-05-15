# Navidrome Support — Progress

## Architecture
- [x] Create abstract `MusicBackend` interface (`lib/core/backend/music_backend.dart`)
- [x] Add `ServerType` enum (jellyfin, subsonic) to `lib/core/jellyfin/models/server.dart`
- [x] Add `serverType` field to `JellyfinAuth`
- [x] Update `AuthStorage` to persist/restore `serverType`
- [x] Make `JellyfinClient` implement `MusicBackend` with all `@override` annotations

## SubsonicClient
- [x] Create `SubsonicClient` implementing `MusicBackend` (`lib/core/subsonic/client.dart`)
- [x] Subsonic token auth (`md5(password + salt)`)
- [x] Ping / server check
- [x] Albums (getAlbumList2, getAlbum)
- [x] Artists (getArtists, getArtist)
- [x] Tracks (search3 for all tracks)
- [x] Playlists (CRUD)
- [x] Search (search3)
- [x] Favorites (star/unstar, getStarred2)
- [x] Stream URL construction
- [x] Cover art URL construction
- [x] Lyrics (getLyricsBySongId)
- [x] Similar songs (getSimilarSongs2)
- [x] Scrobble / playback reporting
- [x] Genres (getGenres)

## Providers
- [x] Add `musicBackendProvider` (creates JellyfinClient or SubsonicClient based on serverType)
- [x] Keep `jellyfinClientProvider` as convenience alias for Jellyfin-specific ops
- [x] Update all library/search/lyrics/favorites/genre providers to use `MusicBackend`
- [x] Update `spectralProvider` auth headers to use `musicBackendProvider`
- [x] Update `favoriteToggleProvider` to use `musicBackendProvider`

## Onboarding
- [x] Auto-detect server type (probe Jellyfin publicInfo, then Subsonic ping)
- [x] Pass `serverType` through router to sign-in screen
- [x] Support Subsonic login flow in sign-in screen (ping to validate creds)
- [x] Hide API token toggle for Navidrome (not applicable)
- [x] Show Navidrome-specific instructions

## Playback
- [x] Update `PlayActions` to use `musicBackendProvider`
- [x] Update `JellyfinPlaybackReporter` to accept `MusicBackend` instead of `JellyfinClient`
- [x] Update `play_actions.dart` stream URL and auth header resolution
- [x] Update track context menu (play next, add to queue) to use `musicBackendProvider`

## UI Screens
- [x] Update `artwork.dart` auth headers to use `musicBackendProvider`
- [x] Update `now_playing_screen.dart` save-to-playlist to use `MusicBackend`
- [x] Update `playlist_screen.dart` (reorder, remove, rename, delete) to use `MusicBackend`
- [x] Update `album_screen.dart` favorite toggle to use `musicBackendProvider`
- [x] Update `library_scope_screen.dart` to use `musicBackendProvider`

## Quality
- [x] Run `flutter analyze --no-fatal-infos` — 0 errors, 0 warnings
- [x] Run `flutter test` — all 24 tests pass
- [x] Push all changes to `navidrome` branch
