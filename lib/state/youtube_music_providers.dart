import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/youtube/youtube_auth.dart';

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
