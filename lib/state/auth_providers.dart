import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/jellyfin/auth_storage.dart';
import '../core/jellyfin/models/server.dart';

final authStorageProvider = Provider<AuthStorage>((ref) => AuthStorage());

final deviceIdProvider = Provider<String>((ref) {
  throw StateError(
    'deviceIdProvider was read before being overridden in main(). '
    'This is a bug — ProviderScope must override it with the value '
    'returned by AuthStorage.loadOrCreateDeviceId().',
  );
});

/// Aetherfin's running app version (pubspec `version:` minor minus build tag,
/// e.g. `0.2.3`). Used in `User-Agent`, the Jellyfin `MediaBrowser` auth
/// header's `Version` field, and the Subsonic `c=Aetherfin` client name.
///
/// Override pattern is identical to [deviceIdProvider]: `main()` loads the
/// value via `package_info_plus` during the boot phase and injects it into
/// the [ProviderContainer], so every [JellyfinClient] / [SubsonicClient]
/// built from [musicBackendProvider] picks it up automatically.
///
/// Reading this before `main()` overrides it is a programmer error — throw
/// loudly so a forgotten override surfaces in widget tests instead of
/// silently shipping a phantom version string to the server.
final aetherfinVersionProvider = Provider<String>((ref) {
  throw StateError(
    'aetherfinVersionProvider was read before being overridden in main(). '
    'This is a bug — ProviderScope must override it with the value '
    'returned by PackageInfo.fromPlatform().version.',
  );
});

final initialAuthProvider = Provider<JellyfinAuth?>((ref) {
  throw StateError(
    'initialAuthProvider was read before being overridden in main(). '
    'This is a bug — ProviderScope must override it with the value '
    'returned by AuthStorage.load() (or null when no auth is stored).',
  );
});

final authProvider = NotifierProvider<AuthNotifier, JellyfinAuth?>(
  AuthNotifier.new,
);

class AuthNotifier extends Notifier<JellyfinAuth?> {
  @override
  JellyfinAuth? build() => ref.read(initialAuthProvider);

  Future<void> save(JellyfinAuth auth) async {
    await ref.read(authStorageProvider).save(auth);
    state = auth;
  }

  Future<void> clear() async {
    await ref.read(authStorageProvider).clear();
    state = null;
  }
}
