# Aetherfin Code Style

This document captures the coding conventions observed across the Aetherfin
codebase. Follow these when adding or modifying code.

---

## Naming Conventions

### Files
| Category | Pattern | Examples |
|---|---|---|
| Feature screens | `<feature>_screen.dart` | `settings_screen.dart`, `home_screen.dart` |
| Feature sub-widgets | `<feature>_<purpose>.dart` | `settings_widgets.dart`, `settings_dialogs.dart` |
| Providers | `*_providers.dart` | `player_providers.dart`, `auth_providers.dart` |
| Design tokens | plural `*.dart` | `colors.dart`, `motion.dart`, `spacing.dart` |
| Utilities | descriptive `*.dart` | `log.dart`, `time_format.dart`, `url.dart` |
| Tests | `*_test.dart` | `design_tokens_test.dart`, `queue_manager_test.dart` |
| Models | descriptive `*.dart` | `items.dart`, `server.dart`, `quality.dart` |
| Core services | descriptive `*.dart` | `player_service.dart`, `artwork_manager.dart` |

### Classes
| Prefix / Suffix | When | Examples |
|---|---|---|
| `Af` prefix | App-domain classes (models, services, tokens) | `AfAlbum`, `AfTrack`, `AfPlayerService`, `AfColors`, `AfSpacing`, `AfQueueManager` |
| `Screen` suffix | Page-level screen widgets | `SettingsScreen`, `HomeScreen`, `AlbumScreen` |
| `Manager` suffix | Subsystem managers | `AfArtworkManager`, `AfQueueManager` |
| `Service` suffix | Service-layer classes | `AfPlayerService`, `OfflineCacheService` |
| `Store` suffix | Persistence stores | `AppModeStore`, `PlayerSettingsStore` |
| `Provider` suffix | Riverpod provider declarations | `currentTrackProvider`, `playerServiceProvider` |
| `_` prefix | Private State classes / internal helpers | `_AfBottomNavState`, `_NowPlayingPage` |
| No prefix | Generic reusable widgets | `PressScale`, `TrackRow`, `FavoriteHeartButton` |

### Functions & Variables
- **Functions**: `camelCase` — `playQueue()`, `skipToNext()`, `setAbLoopA()`, `autoBypassFlat()`
- **Private functions/fields**: `_camelCase` — `_boot()`, `_startPositionPolling()`, `_player`, `_disposed`
- **Booleans**: `is`/`has` prefixes — `isFavorite`, `isPlaying`, `hasAudio`, `hasActivePlayback`
- **Callbacks**: `on` prefix — `onTrackChanged`, `onArtworkChanged`, `onTap`, `onLongPress`
- **Getters**: `camelCase` — `get currentTrack`, `get isPlaying`, `get metadataLine`
- **Stream getters**: `xxxStream` — `get positionStream`, `get playingStream`, `get queueStream`
- **Constants**: `lowerCamelCase` — `const _fallbackDeviceIdKey`, `static const _channel`

### Enums
- **Type**: PascalCase — `AppMode`, `TrackRowDensity`, `ServerType`, `SmartPlaylistCombinator`
- **Values**: lowerCamelCase — `.server`, `.local`, `.compact`, `.comfortable`, `.generous`
- **No SCREAMING_SNAKE_CASE** for enum values
- **Loop enum** (from mpv_audio_kit): `Loop.off`, `Loop.file`, `Loop.playlist` (NOT `LoopMode.off/all/one`)

---

## File Organization

### Imports
Order and grouping (separated by blank lines):
```dart
import 'dart:async';                          // 1. Dart SDK

import 'package:flutter/material.dart';       // 2. Flutter / third-party
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../../app/theme.dart';                 // 3. App-internal (relative)
import '../models/items.dart';

import 'lib/state/providers.dart';            // 4. App-internal (package)
```

No relative imports above `lib/` — use `package:aetherfin/...` when needed.

### Class structure
1. **Public fields** (instance vars, late finals)
2. **Callbacks** (`void Function(...)? onTrackChanged`)
3. **Private fields** (`_prefixed`)
4. **Constructor** (typically unnamed)
5. **Lifecycle methods** (`init()`, `dispose()`)
6. **Public methods**
7. **Private methods**
8. **Widget `build()`** (last in widget files)

### Dart rules (enforced by analysis_options.yaml)
```yaml
analyzer:
  language:
    strict-casts: true
    strict-raw-types: true
linter:
  rules:
    - avoid_print: true                       # Use afLog() instead
    - unawaited_futures: true
    - cancel_subscriptions: true
    - close_sinks: true
    - use_build_context_synchronously: true
    - prefer_final_locals: true
    - require_trailing_commas: true
```

---

## Code Patterns

### Widgets
- **Screen widgets**: extend `ConsumerWidget` or `ConsumerStatefulWidget` (Riverpod)
- **Reusable widgets**: plain `StatelessWidget` or `StatefulWidget` (accept data via constructor)
- **Constructors**: use `const` + `{super.key}` — `const SettingsScreen({super.key})`
- **High-frequency rebuilds**: isolate to leaf `ConsumerWidget`s (reactive islands pattern)

### State Management (Riverpod)
- **Async data**: `FutureProvider.autoDispose` — `final albumProvider = FutureProvider.autoDispose(...)`
- **Mutable state**: `StateNotifierProvider` — `final playerProvider = StateNotifierProvider<PlayerNotifier, PlayerState>(...)`
- **No `ChangeNotifier`** for Riverpod providers
- **Provider overrides**: inject boot-time values via `ProviderScope` overrides in `main.dart`
- **Barrel re-export**: all providers in `lib/state/providers.dart` via `export '...dart';`

### Audio Service
```dart
// Correct — serialized via _queueLock
await _queueLock.run(() async {
  await _player.playNext(media);
  _trackQueue.insert(_currentIndex + 1, media);
});

// Correct — async/await, not .then()
Future<void> _jumpAndPlay(int index) async {
  await _player.jump(index);
  await _player.play();
}

// Correct — catch unawaited futures in stream listeners
svc.errorStream.listen((error) {
  ref.read(playbackErrorProvider.notifier).state = error;
});
```

### Mutating `Future<void>` methods in constructors
```dart
// Correct — catch errors on async calls in sync constructors
_player.setAudioDriver('aaudio').catchError((Object e, StackTrace? stack) {
  afLog('error', 'setAudioDriver failed', error: e, stackTrace: stack);
});
```

### Generation counters for cancelation
```dart
// Correct — stale operation guard
int _shuffleGen = 0;
Future<void> shuffle() async {
  final gen = ++_shuffleGen;
  await doSomething();
  if (gen != _shuffleGen) return; // stale, discard
}
```

---

## Error Handling

### Pattern
```dart
try {
  await riskyOperation();
} catch (e, stack) {
  afLog('error', 'descriptive message', error: e, stackTrace: stack);
  // Display user-friendly error
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(...);
  }
}
```

### DioException display
Use `displayError()` from `lib/utils/display_error.dart`:
```dart
final message = displayError(e, prefix: 'Search failed');
// → "Search failed: HTTP 500 from https://... (auth params redacted)"
```
Sensitive query params (Subsonic token/salt, Jellyfin api_key) are automatically redacted.

### AsyncErrorView long-press
`AsyncErrorView` supports long-press to open a dialog with the full `displayError` output. This lets users inspect truncated error details (e.g. Dio stack traces) without cluttering the inline card.

### Error widget (root)
```dart
ErrorWidget.builder = (details) => _RootErrorWidget(details: details);
// Release: generic message (no PII). Debug: full exception string.
```

---

## Logging

Use `afLog()` from `lib/utils/log.dart` — NEVER `print()`.

```dart
afLog('category', 'message');
afLog('error', 'operation failed', error: e, stackTrace: stack);
```

| Category | When |
|---|---|
| `boot` | Boot ordering, auth restoration |
| `http → / ← / ✕` | HTTP request / response / error |
| `error` | Caught exception + stacktrace |
| `data` | Provider data provenance |
| `audio` | Player state transitions |
| `live_update` | Live Update chip events |

PII (usernames, server URLs, tokens) must be redacted in release builds.

---

## Testing

### File naming
`*_test.dart` matching the source file name: `design_tokens_test.dart` tests `design_tokens/`.

### Structure
```dart
void main() {
  group('Feature name', () {
    setUp(() {
      // Initialize test dependencies
    });

    tearDown(() {
      // Clean up
    });

    test('describes what is verified', () {
      // Arrange
      // Act
      // Assert
    });
  });
}
```

### Patterns
- **Pure function tests**: no `setUp`/`tearDown` needed — just import and call
- **Local DB tests**: use `AppDatabase.forTesting(NativeDatabase.memory())` for in-memory DB
- **Regression tests**: begin with block comment explaining the past bug
- **Test names**: document the invariant, not the implementation
- **Mocking**: `Fake` class + `HttpOverrides.global` for HTTP; not mockito
- **No integration tests** — all 20 test files are unit tests

### Example
```dart
test('bass: enabled stays true when gain is non-zero', () {
  const settings = AudioEffects().copyWith(
    bass: BassSettings(enabled: true, gain: 6.0),
  );
  final result = autoBypassFlat(settings);
  expect(result.bass.enabled, isTrue);
});
```

---

## Model Patterns

```dart
/// Doc comment with /// triple-slash. Summary line, blank, then details.
class AfAlbum {
  final String id;
  final String name;
  final String? artist;
  final Duration duration;
  final bool isFavorite;

  const AfAlbum({
    required this.id,
    required this.name,
    this.artist,
    this.duration = Duration.zero,
    this.isFavorite = false,
  });

  /// copyWith for immutable mutations.
  AfAlbum copyWith({...}) => AfAlbum(...);

  @override
  bool operator ==(Object other) => ...;
  @override
  int get hashCode => Object.hash(id, name, ...);
}
```

- All models are **hand-written Dart classes** — no `json_serializable`
- Immutable with `copyWith()` for mutations
- `==` and `hashCode` overridden for value equality
- `@override` on all overridden methods

---

## Do's and Don'ts

### Do
- ✅ Use `afLog()` for all logging
- ✅ Use `const` constructors where possible
- ✅ Use `super.key` in widget constructors
- ✅ Use `FutureProvider.autoDispose` for async state
- ✅ Use `StateNotifierProvider` for mutable state
- ✅ Use `async/await` (not `.then()`) for async audio operations
- ✅ Use `_queueLock.run()` to serialize queue mutations
- ✅ Use `musicBackendProvider` (not `jellyfinClientProvider`) for backend ops
- ✅ Use `context.push()` for overlay/detail routes
- ✅ Use `context.go()` only for tab switches and auth redirects
- ✅ Check `context.mounted` before using `BuildContext` after async gap
- ✅ Guard `canPop()` before calling `context.pop()`
- ✅ Wrap async calls in sync constructors with `.catchError()`
- ✅ Redact PII (tokens, URLs, usernames) in release build logs/UI
- ✅ Use generation counters to cancel stale async operations
- ✅ Document regression tests with block comments explaining past bugs
- ✅ Use `AfDurations` and `AfCurves` tokens for all animation timings (never literal ms values)
- ✅ Use `StaggerReveal` for list/grid entrance animations (not `ListView.separated` with manual stagger)
- ✅ Use `AfSpacing.*` for all spacing — `SizedBox(height: AfSpacing.s8)`, `EdgeInsets.all(AfSpacing.s16)`
- ✅ Use `AfRadii.*` for all border radii — `AfRadii.borderSm`, `AfRadii.borderMd`, `AfRadii.borderPill`
- ✅ Use `AfTypography.*` text styles with `.copyWith()` — never raw `TextStyle(...)`
- ✅ Use `AfColors.*` for all colors — never `Colors.white`, `Colors.black`, or raw `Color(0x...)`

### Don't
- ❌ Never use `print()` — use `afLog()`
- ❌ Never use `just_audio` or `audio_session` — use `mpv_audio_kit`
- ❌ Never use `json_serializable` — hand-write models
- ❌ Never use `ChangeNotifier` for Riverpod providers
- ❌ Never pass network artwork URLs to native MediaSession — download to local file first
- ❌ Never use `Timer.periodic` for progress reporting — use serialized `while` loop
- ❌ Never use `Future.delayed` for auto-advance — use stream callbacks
- ❌ Never use `.then()` for jump+play — use `async/await`
- ❌ Never use 200/300/500ms durations — use the 5 token tiers only
- ❌ Never hardcode animation durations (e.g. `Duration(milliseconds: 300)`) — use `AfDurations.standard` etc.
- ❌ Never use `NoTransitionPage` for tab switches — use `AnimatedSwitcher` with `AfDurations.quick`
- ❌ Never hardcode auth header values in clients — use `aetherfinVersionProvider`
- ❌ Never store credentials in `shared_preferences` — use `flutter_secure_storage`
- ❌ Never use `context.go()` for overlay screens (lyrics, queue, settings)
- ❌ Never rebuild GoRouter — it's a module-level singleton
- ❌ Never add client-side smoothing to visualizer — engine handles it
- ❌ Never use `jellyfinClientProvider` for backend ops in UI — use `musicBackendProvider`
- ❌ Never create a separate HTTP client — add to `JellyfinClient` or `SubsonicClient`
- ❌ Never store Subsonic auth token — store password, generate `md5(password + salt)` per request
- ❌ Never reuse Subsonic salt — generate fresh random salt per request
- ❌ Never hardcode colors (e.g. `Colors.white`, `Color(0xFF...)`) — use `AfColors.*` tokens
- ❌ Never hardcode spacing (e.g. `SizedBox(height: 8)`) — use `AfSpacing.*` tokens
- ❌ Never hardcode border radii (e.g. `BorderRadius.circular(8)`) — use `AfRadii.*` tokens
- ❌ Never hardcode font sizes (e.g. `fontSize: 11`) — use `AfTypography.*` text styles
- ❌ Never use raw `TextStyle(...)` — use `AfTypography.*.copyWith(...)` instead
