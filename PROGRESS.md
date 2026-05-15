# Navidrome Support — Progress

## Architecture
- [x] Create abstract `MusicBackend` interface (`lib/core/backend/music_backend.dart`)
- [x] Add `ServerType` enum (jellyfin, subsonic) to `lib/core/jellyfin/models/server.dart`
- [x] Add `serverType` field to `JellyfinAuth`
- [x] Update `AuthStorage` to persist/restore `serverType`
- [x] Make `JellyfinClient` implement `MusicBackend` (partial — needs all `@override` annotations)

## JellyfinClient
- [ ] Add all `@override` annotations to `JellyfinClient` methods matching `MusicBackend`

## SubsonicClient
- [ ] Create `SubsonicClient` implementing `MusicBackend` (`lib/core/subsonic/client.dart`)
- [ ] Subsonic token auth (`md5(password + salt)`)
- [ ] Ping / server check
- [ ] Albums (getAlbumList2, getAlbum)
- [ ] Artists (getArtists, getArtist)
- [ ] Tracks (search3 for all tracks)
- [ ] Playlists (CRUD)
- [ ] Search (search3)
- [ ] Favorites (star/unstar, getStarred2)
- [ ] Stream URL construction
- [ ] Cover art URL construction
- [ ] Lyrics (getLyricsBySongId)
- [ ] Similar songs (getSimilarSongs2)
- [ ] Scrobble / playback reporting
- [ ] Genres (getGenres)

## Providers
- [ ] Replace `jellyfinClientProvider` with `musicBackendProvider`
- [ ] Update all library/search/lyrics providers to use `MusicBackend`

## Onboarding
- [ ] Auto-detect server type (Jellyfin vs Navidrome) at URL entry
- [ ] Support Subsonic login flow in sign-in screen

## Playback
- [ ] Update `PlayActions` to use `MusicBackend`
- [ ] Update `JellyfinPlaybackReporter` to use `MusicBackend`

## Quality
- [ ] Run `flutter analyze --no-fatal-infos` — 0 errors, 0 warnings
- [ ] Run `flutter test` — all pass
- [ ] Push final changes to `navidrome` branch
