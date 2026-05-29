import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/audio/offline_cache_service.dart';
import '../core/jellyfin/models/server.dart';
import '../core/lastfm/lastfm_client.dart';
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

/// Last.fm API key for enriching smart queue candidates.
final lastfmApiKeyProvider = StateProvider<String>((ref) => '');

/// Last.fm API secret for signing scrobbles.
final lastfmApiSecretProvider = StateProvider<String>((ref) => '');

/// Last.fm session key for scrobbling.
final lastfmSessionKeyProvider = StateProvider<String>((ref) => '');

/// Last.fm username for scrobbling.
final lastfmUsernameProvider = StateProvider<String>((ref) => '');

/// Whether Last.fm scrobbling is enabled.
final lastfmScrobbleEnabledProvider = StateProvider<bool>((ref) => true);

/// Central Last.fm client provider, watching api key, secret and session key.
final lastFmClientProvider = Provider<LastFmClient?>((ref) {
  final apiKey = ref.watch(lastfmApiKeyProvider);
  final apiSecret = ref.watch(lastfmApiSecretProvider);
  final sessionKey = ref.watch(lastfmSessionKeyProvider);
  if (apiKey.isEmpty) return null;
  return LastFmClient(
    apiKey: apiKey,
    apiSecret: apiSecret.isEmpty ? null : apiSecret,
    sessionKey: sessionKey.isEmpty ? null : sessionKey,
  );
});

final appIconProvider = NotifierProvider<AppIconNotifier, String>(
  AppIconNotifier.new,
);

class AppIconNotifier extends Notifier<String> {
  @override
  String build() {
    _load();
    return 'DefaultIcon';
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
