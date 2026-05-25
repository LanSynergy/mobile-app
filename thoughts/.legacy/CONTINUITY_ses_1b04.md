---
session: ses_1b04
updated: 2026-05-22T12:50:44.795Z
---

# Session Summary

## Goal
Document naming conventions across this Flutter/Dart codebase (Aetherfin music player) — file names, class names, function names, variable names, constants, and enums — based on examination of 25+ files.

## Constraints & Preferences
- Must report patterns found for each category
- Must reference exact file paths, identifiers, and examples
- Prefer specific examples over general rules

## Progress
### Done
- [x] Explored project root and discovered structure: `lib/app/`, `lib/core/`, `lib/design_tokens/`, `lib/features/`, `lib/state/`, `lib/utils/`, `lib/widgets/`, `test/`
- [x] Read 25+ files covering all naming categories and layers

## File Naming Conventions

| Category | Pattern | Examples |
|---|---|---|
| Feature screens | `<feature>_screen.dart` | `settings_screen.dart`, `queue_screen.dart`, `home_screen.dart`, `search_screen.dart` |
| Providers | `*_providers.dart` | `player_providers.dart`, `auth_providers.dart`, `library_providers.dart`, `app_mode_providers.dart` |
| Widgets | `*.dart` (descriptive snake_case) | `track_row.dart`, `bottom_nav.dart`, `press_scale.dart`, `artwork.dart`, `mini_player.dart` |
| Models | `*.dart` (descriptive) | `items.dart` (AfAlbum, AfTrack), `server.dart`, `quality.dart`, `library.dart` |
| Design tokens | plural `*.dart` | `colors.dart`, `motion.dart`, `spacing.dart`, `radii.dart`, `typography.dart` |
| Utilities | `*.dart` (descriptive) | `log.dart`, `url.dart`, `time_format.dart`, `display_error.dart` |
| Tests | `*_test.dart` (matches tested file) | `design_tokens_test.dart`, `auto_bypass_flat_test.dart`, `queue_manager_test.dart` |
| Core services | `*.dart` | `player_service.dart`, `queue_manager.dart`, `artwork_manager.dart` |
| Feature sub-widgets | within feature dir, descriptive | `settings_dialogs.dart`, `settings_sections.dart`, `settings_widgets.dart` |

## Class Naming Conventions

| Prefix / Suffix | Examples | Used For |
|---|---|---|
| `Af` prefix | `AfAlbum`, `AfTrack`, `AfArtist`, `AfPlaylist`, `AfGenre`, `AfTrackDetails` | Domain data models in `lib/core/jellyfin/models/items.dart` |
| `Af` prefix | `AfColors`, `AfCurves`, `AfDurations`, `AfSpacing`, `AfRadii` | Design token classes in `lib/design_tokens/` (all abstract final) |
| `Af` prefix | `AfPlayerService`, `AfPositionTracker`, `AfArtworkManager`, `AfAudioDeviceManager`, `AfQueueManager`, `AfAsyncLock` | Audio service/manager classes |
| `Af` prefix | `AfBottomNav`, `AfBottomNavItem` | Public widget classes with `Af` branding |
| No prefix, PascalCase | `PressScale`, `TrackRow`, `Artwork`, `CircularArtwork`, `FavoriteHeartButton` | Generic reusable widgets in `lib/widgets/` |
| `Screen` suffix | `SettingsScreen`, `HomeScreen`, `SearchScreen`, `QueueScreen`, `AlbumScreen`, `ArtistScreen`, `NowPlayingScreen` | Feature screen widgets (usually extend `ConsumerWidget` or `ConsumerStatefulWidget`) |
| `Store` suffix | `AppModeStore`, `PlayerSettingsStore` | Persistence stores |
| Descriptive PascalCase | `JellyfinServer`, `JellyfinAuth`, `ServerType` (enum), `JellyfinClient`, `SubsonicClient`, `LibraryView`, `SmartRule`, `SmartPlaylist` | Jellyfin / local models |
| Abstract `MusicBackend` | `abstract class MusicBackend` | Backend abstraction (implemented by JellyfinClient, SubsonicClient, LocalBackend) |
| `Provider` suffix (Riverpod) | `currentTrackProvider`, `playerServiceProvider`, `fftSpectrumProvider` | Riverpod provider declarations |
| `_` prefix (private) | `_AfBottomNavState`, `_PressScaleState`, `_NowPlayingPage`, `_RootErrorWidget` | Private State classes and widgets |
| `App` suffix | `AetherfinApp` | Root app widget (`lib/app/app.dart`) |
| `Manager` suffix | `AfArtworkManager`, `AfQueueManager`, `AfAudioDeviceManager` | Subsystem managers |
| `Service` suffix | `AfPlayerService`, `PlayerSettingsStore`, `OfflineCacheService` | Service-layer classes |

## Function Naming Conventions

| Pattern | Examples | Context |
|---|---|---|
| Top-level camelCase | `afLog()`, `autoBypassFlat()`, `stripTrailingSlash()`, `redactSensitiveQueryParams()`, `displayError()`, `formatTrackDuration()`, `formatRemaining()`, `formatHourCount()`, `formatCompactCount()`, `buildNocturneTheme()`, `setRouterAuthState()`, `notifyAuthChanged()`, `wirePlayerService()` | Utility functions and module-level helpers |
| Private `_` prefix | `_boot()`, `_loadAetherfinVersion()`, `_loadOrCreateFallbackDeviceId()`, `_render()`, `_openConnection()`, `_startPositionPolling()` | Internal helpers, not exported |
| Instance methods (camelCase) | `playQueue()`, `skipToNext()`, `setAbLoopA()`, `getRawPosition()`, `dispose()`, `copyWith()`, `toJson()`, `fromJson()` | Object methods across all classes |
| Getters | `get currentTrack`, `get isPlaying`, `get shouldAdvancePosition`, `get audioDevices`, `get isShuffleEnabled`, `get currentQueue`, `get currentIndex`, `get metadataLine`, `get subtitle`, `get chipLabel`, `get summary`, `get hasAudio` | Computed property accessors |
| Stream getters | `get positionStream`, `get playingStream`, `get queueStream`, `get shuffleModeStream`, `get currentTrackStream` | Event stream exposure in managers |
| Named factory constructors | `factory SmartPlaylist.fromJson(...)`, `factory SmartRule.fromJson(...)` | Deserialization |
| `build()` override | `Widget build(BuildContext context, WidgetRef ref)` (ConsumerWidget) | Widget build method |
| Riverpod callbacks | `ref.read(provider.notifier).state = value`, `ref.watch(provider)` | Provider reading patterns |

## Variable Naming Conventions

| Pattern | Examples | Context |
|---|---|---|
| camelCase (local) | `deviceId`, `initialAuth`, `persistedMode`, `aetherfinVersion`, `raw`, `clamped` | Local variables within functions |
| `_` prefix + camelCase (private fields) | `_player`, `_disposed`, `_userPaused`, `_isLoadingQueue`, `_shuffleGen`, `_queueLoadGen`, `_playlistHandlerGen`, `_queueLock`, `_trackQueue`, `_currentIndex`, `_originalQueue`, `_urlToTrack`, `_coverCounter`, `_coverPath`, `_networkCoverPath`, `_authHeaders`, `_subs`, `_lastPlaybackStatePush`, `_lastPushedPlaying`, `_navBg`, `_fallbackDeviceIdKey`, `_sensitiveQueryKeys`, `_kAppMode`, `_httpClient` | Private instance fields and module-level privates |
| camelCase (public fields) | `baseUrl`, `name`, `version`, `id`, `isLocal`, `isReachable`, `userId`, `userName`, `accessToken`, `sourceCodec`, `bitrateKbps`, `bitDepth`, `sampleRateKhz`, `isTranscoded`, `transcodeCodec`, `onTrackChanged`, `onTrackCompleted`, `onArtworkChanged` | Public instance fields |
| `is` / `has` prefix (booleans) | `isFavorite`, `isDownloaded`, `isLocal`, `isReachable`, `isPublic`, `isTranscoded`, `isActive`, `isDegraded`, `hasAudio`, `hasActivePlayback`, `hasTrack` | Boolean getters and fields |
| `on` prefix (callbacks) | `onTap`, `onLongPress`, `onTrackChanged`, `onTrackCompleted`, `onArtworkChanged`, `onSelect` | Void callbacks / event handlers |
| `super.key` (widget key) | `const SettingsScreen({super.key})` | All widget constructors pass key |

## Constants

| Pattern | Examples | Location |
|---|---|---|
| Module-level `const` + lowerCamelCase | `const _fallbackDeviceIdKey`, `const _navBg`, `const _sensitiveQueryKeys` | Private to file |
| Static class consts + lowerCamelCase | `AfDurations.instant`, `AfDurations.quick`, `AfDurations.standard`, `AfColors.indigo50`, `AfColors.indigo600`, `AfSpacing.s4`, `AfSpacing.s16`, `AfSpacing.gutter`, `AfRadii.borderSm`, `AfRadii.rXs` | Design token abstract final classes |
| Private static consts | `static const _channel = MethodChannel(...)`, `static const _maxNudgeRetries = 3`, `static const _kAppMode = 'af.app_mode'` | Inside classes |
| Duration constants | `const Duration(milliseconds: 80)`, `const Duration(milliseconds: 240)` | `AfDurations` tiers |
| Tolerance constants | `static const _epsSec = Duration(milliseconds: 10)` | `position_tracker.dart` |

## Enum Naming Conventions

| Enum Name | Values | File |
|---|---|---|
| `AppMode` | `AppMode.server`, `AppMode.local` | `lib/state/app_mode_providers.dart` |
| `TrackRowDensity` | `TrackRowDensity.compact`, `TrackRowDensity.comfortable`, `TrackRowDensity.generous` | `lib/widgets/track_row.dart` |
| `ServerType` | (inferred — values like `.jellyfin`, `.subsonic`, `.local`) | `lib/core/jellyfin/models/server.dart` |
| `Loop` | `Loop.off`, `Loop.playlist`, `Loop.file` | (from mpv_audio_kit package, not app-defined) |
| `SmartPlaylistCombinator` | `all`, `any` | `lib/core/smart_playlist/smart_playlist_model.dart` |

**Enum naming rules observed:**
- Enum type name: PascalCase (`AppMode`, `TrackRowDensity`, `ServerType`)
- Enum values: lowerCamelCase (`.server`, `.local`, `.compact`, `.comfortable`, `.generous`)
- No SCREAMING_SNAKE_CASE values anywhere
- No prefix on values (they're already namespaced by the enum type)

## Additional Patterns Observed
- **Record type syntax**: `({int completed, int total})?` for `localScanProgressProvider`
- **Package name**: `aetherfin` (used in imports like `package:aetherfin/design_tokens/tokens.dart`)
- **Riverpod pattern**: All providers exported through barrel file `lib/state/providers.dart`
- **Generated code**: `app_database.g.dart` (Drift code generation)
- **Drift table classes**: `Tracks extends Table`, `Folders extends Table`, `SmartPlaylists extends Table` — plural table names, `@DataClassName('TrackEntity')` annotation for generated data class
- **Library declarations**: `library;` in `tokens.dart` — used for export surface
- **Doc comments**: Triple-slash `///` everywhere. Doc format: first line is summary, blank, then details. See `afLog`, `displayError`, `AfPlayerService`, `MusicBackend`, `AfColors`, `AfCurves`, `AfDurations`, etc.

### Blocked
- (none)

## Key Decisions
- **Af prefix for app-domain classes**: Distinguishes Aetherfin types from Flutter/library types. Applied to domain models (`AfAlbum`, `AfTrack`), design tokens (`AfColors`, `AfSpacing`), and audio services (`AfPlayerService`, `AfQueueManager`)
- **lowerCamelCase for enum values**: Follows Dart style guide for non-Java enums. No legacy SCREAMING_CASE
- **All design token classes are `abstract final`**: Prevents instantiation and inheritance — pure namespace for constants
- **Private class members use `_` prefix**: Dart idiomatic privacy. Applied to fields, methods, State subclasses
- **Snake_case for file names**: Dart convention. Feature files grouped by feature, test files mirror source with `_test` suffix
- **`Screen` suffix for page-level widgets**: Distinguishes screens from reusable widgets in router imports and feature folders

## Next Steps
1. No pending work — this was a discovery/reporting session. Ready to apply these conventions in new code.

## Critical Context
- The project is a Flutter 3.41+ app using Riverpod for state management and go_router for navigation
- All domain models live under `lib/core/jellyfin/models/items.dart` with `Af*` prefix
- Design tokens are centralized in `lib/design_tokens/` — single import via `package:aetherfin/design_tokens/tokens.dart`
- Audio subsystem has a layered architecture: `AfPlayerService` → `AfQueueManager` + `AfPositionTracker` + `AfArtworkManager` + `AfAudioDeviceManager`
- All tests are in `test/` root (not `test/unit/` etc.)
- Generated code for Drift database is at `lib/core/local/app_database.g.dart`
- Barrel re-export in `lib/state/providers.dart` re-exports all provider files

## File Operations
### Read
- `/home/azrim/Projects/Aetherfin/mobile-app`
- `/home/azrim/Projects/Aetherfin/mobile-app/lib/app/app.dart`
- `/home/azrim/Projects/Aetherfin/mobile-app/lib/app/router.dart`
- `/home/azrim/Projects/Aetherfin/mobile-app/lib/app/theme.dart`
- `/home/azrim/Projects/Aetherfin/mobile-app/lib/core/audio/artwork_manager.dart`
- `/home/azrim/Projects/Aetherfin/mobile-app/lib/core/audio/player_service.dart`
- `/home/azrim/Projects/Aetherfin/mobile-app/lib/core/audio/queue_manager.dart`
- `/home/azrim/Projects/Aetherfin/mobile-app/lib/core/backend/music_backend.dart`
- `/home/azrim/Projects/Aetherfin/mobile-app/lib/core/jellyfin/models/items.dart`
- `/home/azrim/Projects/Aetherfin/mobile-app/lib/core/jellyfin/models/library.dart`
- `/home/azrim/Projects/Aetherfin/mobile-app/lib/core/jellyfin/models/quality.dart`
- `/home/azrim/Projects/Aetherfin/mobile-app/lib/core/jellyfin/models/server.dart`
- `/home/azrim/Projects/Aetherfin/mobile-app/lib/core/local/app_database.dart`
- `/home/azrim/Projects/Aetherfin/mobile-app/lib/core/local/app_mode_store.dart`
- `/home/azrim/Projects/Aetherfin/mobile-app/lib/core/smart_playlist/smart_playlist_model.dart`
- `/home/azrim/Projects/Aetherfin/mobile-app/lib/design_tokens/colors.dart`
- `/home/azrim/Projects/Aetherfin/mobile-app/lib/design_tokens/motion.dart`
- `/home/azrim/Projects/Aetherfin/mobile-app/lib/design_tokens/radii.dart`
- `/home/azrim/Projects/Aetherfin/mobile-app/lib/design_tokens/spacing.dart`
- `/home/azrim/Projects/Aetherfin/mobile-app/lib/design_tokens/tokens.dart`
- `/home/azrim/Projects/Aetherfin/mobile-app/lib/features/settings/settings_screen.dart`
- `/home/azrim/Projects/Aetherfin/mobile-app/lib/main.dart`
- `/home/azrim/Projects/Aetherfin/mobile-app/lib/state/app_mode_providers.dart`
- `/home/azrim/Projects/Aetherfin/mobile-app/lib/state/player_providers.dart`
- `/home/azrim/Projects/Aetherfin/mobile-app/lib/state/providers.dart`
- `/home/azrim/Projects/Aetherfin/mobile-app/lib/utils/display_error.dart`
- `/home/azrim/Projects/Aetherfin/mobile-app/lib/utils/log.dart`
- `/home/azrim/Projects/Aetherfin/mobile-app/lib/utils/time_format.dart`
- `/home/azrim/Projects/Aetherfin/mobile-app/lib/utils/url.dart`
- `/home/azrim/Projects/Aetherfin/mobile-app/lib/widgets/artwork.dart`
- `/home/azrim/Projects/Aetherfin/mobile-app/lib/widgets/bottom_nav.dart`
- `/home/azrim/Projects/Aetherfin/mobile-app/lib/widgets/press_scale.dart`
- `/home/azrim/Projects/Aetherfin/mobile-app/lib/widgets/track_row.dart`
- `/home/azrim/Projects/Aetherfin/mobile-app/test/auto_bypass_flat_test.dart`
- `/home/azrim/Projects/Aetherfin/mobile-app/test/design_tokens_test.dart`

### Modified
- (none)
