# Contributing to Aetherfin

Thank you for your interest in contributing to Aetherfin! This document covers everything you need to know to set up, develop, test, and submit changes.

---

## Prerequisites

| Requirement | Version | Notes |
|-------------|---------|-------|
| **Flutter SDK** | 3.44.0 | Exact version required |
| **Dart SDK** | 3.11.5 | Bundled with Flutter 3.44 |
| **Java** | 17 | Required for Android builds |
| **Git** | Latest | For version control |

Verify your setup:
```bash
flutter --version
# Should output: Flutter 3.44.0 • channel stable • https://github.com/flutter/flutter.git
# Framework • revision 1159914630 (5 weeks ago) • 2026-05-08 14:28:51 -0700
# Engine • revision a457a28439
# Tools • Dart 3.11.5 • DevTools 2.37.0
```

---

## Setup

### 1. Clone the repository

```bash
git clone https://github.com/Aetherfin/mobile-app.git
cd mobile-app
```

### 2. Install dependencies

```bash
flutter pub get
```

> **Note:** First build downloads ~20MB libmpv `.so` files per ABI (arm64-v8a, x86_64) from GitHub Releases. Ensure you have internet connectivity and sufficient disk space.

---

## Project Structure

```
lib/
├─ app/                     # App root: router, theme, entry
│  ├─ app.dart             # MaterialApp.router + Nocturne theme
│  ├─ router.dart          # GoRouter: shell + 20+ routes
│  └─ theme.dart           # Design tokens → ThemeData
│
├─ design_tokens/          # Visual spec (single source of truth)
│  ├─ colors.dart          # AfColors: indigo scale + surfaces + text + semantic
│  ├─ motion.dart          # AfCurves + AfDurations
│  ├─ radii.dart           # Border radii
│  ├─ spacing.dart         # 4px grid spacing system
│  └─ typography.dart      # Text styles
│
├─ core/                   # Domain layer
│  ├─ audio/               # Playback engine (mpv_audio_kit)
│  ├─ backend/             # MusicBackend interface
│  ├─ jellyfin/            # Jellyfin client + models
│  ├─ subsonic/            # Subsonic/Navidrome clients
│  ├─ local/               # Local mode: drift DB, SAF scanner
│  ├─ lastfm/              # Last.fm integration
│  └─ ...
│
├─ state/                  # Riverpod providers (17 files, barrel-exported)
│  ├─ providers.dart       # Barrel re-export
│  ├─ auth_providers.dart
│  ├─ player_providers.dart
│  └─ ...
│
├─ features/               # Screens (13 folders)
│  ├─ home/                # Carousel + recent items
│  ├─ library/             # Albums/artists/songs/genres
│  ├─ now_playing/         # Full-screen + EQ/DSP route
│  ├─ queue/
│  ├─ search/
│  └─ ...
│
├─ widgets/                # Shared widgets (22 files)
│  ├─ app_shell.dart       # 4-tab shell
│  └─ ...
│
└─ utils/                  # Helpers
   ├─ log.dart             # afLog() wrapper
   └─ ...
```

---

## Development

### Run the app

```bash
# Debug build
flutter run --debug

# Specify device
flutter run --debug -d <device-id>
```

### Code Generation

Aetherfin uses `drift` for database code generation. After modifying drift files:

```bash
dart run build_runner build
```

---

## Testing

### Run all tests

```bash
flutter test
```

### Run specific test file

```bash
flutter test test/<path>/<file>_test.dart
```

### Static analysis

```bash
flutter analyze --no-fatal-infos
```

### CI Checks (run before pushing)

```bash
flutter analyze --no-fatal-infos
flutter test
```

---

## Code Style & Conventions

### Linting

The project uses strict linting rules defined in `analysis_options.yaml`:

- `strict-casts: true`
- `strict-raw-types: true`
- `prefer_final_locals: true`
- `require_trailing_commas: true`
- `avoid_print: true`
- `use_build_context_synchronously: true`

**Note on `avoid_dynamic_calls`:** This rule is intentionally disabled. Dynamic types are used in specific cases:
- Multi-type returns in `smart_playlist_engine.dart` (`_getField`)
- 3rd-party API parameters (`multicast_dns` host param)
- Duck-typed parameters (`playlist_undo_buffer.dart`)
All usages are type-checked at runtime.

### Formatting

```bash
# Format all files
dart format .
```

### Design Tokens

**Never hardcode colors, spacing, or typography values.** Use design tokens from `lib/design_tokens/tokens.dart`:

```dart
// ✅ Good
color: AfColors.textPrimary,
padding: const EdgeInsets.all(AfSpacing.s16),
style: AfTypography.bodyLarge,

// ❌ Bad
color: const Color(0xFFFFFFFF),
padding: const EdgeInsets.all(16),
style: const TextStyle(fontSize: 16),
```

Design token tests enforce exact values. See `test/design_tokens_test.dart`.

### Architecture Rules

See `ARCHITECTURE.md` and `CLAUDE.md` for complete architecture documentation. Key rules:

1. **Audio engine is `mpv_audio_kit`** — never `just_audio` or alternatives
2. **No `json_serializable`** — all models are hand-written Dart classes
3. **Stream URLs embed auth as query params** — libmpv/FFmpeg rejects headers
4. **Favorites are server-owned** — flip locally first, revert on HTTP error
5. **Queue operations serialized via `AfAsyncLock`** — prevents interleaved mutations
6. **GoRouter is module-level singleton** — never recreated
7. **`context.push()` for overlays, `context.go()` for tab switches**

---

## Common Pitfalls

### 1. Timer Leaks in StatefulWidget

Always cancel timers in `dispose()`:

```dart
// ✅ Good
class MyScreen extends StatefulWidget {
  @override
  _MyScreenState createState() => _MyScreenState();
}

class _MyScreenState extends State<MyScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(Duration(seconds: 1), (t) => _onTick());
  }

  @override
  void dispose() {
    _timer?.cancel();  // Cancel timer!
    super.dispose();
  }
}

// ❌ Bad - timer leaks
class _BadScreenState extends State<BadScreen> {
  @override
  void initState() {
    super.initState();
    Timer.periodic(Duration(seconds: 1), (t) => _onTick());
    // No way to cancel this timer!
  }
}
```

### 2. Stream Subscriptions

Always cancel stream subscriptions:

```dart
StreamSubscription? _sub;

@override
void initState() {
  super.initState();
  _sub = someStream.listen(_onData);
}

@override
void dispose() {
  _sub?.cancel();
  super.dispose();
}
```

### 3. Riverpod Provider Lifecycle

Use `autoDispose` for providers tied to widget lifecycle:

```dart
// ✅ Good - auto-disposed when no longer needed
final myProvider = FutureProvider.autoDispose<MyData>((ref) async {
  return await fetchData();
});

// ❌ Bad - lives forever, can cause memory leaks
final myProvider = FutureProvider<MyData>((ref) async {
  return await fetchData();
});
```

---

## Pull Request Process

### Before Submitting

1. Run static analysis:
   ```bash
   flutter analyze --no-fatal-infos
   ```
   Fix all warnings and errors.

2. Run all tests:
   ```bash
   flutter test
   ```
   All tests must pass.

3. Test manually:
   - Run the app on a real Android device
   - Test the feature you're adding/changing
   - Verify no regressions in existing functionality

### Commit Messages

Use [Conventional Commits](https://www.conventionalcommits.org/) format:

```
feat: add new feature
fix: resolve issue with X
chore: update dependencies
docs: update README
refactor: simplify Y logic
perf: optimize Z performance
```

### PR Title

Follow the same convention as commit messages. Include the feature/area in scope:

- `feat(onboarding): add server discovery screen`
- `fix(audio): prevent position tracking glitch`
- `docs: update ARCHITECTURE.md`

---

## Reporting Issues

When reporting bugs:

1. **Include device information:**
   - Android version
   - Device model
   - Aetherfin version

2. **Include server information (if applicable):**
   - Jellyfin/Navidrome version
   - Server OS

3. **Steps to reproduce:**
   - Clear, numbered steps
   - Expected behavior
   - Actual behavior

4. **Logs:**
   - Attach `adb logcat` output
   - Filter with: `adb logcat | grep aetherfin`

---

## Resources

- [Flutter Documentation](https://flutter.dev/docs)
- [Riverpod Documentation](https://riverpod.dev/docs)
- [Dart Language](https://dart.dev/guides/language)
- [Aetherfin Architecture](ARCHITECTURE.md)
- [Aetherfin Project Guide](CLAUDE.md)

---

## License

By contributing to Aetherfin, you agree that your contributions will be licensed under the [MIT License](LICENSE).
