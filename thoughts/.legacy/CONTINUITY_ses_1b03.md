---
session: ses_1b03
updated: 2026-05-22T13:09:33.633Z
---

# Session Summary

## Goal
Map all library dependencies, their usage patterns, implementation files, API surfaces, and architectural relationships in the Aetherfin Flutter project at `/home/azrim/Projects/Aetherfin/mobile-app`.

## Constraints & Preferences
- Output complete YAML dependency graph covering external deps, internal modules, import patterns, dependency tiers, and test matrix
- Preserve exact file paths, class names, function signatures, and enums
- Scan 20+ source files to validate usage patterns against pubspec declarations
- Verify import_style conventions (barrel files, package imports vs relative)
- Check for stale dependencies, forbidden packages, and inconsistencies

## Progress
### Done
- [x] Read `pubspec.yaml` — 20 runtime deps, 6 dev deps, versions locked
- [x] Scanned 27 source files for import statements and usage patterns (glob matched 49+ Dart files)
- [x] Read all 6 key source files in full: `main.dart`, `player_service.dart` (1241 lines), `app_database.dart`, `jellyfin/client.dart`, `subsonic/client.dart`, `music_backend.dart`
- [x] Read all remaining managers and utilities: `router.dart`, `auth_storage.dart`, `spectral_extractor.dart`, `discovery.dart`, `offline_cache_service.dart`, `local_db.dart`, `log.dart`, `url.dart`, `track_row.dart`, `home_screen.dart`
- [x] Read 2 test files: `design_tokens_test.dart`, `auto_bypass_flat_test.dart`
- [x] Read analysis_options.yaml (7 lint rules, strict-casts + strict-raw-types)
- [x] Identified 3 barrel files: `state/providers.dart` (13 exports), `design_tokens/tokens.dart` (5 exports), `lib/utils/log.dart` (library directive)
- [x] Identified 3 MusicBackend implementations: JellyfinClient, SubsonicClient, LocalBackend
- [x] Enumerated mpv_audio_kit full API surface: Player constructor, 8 openAll/add/call categories, 33 stream getters, set* mutators, Loop enum variants
- [x] Cataloged 20 test files: 1 design tokens (exact value enforcement), 10 local DB, 2 backend, 4 audio, 3 misc
- [x] Detected 6 one-import-only deps: crypto, multicast_dns, async, palette_generator_master, uuid, package_info_plus, flutter_secure_storage
- [x] Produced full YAML dependency graph output with 7 sections (external_dependencies, internal_modules, import_patterns, dependency_tiers, dependency_graph, test_matrix, notes)

### In Progress
- (none — all reading and synthesis complete)

### Blocked
- (none)

## Key Decisions
- **Barrel import convention**: `state/providers.dart` and `design_tokens/tokens.dart` serve as single import surfaces. No file imports individual provider or token sources directly.
- **Dio wrapper pattern**: Both Jellyfin and Subsonic clients wrap Dio with cache interceptors (MemCacheStore, 20MB) and debug log interceptors. No raw `dart:io` HttpClient or `http` package used anywhere.
- **Three-backend architecture**: MusicBackend abstract interface with identical method signatures. Provider layer uses `Provider<MusicBackend>` — never branches on client type. JellyfinClient and SubsonicClient both reuse shared Jellyfin model types (AfTrack, AfAlbum, AfServer, etc.).
- **mpv_audio_kit isolation**: Only `player_service.dart` directly imports and uses the Player class. `player_providers.dart` imports only for type references (Loop, FftFrame, MpvPlayerError). All other code accesses audio through AfPlayerService abstraction.
- **Drift codegen with hand-written repos**: `app_database.dart` defines 7 tables via drift DSL, `app_database.g.dart` is generated. Domain repos (TrackRepository, AlbumRepository, PlaylistRepository) are hand-written facade classes.
- **No json_serializable**: All model classes are hand-written Dart classes. Jellyfin response_parser.dart does manual JSON parsing; Subsonic client has inline `_parse*` methods.
- **flutter_secure_storage single-file isolation**: AuthStorage class in `auth_storage.dart` is the only file importing `flutter_secure_storage`. Password bytes zeroed after use in Subsonic client via `List<int> _passwordBytes`.

## Next Steps
1. Continue with feature implementation or bug fixing using the dependency map above as reference for which files to import and which patterns to follow
2. If adding new screens: follow `router.dart` GoRoute pattern + `ConsumerStatefulWidget` pattern from `home_screen.dart`
3. If adding new DB queries: follow `local_db_*.dart` repository pattern with drift select/delete DSL
4. If adding new API calls: extend `MusicBackend` interface, implement in both `jellyfin/client.dart` and `subsonic/client.dart`, add provider in appropriate `state/*_providers.dart`
5. If adding new audio features: add methods to `AfPlayerService` (which wraps mpv_audio_kit Player) and expose via Riverpod stream providers in `player_providers.dart`

## Critical Context
- **mpv_audio_kit Loop enum values**: `Loop.off` / `Loop.playlist` / `Loop.file` (not `LoopMode.off/all/one`)
- **Drift schema version**: current V3, migrations in `app_database.dart` MigrationStrategy
- **Device ID**: Generated once by `AuthStorage.loadOrCreateDeviceId()` (16 random bytes, base64url, strip padding), persisted to flutter_secure_storage. Fallback persisted to `_fallbackDeviceIdKey` in plain shared_preferences.
- **MusicBackend abstract methods**: 35 methods covering recentlyAddedAlbums, recentlyPlayed, resumeItems, artists, playlists, allAlbums, allTracks, genres, favoriteAlbums, favoriteTracks, album(id), artist(id), trackDetails, artistAlbums, albumTracks, searchAlbums, searchArtists, searchTracks, searchPlaylists, trackStreamUrl, trackCoverUrl, artistImageUrl, albumCoverUrl, playlistCoverUrl, starTrack, unstarTrack, setRating, getPlaylist, createPlaylist, addToPlaylist, removeFromPlaylist, deletePlaylist, scrobble, authHeaders, close
- **Test pattern**: 20 unit tests (0 integration). Local DB tests use `AppDatabase.forTesting(NativeDatabase.memory())`. No mock packages.
