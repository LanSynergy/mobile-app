import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

final discoveredServersProvider = StateProvider<List<JellyfinServer>>(
  (ref) => const <JellyfinServer>[],
);

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

/// Max streaming bitrate in kbps. 0 means Original / Lossless.
final maxBitrateProvider = StateProvider<int>((ref) => 0);

/// Whether smart queue autoplay is enabled.
final autoplayEnabledProvider = StateProvider<bool>((ref) => false);

final appIconProvider = StateNotifierProvider<AppIconNotifier, String>((ref) {
  return AppIconNotifier();
});

class AppIconNotifier extends StateNotifier<String> {
  AppIconNotifier() : super('DefaultIcon') {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString('af.app_icon') ?? 'DefaultIcon';
  }

  Future<void> setIcon(String iconName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('af.app_icon', iconName);
    state = iconName;
    try {
      const channel = MethodChannel('aetherfin.media_session');
      await channel.invokeMethod('changeAppIcon', {'icon': iconName});
    } catch (_) {}
  }
}
