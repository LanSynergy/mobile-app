import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/audio/offline_cache_service.dart';
import '../core/jellyfin/models/server.dart';
import 'local_library_providers.dart';

final reducedMotionProvider = Provider.autoDispose<bool>((ref) {
  try {
    return WidgetsBinding.instance.accessibilityFeatures.reduceMotion;
  } catch (_) {
    return false;
  }
});

final discoveredServersProvider = StateProvider<List<JellyfinServer>>((ref) => const <JellyfinServer>[]);

final artworkPulseEnabledProvider = StateProvider<bool>((ref) => true);

/// Shared [OfflineCacheService] instance.
final offlineCacheServiceProvider = Provider<OfflineCacheService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return OfflineCacheService(database: db);
});

/// Whether offline track caching is enabled.
final offlineCacheEnabledProvider = StateProvider<bool>((ref) => false);

/// Max cache size in bytes. Default 1 GB.
final offlineCacheMaxSizeProvider = StateProvider<int>((ref) {
  return 1024 * 1024 * 1024;
});
