import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/audio/player_service.dart';
import '../core/audio/spectral_extractor.dart';
import '../core/demo/demo_library.dart';
import '../core/jellyfin/auth_storage.dart';
import '../core/jellyfin/client.dart';
import '../core/jellyfin/models/items.dart';
import '../core/jellyfin/models/server.dart';
import '../design_tokens/colors.dart';

/// ─────────────────────────────────────────────────────────────────────────
/// Auth
/// ─────────────────────────────────────────────────────────────────────────

final authStorageProvider = Provider<AuthStorage>((ref) => AuthStorage());

/// Stable per-install device ID used in the Jellyfin Authorization header.
/// Overridden at app startup in `main.dart` with the value loaded from
/// `AuthStorage.loadOrCreateDeviceId()`. Throws if accessed before that
/// override is applied — a loud failure is preferable to silently sending
/// the literal string "uninitialized" to Jellyfin.
final deviceIdProvider = Provider<String>((ref) {
  throw StateError(
    'deviceIdProvider was read before being overridden in main(). '
    'This is a bug — ProviderScope must override it with the value '
    'returned by AuthStorage.loadOrCreateDeviceId().',
  );
});

/// Auth blob loaded synchronously from secure storage at app startup.
/// Overridden in `main.dart` so that [authProvider]'s initial state is
/// the persisted auth (if any) — never `null` followed by an async
/// hydrate() that would race with a sign-in `save()` and clobber it.
final initialAuthProvider = Provider<JellyfinAuth?>((ref) {
  throw StateError(
    'initialAuthProvider was read before being overridden in main(). '
    'This is a bug — ProviderScope must override it with the value '
    'returned by AuthStorage.load() (or null when no auth is stored).',
  );
});

final authProvider = StateNotifierProvider<AuthNotifier, JellyfinAuth?>((ref) {
  return AuthNotifier(
    ref.watch(authStorageProvider),
    initial: ref.watch(initialAuthProvider),
  );
});

class AuthNotifier extends StateNotifier<JellyfinAuth?> {
  final AuthStorage _storage;
  AuthNotifier(this._storage, {JellyfinAuth? initial}) : super(initial);

  Future<void> save(JellyfinAuth auth) async {
    state = auth;
    await _storage.save(auth);
  }

  Future<void> clear() async {
    state = null;
    await _storage.clear();
  }
}

/// ─────────────────────────────────────────────────────────────────────────
/// Jellyfin client (null when no auth — UI uses demo data in that case)
/// ─────────────────────────────────────────────────────────────────────────

final jellyfinClientProvider = Provider<JellyfinClient?>((ref) {
  final auth = ref.watch(authProvider);
  if (auth == null) return null;
  return JellyfinClient(
    server: auth.server,
    deviceId: ref.watch(deviceIdProvider),
    accessToken: auth.accessToken,
    userId: auth.userId,
  );
});

/// ─────────────────────────────────────────────────────────────────────────
/// Audio player (singleton handler)
/// ─────────────────────────────────────────────────────────────────────────

final playerServiceProvider = Provider<AfPlayerService>((ref) {
  final svc = AfPlayerService();
  ref.onDispose(svc.dispose);
  return svc;
});

/// Stream of position from the single player. Per non-negotiable §4.3,
/// every UI consumer (ring, waveform, lyric scroll, time labels) listens
/// to THIS stream — never a private timer.
final positionStreamProvider = StreamProvider.autoDispose<Duration>((ref) {
  final svc = ref.watch(playerServiceProvider);
  return svc.positionStream;
});

final playingStreamProvider = StreamProvider.autoDispose<bool>((ref) {
  final svc = ref.watch(playerServiceProvider);
  return svc.playingStream;
});

/// Currently-playing track (changes when the player advances within
/// the queue). Null when no playback has been started this session.
final currentTrackProvider = StateProvider<AfTrack?>((ref) => null);

/// True the moment any playback has been started this session — drives
/// whether the floating mini-player is rendered.
final hasActivePlaybackProvider = Provider<bool>((ref) {
  return ref.watch(currentTrackProvider) != null;
});

/// ─────────────────────────────────────────────────────────────────────────
/// Spectral accent — Riverpod family keyed by track ID. Uses image-based
/// extraction when an artwork URL is available, otherwise falls back to
/// the indigo default.
/// ─────────────────────────────────────────────────────────────────────────

final spectralExtractorProvider =
    Provider<SpectralExtractor>((ref) => SpectralExtractor());

final spectralProvider =
    FutureProvider.autoDispose.family<Spectral, AfTrack?>((ref, track) async {
  if (track?.imageUrl == null) return Spectral.fallback;
  try {
    return await ref.watch(spectralExtractorProvider).fromImageUrl(track!.imageUrl!);
  } catch (_) {
    return Spectral.fallback;
  }
});

/// Currently-resolved spectral triple for the currently-playing track.
final currentSpectralProvider = Provider<Spectral>((ref) {
  final track = ref.watch(currentTrackProvider);
  final async = ref.watch(spectralProvider(track));
  return async.maybeWhen(data: (s) => s, orElse: () => Spectral.fallback);
});

/// ─────────────────────────────────────────────────────────────────────────
/// Library (demo backed for v1; swaps to live Jellyfin when authed)
/// ─────────────────────────────────────────────────────────────────────────

/// Recently added albums. When authenticated, hits Jellyfin's `Latest`
/// endpoint; when not, falls back to the bundled demo library so the
/// onboarding "All set" preview still has something to render.
final recentlyAddedAlbumsProvider =
    FutureProvider.autoDispose<List<AfAlbum>>((ref) async {
  final client = ref.watch(jellyfinClientProvider);
  if (client == null) return DemoLibrary.albums;
  return client.recentlyAddedAlbums();
});

final recentlyPlayedTracksProvider =
    FutureProvider.autoDispose<List<AfTrack>>((ref) async {
  final client = ref.watch(jellyfinClientProvider);
  if (client == null) return DemoLibrary.tracks.take(10).toList();
  return client.recentlyPlayed();
});

final allArtistsProvider =
    FutureProvider.autoDispose<List<AfArtist>>((ref) async {
  final client = ref.watch(jellyfinClientProvider);
  if (client == null) return DemoLibrary.artists;
  return client.artists();
});

final allPlaylistsProvider =
    FutureProvider.autoDispose<List<AfPlaylist>>((ref) async {
  final client = ref.watch(jellyfinClientProvider);
  if (client == null) return DemoLibrary.playlists;
  return client.playlists();
});

/// Music genres. Jellyfin returns these without colors so we cycle through
/// a small palette to keep the chip row colourful.
final allGenresProvider =
    FutureProvider.autoDispose<List<AfGenre>>((ref) async {
  final client = ref.watch(jellyfinClientProvider);
  if (client == null) return DemoLibrary.genres;
  return client.genres();
});

final albumDetailProvider = FutureProvider.autoDispose
    .family<({AfAlbum album, List<AfTrack> tracks})?, String>((ref, id) async {
  final client = ref.watch(jellyfinClientProvider);
  if (client != null) {
    return client.album(id);
  }
  final album = DemoLibrary.albumById(id);
  if (album == null) return null;
  return (album: album, tracks: DemoLibrary.tracksByAlbum(id));
});

final artistDetailProvider =
    FutureProvider.autoDispose.family<AfArtist?, String>((ref, id) async {
  final client = ref.watch(jellyfinClientProvider);
  if (client != null) {
    return client.artist(id);
  }
  return DemoLibrary.artistById(id);
});

/// ─────────────────────────────────────────────────────────────────────────
/// Settings
/// ─────────────────────────────────────────────────────────────────────────

final showNavLabelsProvider = StateProvider<bool>((ref) => false);

final reducedMotionProvider = Provider.autoDispose<bool>((ref) {
  // Re-evaluated whenever MediaQuery changes — UIs read this via
  // MediaQuery.disableAnimations OR via this provider in non-widget code.
  return false;
});

/// ─────────────────────────────────────────────────────────────────────────
/// Server discovery results (used by the onboarding flow)
/// ─────────────────────────────────────────────────────────────────────────

final discoveredServersProvider =
    StateProvider<List<JellyfinServer>>((ref) => const []);
