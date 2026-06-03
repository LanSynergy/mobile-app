import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/youtube/youtube_auth.dart';
import '../core/youtube/youtube_home_content.dart';
import '../core/youtube/youtube_music_client.dart';
import '../core/youtube/innertube_client.dart';
import 'music_backend_providers.dart';

/// YouTube Music auth storage provider.
final youtubeAuthStorageProvider = Provider<YouTubeAuthStorage>(
  (ref) => YouTubeAuthStorage(),
);

/// Current YouTube Music auth state.
final youtubeAuthProvider = NotifierProvider<YouTubeAuthNotifier, YouTubeAuth?>(
  YouTubeAuthNotifier.new,
);

class YouTubeAuthNotifier extends Notifier<YouTubeAuth?> {
  @override
  YouTubeAuth? build() => null;

  Future<void> init() async {
    final stored = await ref.read(youtubeAuthStorageProvider).load();
    state = stored;
  }

  Future<void> save(YouTubeAuth auth) async {
    await ref.read(youtubeAuthStorageProvider).save(auth);
    state = auth;
  }

  Future<void> clear() async {
    await ref.read(youtubeAuthStorageProvider).clear();
    state = null;
  }
}

/// Selected YouTube home chip parameters.
final youtubeHomeParamsProvider = StateProvider.autoDispose<String?>((ref) => null);

/// Selected chip (if any).
final youtubeSelectedChipProvider = StateProvider.autoDispose<InnerTubeChip?>((ref) => null);

/// YouTube Music home page content (trending, popular, etc.).
class YouTubeHomeNotifier extends AutoDisposeAsyncNotifier<YouTubeHomeContent> {
  @override
  Future<YouTubeHomeContent> build() async {
    final backend = ref.watch(musicBackendProvider);
    if (backend is! YouTubeMusicClient) {
      return YouTubeHomeContent.empty();
    }
    final params = ref.watch(youtubeHomeParamsProvider);
    return backend.browseHome(params: params);
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || current.continuation == null) return;

    final backend = ref.read(musicBackendProvider);
    if (backend is! YouTubeMusicClient) return;

    try {
      final nextContent = await backend.browseHome(continuation: current.continuation);
      state = AsyncValue.data(YouTubeHomeContent(
        sections: [...current.sections, ...nextContent.sections],
        chips: current.chips,
        region: current.region,
        continuation: nextContent.continuation,
      ));
    } catch (e) {
      print('[YT-HOME] loadMore failed: $e');
    }
  }
}

final youtubeHomeProvider =
    AsyncNotifierProvider.autoDispose<YouTubeHomeNotifier, YouTubeHomeContent>(
  YouTubeHomeNotifier.new,
);
