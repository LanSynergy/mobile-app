import 'dart:async' show StreamController, Timer, unawaited;

import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show Loop, FftFrame;

import '../core/audio/jellyfin_playback_reporter.dart';
import '../core/audio/live_update_service.dart';
import '../core/audio/player_service.dart';
import '../core/audio/player_settings_store.dart';
import '../core/audio/spectral_extractor.dart';
import '../core/backend/music_backend.dart';
import '../core/jellyfin/auth_storage.dart';
import '../core/local/local_library.dart';
import '../core/jellyfin/client.dart';
import '../core/jellyfin/models/items.dart';
import '../core/jellyfin/models/server.dart';
import '../core/lyrics/lrc_parser.dart';
import '../core/subsonic/client.dart';
import '../design_tokens/colors.dart';
import '../utils/log.dart';

// ─────────────────────────────────────────────────────────────────────────────
// App Mode
// ─────────────────────────────────────────────────────────────────────────────

/// The app operates in one of two mutually exclusive modes.
/// Persisted in shared_preferences as 'af.app_mode'.
enum AppMode { server, local }

/// Current app mode. Null on first launch (user hasn't chosen yet).
/// Overridden in main.dart from persisted value.
final appModeProvider = StateProvider<AppMode?>((ref) => null);

/// Scan progress for local library. Null when not scanning.
/// Value is (completed, total) tuple.
final localScanProgressProvider =
    StateProvider<({int completed, int total})?>((ref) => null);

// ─────────────────────────────────────────────────────────────────────────────
// Local library providers
// ─────────────────────────────────────────────────────────────────────────────

/// Singleton LocalLibrary instance. Created once, reused across providers.
final localLibraryProvider = Provider<LocalLibrary>((ref) {
  final lib = LocalLibrary();
  ref.onDispose(() => lib.close());
  return lib;
});

/// All albums from local SQLite DB.
final localAlbumsProvider = FutureProvider.autoDispose<List<AfAlbum>>((ref) {
  final lib = ref.watch(localLibraryProvider);
  return lib.albums();
});

/// All artists from local SQLite DB.
final localArtistsProvider = FutureProvider.autoDispose<List<AfArtist>>((ref) {
  final lib = ref.watch(localLibraryProvider);
  return lib.artists();
});

/// All tracks from local SQLite DB.
final localTracksProvider = FutureProvider.autoDispose<List<AfTrack>>((ref) {
  final lib = ref.watch(localLibraryProvider);
  return lib.tracks();
});

/// All genres from local SQLite DB.
final localGenresProvider = FutureProvider.autoDispose<List<AfGenre>>((ref) {
  final lib = ref.watch(localLibraryProvider);
  return lib.genres();
});

/// Compact one-liner for the `aetherfin:data` trace category.
///
/// Every place that resolves data the UI will render goes through this
/// helper so an `adb logcat -s flutter | grep aetherfin:data` output
/// shows exactly which feature served live Jellyfin data vs. demo data
/// vs. still-mocked data. Used by reviewers to spot regressions where a
/// screen silently slips back onto `DemoLibrary` after sign-in.
void _logData(
  String feature, {
  required String source,
  String? extra,
}) {
  final detail = extra == null || extra.isEmpty ? '' : ' $extra';
  afLog('data', '$feature source=$source$detail');
}

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

  /// Persist [auth] FIRST, then flip in-memory state.
  ///
  /// Previously we set `state = auth` before the storage write — if the
  /// keystore was full / corrupted the user looked signed in but the
  /// next app launch would silently kick them back to onboarding. By
  /// failing loudly here the sign-in screen surfaces the error instead,
  /// and a successful flip implies the secret already hit disk.
  Future<void> save(JellyfinAuth auth) async {
    await _storage.save(auth);
    state = auth;
  }

  Future<void> clear() async {
    // The Jellyfin client provider listens to this state and tears
    // itself down (HTTP cache + connection pool) via `ref.onDispose`
    // when `state` flips to null.
    state = null;
    await _storage.clear();
  }
}

/// ─────────────────────────────────────────────────────────────────────────
/// Music backend (null when no auth — UI uses demo data in that case)
///
/// Returns a [JellyfinClient] or [SubsonicClient] depending on the
/// stored [ServerType]. All data providers below use this instead of
/// a specific client type.
/// ─────────────────────────────────────────────────────────────────────────

final musicBackendProvider = Provider<MusicBackend?>((ref) {
  final auth = ref.watch(authProvider);
  if (auth == null) {
    _logData('musicBackend', source: 'demo', extra: '(signed out)');
    return null;
  }
  _logData('musicBackend',
      source: 'live',
      extra: 'type=${auth.serverType.name} '
          'server=${auth.server.baseUrl} user=${auth.userName}');
  final MusicBackend client;
  switch (auth.serverType) {
    case ServerType.subsonic:
      client = SubsonicClient(
        server: auth.server,
        username: auth.userName,
        password: auth.accessToken, // accessToken stores password for Subsonic
      );
    case ServerType.jellyfin:
      client = JellyfinClient(
        server: auth.server,
        deviceId: ref.watch(deviceIdProvider),
        accessToken: auth.accessToken,
        userId: auth.userId,
      );
  }
  ref.onDispose(client.close);
  return client;
});

/// Convenience alias: returns the backend as [JellyfinClient] when
/// the server type is Jellyfin, otherwise `null`. Used for
/// Jellyfin-specific operations (authenticate, publicInfo) that are
/// not part of the [MusicBackend] interface.
final jellyfinClientProvider = Provider<JellyfinClient?>((ref) {
  final backend = ref.watch(musicBackendProvider);
  if (backend is JellyfinClient) return backend;
  return null;
});

/// ─────────────────────────────────────────────────────────────────────────
/// Audio player (singleton handler)
/// ─────────────────────────────────────────────────────────────────────────

/// Wires Riverpod-side side-effects onto an [AfPlayerService] instance:
///   1. Forwards `onTrackChanged` to `currentTrackProvider` so the UI
///      re-renders on queue advance / manual skip / lock-screen action.
///   2. Instantiates the [JellyfinPlaybackReporter] (Sessions/Playing*
///      lifecycle) bound to the same service.
///   3. Registers disposal so both the reporter and the service shut
///      down when the ProviderScope is torn down.
///
/// Pulled out as a free function so `main.dart` can hand the *same*
/// service instance to `AudioService.init` (for lock-screen controls)
/// and to the provider tree — without duplicating the wiring logic
/// across the default factory and the override.
void wirePlayerService(Ref ref, AfPlayerService svc) {
  svc.onTrackChanged = (track) {
    ref.read(currentTrackProvider.notifier).state = track;
  };

  // Playback reporting only in server mode — local mode has no server.
  final mode = ref.read(appModeProvider);
  JellyfinPlaybackReporter? reporter;
  if (mode != AppMode.local) {
    reporter = JellyfinPlaybackReporter(
      svc,
      () => ref.read(musicBackendProvider),
    );
  }

  final liveUpdate = LiveUpdateService(svc);
  unawaited(liveUpdate.attach());
  unawaited(svc.configureSpectrum().then((_) {
    // Apply user-tweaked audio settings (sample rate, bit depth, cache,
    // ReplayGain, etc.) after the spectrum pipeline is configured.
    return PlayerSettingsStore.applyPersisted(svc);
  }));

  // When the user signs out (auth → null), send a final Stopped ping so
  // Jellyfin's activity feed doesn't show the user as "still playing".
  // requestStopOnDispose() must be called before dispose() fires.
  ref.listen<JellyfinAuth?>(authProvider, (prev, next) {
    if (prev != null && next == null) {
      reporter?.requestStopOnDispose();
    }
  });

  ref.onDispose(() async {
    await liveUpdate.dispose();
    await reporter?.dispose();
    await svc.dispose();
  });
}

final playerServiceProvider = Provider<AfPlayerService>((ref) {
  final svc = AfPlayerService();
  wirePlayerService(ref, svc);
  return svc;
});

/// Live queue exposed by the player. The Queue screen watches this so
/// reorder / skip / play-new-album immediately re-render — no more
/// snapshotting `DemoLibrary.tracks` into local state.
final playerQueueProvider = StreamProvider.autoDispose<List<AfTrack>>((ref) {
  final svc = ref.watch(playerServiceProvider);
  // Emit the current snapshot first so a freshly mounted Queue screen
  // doesn't render an empty list while waiting for the next stream tick.
  return Stream<List<AfTrack>>.multi((controller) {
    controller.add(svc.currentQueue);
    final sub = svc.queueStream.listen(controller.add);
    controller.onCancel = sub.cancel;
  });
});

/// Stream of position from the single player. Per non-negotiable §4.3,
/// every UI consumer (ring, waveform, lyric scroll, time labels) listens
/// to THIS stream — never a private timer.
///
/// mpv_audio_kit's ReactiveProperty deduplicates by == — when position
/// resets to the same Duration (e.g. Duration.zero on track change or
/// seek-to-start), the reactive stream suppresses the event. A 200 ms
/// heartbeat polls the synchronous position to guarantee the UI always
/// has fresh data even when the reactive stream is silent.
final positionStreamProvider = StreamProvider.autoDispose<Duration>((ref) {
  final svc = ref.watch(playerServiceProvider);
  final ctrl = StreamController<Duration>();
  Duration lastEmitted = const Duration(microseconds: -1);

  void emit(Duration pos) {
    if (pos == lastEmitted) return;
    lastEmitted = pos;
    ctrl.add(pos);
  }

  /// Force-emit Duration.zero regardless of dedup — used on track change
  /// so the progress bar resets immediately instead of appearing frozen.
  void forceReset() {
    lastEmitted = const Duration(microseconds: -1);
    ctrl.add(Duration.zero);
  }

  // Seed with the current synchronous position so the first frame
  // renders without waiting for the next stream tick.
  emit(svc.position);

  // Forward high-frequency reactive events.
  final sub = svc.positionStream.listen((pos) => emit(pos));

  // Reset position on track change so the bar doesn't appear stuck at
  // the previous track's last position while the new track buffers.
  final trackSub = svc.currentTrackStream.listen((_) => forceReset());

  // Heartbeat: poll at ~10 Hz to keep the progress bar smooth even when
  // the reactive stream is silent (e.g. during buffering transitions).
  final timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
    emit(svc.position);
  });

  ref.onDispose(() {
    timer.cancel();
    sub.cancel();
    trackSub.cancel();
    ctrl.close();
  });

  return ctrl.stream;
});

final playingStreamProvider = StreamProvider.autoDispose<bool>((ref) {
  final svc = ref.watch(playerServiceProvider);
  return svc.playingStream;
});

/// Live shuffle flag — drives the shuffle icon's active tint in
/// Now Playing / Queue. Seeded with the player's current value so the
/// first frame matches reality without waiting for the next emit.
final shuffleModeProvider = StreamProvider.autoDispose<bool>((ref) {
  final svc = ref.watch(playerServiceProvider);
  return Stream<bool>.multi((controller) {
    controller.add(svc.isShuffleEnabled);
    final sub = svc.shuffleModeStream.listen(controller.add);
    controller.onCancel = sub.cancel;
  });
});

/// Live loop mode — drives the repeat icon (off / all / one) in Now Playing.
final loopModeProvider = StreamProvider.autoDispose<Loop>((ref) {
  final svc = ref.watch(playerServiceProvider);
  return Stream<Loop>.multi((controller) {
    controller.add(svc.loopMode);
    final sub = svc.loopModeStream.listen(controller.add);
    controller.onCancel = sub.cancel;
  });
});

/// Live playback speed multiplier — drives the Speed sheet's checkmark.
final playbackSpeedProvider = StreamProvider.autoDispose<double>((ref) {
  final svc = ref.watch(playerServiceProvider);
  return Stream<double>.multi((controller) {
    controller.add(svc.speed);
    final sub = svc.speedStream.listen(controller.add);
    controller.onCancel = sub.cancel;
  });
});

/// Real-time FFT spectrum from mpv_audio_kit — 64 log-spaced bands in
/// [0, 1] at ~30 fps. No RECORD_AUDIO permission needed. Lazy: pipeline
/// starts on first listener, stops on last cancel. Drives [BeatPulseArtwork].
///
/// Note: The spectrum is captured post-DSP (`pcm-tap-frame`).
/// `mpv_audio_kit` 0.1.3 does not expose a pre-DSP tap point.
/// A future library update may add a bypass option; until then the
/// visualizer reflects processed audio.
final fftSpectrumProvider = StreamProvider.autoDispose<FftFrame>((ref) {
  final svc = ref.watch(playerServiceProvider);
  return svc.spectrumStream;
});

/// Currently-playing track (changes when the player advances within
/// the queue). Null when no playback has been started this session.
final currentTrackProvider = StateProvider<AfTrack?>((ref) => null);

/// Imperative helper to toggle a track's favorite state.
///
/// Optimistically flips the in-memory `currentTrackProvider.isFavorite`
/// so the heart fills/empties on the next frame, then POSTs/DELETEs
/// `/Users/{id}/FavoriteItems/{trackId}`. On HTTP failure we revert.
///
/// Signed-out (no client) → updates the local state only; the next sign-in
/// will resync against the server's user-data on the next track fetch.
final favoriteToggleProvider = Provider<Future<void> Function(AfTrack)>((ref) {
  return (AfTrack track) async {
    final backend = ref.read(musicBackendProvider);
    final next = !track.isFavorite;
    final updated = track.copyWith(isFavorite: next);
    final current = ref.read(currentTrackProvider);
    if (current?.id == track.id) {
      ref.read(currentTrackProvider.notifier).state = updated;
    }
    if (backend == null) {
      _logData('favoriteToggle',
          source: 'demo',
          extra: '(signed out) id=${track.id} isFavorite=$next');
      return;
    }
    try {
      await backend.setFavorite(track.id, next);
      _logData('favoriteToggle',
          source: 'live',
          extra: 'id=${track.id} isFavorite=$next');
      // Force every cached favorites surface to re-fetch from the server
      // so they reflect the new state on the next frame. Without this,
      // the heart on the album/now-playing screen filled but the
      // "Favorite albums" row on Home still showed the stale list until
      // the user manually pulled to refresh. The .autoDispose providers
      // below all live for the duration of the screen they're watched
      // on; invalidation is a no-op when nothing is listening.
      ref.invalidate(favoriteAlbumsProvider);
      ref.invalidate(favoriteTracksProvider);
      ref.invalidate(recentlyPlayedTracksProvider);
    } catch (e, stack) {
      afLog(
        'error',
        'favoriteToggle failed',
        error: e,
        stackTrace: stack,
      );
      // Revert optimistic flip on server error.
      if (current?.id == track.id) {
        ref.read(currentTrackProvider.notifier).state = track;
      }
      rethrow;
    }
  };
});

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
  // Hand the same Authorization header to PaletteGenerator that the
  // CachedNetworkImage widgets use — once the token moved out of the
  // URL query string (review S2), unauthed artwork fetches would 401
  // and the player UI would flicker back to fallback indigo.
  final backend = ref.watch(musicBackendProvider);
  final headers = backend?.authHeaders;
  try {
    return await ref
        .watch(spectralExtractorProvider)
        .fromImageUrl(track!.imageUrl!, headers: headers);
  } catch (e) {
    afLog('spectral', 'spectral extraction failed', error: e);
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
  final backend = ref.watch(musicBackendProvider);
  if (backend == null) {
    _logData('recentlyAddedAlbums',
        source: 'demo', extra: '(signed out)');
    return const [];
  }
  final res = await backend.recentlyAddedAlbums();
  _logData('recentlyAddedAlbums', source: 'live', extra: 'count=${res.length}');
  return res;
});

final recentlyPlayedTracksProvider =
    FutureProvider.autoDispose<List<AfTrack>>((ref) async {
  final backend = ref.watch(musicBackendProvider);
  if (backend == null) {
    _logData('recentlyPlayedTracks',
        source: 'demo', extra: '(signed out)');
    return const [];
  }
  final res = await backend.recentlyPlayed();
  _logData('recentlyPlayedTracks',
      source: 'live', extra: 'count=${res.length}');
  return res;
});

final allArtistsProvider =
    FutureProvider.autoDispose<List<AfArtist>>((ref) async {
  final backend = ref.watch(musicBackendProvider);
  if (backend == null) {
    _logData('allArtists', source: 'demo', extra: '(signed out)');
    return const [];
  }
  final res = await backend.artists();
  _logData('allArtists', source: 'live', extra: 'count=${res.length}');
  return res;
});

final allPlaylistsProvider =
    FutureProvider.autoDispose<List<AfPlaylist>>((ref) async {
  final backend = ref.watch(musicBackendProvider);
  if (backend == null) {
    _logData('allPlaylists', source: 'demo', extra: '(signed out)');
    return const [];
  }
  final res = await backend.playlists();
  _logData('allPlaylists', source: 'live', extra: 'count=${res.length}');
  return res;
});

/// Tracks that have been saved to a playlist during this session.
/// Used to show "Saved" state on the Now Playing utility row without
/// requiring an API call on every render.
final savedTrackIdsProvider = StateProvider<Set<String>>((ref) => {});

/// Set of track IDs that exist in ANY of the user's playlists.
/// Fetched once and invalidated when playlists change.
final playlistTrackIdsProvider =
    FutureProvider.autoDispose<Set<String>>((ref) async {
  final backend = ref.watch(musicBackendProvider);
  if (backend == null) return {};
  final playlists = await ref.watch(allPlaylistsProvider.future);
  final ids = <String>{};
  for (final pl in playlists) {
    try {
      final detail = await backend.playlist(pl.id);
      if (detail != null) {
        for (final t in detail.tracks) {
          ids.add(t.id);
        }
      }
    } catch (e) {
      afLog('data', 'playlist track fetch failed id=${pl.id}', error: e);
    }
  }
  return ids;
});

/// User's favourite (heart-flagged) albums. Powers the Profile screen's
/// "Pinned" row. Previously the row was hard-coded with four demo album
/// names; now it shows real favourites, falling back to the most
/// recently added albums when the user hasn't hearted anything yet so
/// the row is never empty.
final favoriteAlbumsProvider =
    FutureProvider.autoDispose<List<AfAlbum>>((ref) async {
  final backend = ref.watch(musicBackendProvider);
  if (backend == null) {
    _logData('favoriteAlbums', source: 'demo', extra: '(signed out)');
    return const [];
  }
  final res = await backend.favoriteAlbums();
  _logData('favoriteAlbums', source: 'live', extra: 'count=${res.length}');
  return res;
});

/// All tracks the user has marked as favorite / starred.
final favoriteTracksProvider =
    FutureProvider.autoDispose<List<AfTrack>>((ref) async {
  final backend = ref.watch(musicBackendProvider);
  if (backend == null) {
    _logData('favoriteTracks', source: 'demo', extra: '(signed out)');
    return const [];
  }
  final res = await backend.favoriteTracks();
  _logData('favoriteTracks', source: 'live', extra: 'count=${res.length}');
  return res;
});

/// Every album in the library (sorted alphabetically). Used by the
/// Library tab's Albums grid — the previous wiring used
/// `recentlyAddedAlbums` (top-20 newest) so the grid looked permanently
/// underpopulated.
final allAlbumsProvider =
    FutureProvider.autoDispose<List<AfAlbum>>((ref) async {
  final backend = ref.watch(musicBackendProvider);
  if (backend == null) {
    _logData('allAlbums', source: 'demo', extra: '(signed out)');
    return const [];
  }
  final res = await backend.allAlbums();
  _logData('allAlbums', source: 'live', extra: 'count=${res.length}');
  return res;
});

/// Every track in the library (sorted alphabetically). Used by the
/// Library tab's Songs list, which previously used
/// `recentlyPlayedTracks` (filter=IsPlayed, limit=20) and so missed
/// every unplayed song.
final allTracksProvider =
    FutureProvider.autoDispose<List<AfTrack>>((ref) async {
  final backend = ref.watch(musicBackendProvider);
  if (backend == null) {
    _logData('allTracks', source: 'demo', extra: '(signed out)');
    return const [];
  }
  final res = await backend.allTracks();
  _logData('allTracks', source: 'live', extra: 'count=${res.length}');
  return res;
});

/// Playlist + its ordered tracks. Powers the Playlist detail screen.
final playlistDetailProvider = FutureProvider.autoDispose
    .family<({AfPlaylist playlist, List<AfTrack> tracks})?, String>(
        (ref, id) async {
  final backend = ref.watch(musicBackendProvider);
  if (backend == null) {
    _logData('playlistDetail',
        source: 'demo', extra: 'id=$id (signed out)');
    return null;
  }
  final res = await backend.playlist(id);
  _logData('playlistDetail',
      source: 'live',
      extra: 'id=$id tracks=${res?.tracks.length ?? 0}');
  return res;
});

/// Instant Mix — server-side similar-tracks generator keyed on a seed
/// track / album / artist ID. Used to start a "radio" from the currently
/// playing song and to extend the queue with related songs (the feature
/// the user requested).
final instantMixProvider = FutureProvider.autoDispose
    .family<List<AfTrack>, String>((ref, seedId) async {
  final backend = ref.watch(musicBackendProvider);
  if (backend == null) {
    _logData('instantMix',
        source: 'demo', extra: 'seedId=$seedId (signed out)');
    return const <AfTrack>[];
  }
  final res = await backend.instantMix(seedId);
  _logData('instantMix',
      source: 'live', extra: 'seedId=$seedId count=${res.length}');
  return res;
});

/// Albums tagged with a given genre name. Powers the Genre detail screen.
final genreAlbumsProvider = FutureProvider.autoDispose
    .family<List<AfAlbum>, String>((ref, genre) async {
  final backend = ref.watch(musicBackendProvider);
  if (backend == null) {
    _logData('genreAlbums', source: 'demo', extra: 'genre=$genre (signed out)');
    return const [];
  }
  final res = await backend.albumsByGenre(genre);
  _logData('genreAlbums', source: 'live', extra: 'genre=$genre count=${res.length}');
  return res;
});
/// Music genres. Jellyfin returns these without colors so we cycle through
/// Music genres. Jellyfin returns genre images directly. For Subsonic
/// (which doesn't), we cross-reference with the album list to pick a
/// representative cover art per genre — zero extra network requests.
final allGenresProvider =
    FutureProvider.autoDispose<List<AfGenre>>((ref) async {
  final backend = ref.watch(musicBackendProvider);
  if (backend == null) {
    _logData('allGenres', source: 'none', extra: '(signed out)');
    return const [];
  }
  final res = await backend.genres();
  _logData('allGenres', source: 'live', extra: 'count=${res.length}');

  // If all genres already have images (Jellyfin), return as-is.
  if (res.every((g) => g.imageUrl != null)) return res;

  // Subsonic/local path: enrich genres with album artwork by fetching
  // one album per genre. Uses albumsByGenre(limit:1) which is a single
  // lightweight request per genre. Runs in parallel, capped at 10 concurrent.
  final enriched = <AfGenre>[];
  for (final g in res) {
    if (g.imageUrl != null) {
      enriched.add(g);
      continue;
    }
    try {
      final albums = await backend.albumsByGenre(g.name, limit: 1);
      final imageUrl = albums.isNotEmpty ? albums.first.imageUrl : null;
      enriched.add(AfGenre(g.name, g.tint, imageUrl: imageUrl));
    } catch (_) {
      enriched.add(g);
    }
  }
  return enriched;
});

final albumDetailProvider = FutureProvider.autoDispose
    .family<({AfAlbum album, List<AfTrack> tracks})?, String>((ref, id) async {
  // Local mode: parse album name/artist from the ID
  if (id.startsWith('local:album:')) {
    final lib = ref.read(localLibraryProvider);
    final parts = id.substring('local:album:'.length).split(':');
    if (parts.length >= 2) {
      final albumName = parts[0];
      final artistName = parts.sublist(1).join(':');
      final tracks = await lib.tracksByAlbum(albumName, artistName);
      if (tracks.isNotEmpty) {
        final album = AfAlbum(
          id: id,
          name: albumName,
          artistName: artistName,
          trackCount: tracks.length,
          imageUrl: tracks.first.imageUrl,
        );
        return (album: album, tracks: tracks);
      }
    }
    return null;
  }

  final backend = ref.watch(musicBackendProvider);
  if (backend != null) {
    final res = await backend.album(id);
    _logData('albumDetail',
        source: 'live',
        extra: 'id=$id tracks=${res?.tracks.length ?? 0}');
    return res;
  }
  _logData('albumDetail', source: 'none', extra: 'id=$id (no backend)');
  return null;
});

final artistDetailProvider =
    FutureProvider.autoDispose.family<AfArtist?, String>((ref, id) async {
  // Local mode: parse artist name from the ID
  if (id.startsWith('local:artist:')) {
    final name = id.substring('local:artist:'.length);
    return AfArtist(id: id, name: name, albumCount: 0);
  }

  final backend = ref.watch(musicBackendProvider);
  if (backend != null) {
    final res = await backend.artist(id);
    _logData('artistDetail',
        source: 'live', extra: 'id=$id found=${res != null}');
    return res;
  }
  _logData('artistDetail', source: 'none', extra: 'id=$id (no backend)');
  return null;
});

/// Albums credited to a given artist.
final artistAlbumsProvider = FutureProvider.autoDispose
    .family<List<AfAlbum>, String>((ref, artistId) async {
  // Local mode: filter albums by artist name
  if (artistId.startsWith('local:artist:')) {
    final name = artistId.substring('local:artist:'.length);
    final allAlbums = await ref.read(localLibraryProvider).albums();
    return allAlbums.where((a) => a.artistName == name).toList();
  }

  final backend = ref.watch(musicBackendProvider);
  if (backend == null) {
    _logData('artistAlbums', source: 'none', extra: 'artistId=$artistId (no backend)');
    return const [];
  }
  final res = await backend.artistAlbums(artistId);
  _logData('artistAlbums',
      source: 'live', extra: 'artistId=$artistId count=${res.length}');
  return res;
});

/// Top tracks for an artist.
final artistTopTracksProvider = FutureProvider.autoDispose
    .family<List<AfTrack>, String>((ref, artistId) async {
  // Local mode: get tracks by artist name
  if (artistId.startsWith('local:artist:')) {
    final name = artistId.substring('local:artist:'.length);
    final tracks = await ref.read(localLibraryProvider).tracksByArtist(name);
    return tracks.take(10).toList();
  }

  final backend = ref.watch(musicBackendProvider);
  if (backend == null) {
    _logData('artistTopTracks', source: 'none', extra: 'artistId=$artistId (no backend)');
    return const [];
  }
  final res = await backend.artistTopTracks(artistId, limit: 5);
  _logData('artistTopTracks',
      source: 'live', extra: 'artistId=$artistId count=${res.length}');
  return res;
});

/// ─────────────────────────────────────────────────────────────────────────
/// Search & lyrics (live)
/// ─────────────────────────────────────────────────────────────────────────

/// Server-side search results. Hits `/Users/{id}/Items?searchTerm=`
/// (NOT `/Search/Hints` — see CLAUDE.md §10 footgun #3) and bucketises
/// the BaseItemDto stream into tracks/albums/artists for the screen.
typedef SearchResults = ({
  List<AfTrack> tracks,
  List<AfAlbum> albums,
  List<AfArtist> artists,
  List<AfPlaylist> playlists,
});

final searchProvider = FutureProvider.autoDispose
    .family<SearchResults, String>((ref, raw) async {
  final query = raw.trim();
  if (query.isEmpty) {
    return (
      tracks: const <AfTrack>[],
      albums: const <AfAlbum>[],
      artists: const <AfArtist>[],
      playlists: const <AfPlaylist>[],
    );
  }

  // Local mode: search the SQLite DB directly.
  final mode = ref.watch(appModeProvider);
  if (mode == AppMode.local) {
    final lib = ref.read(localLibraryProvider);
    final tracks = await lib.search(query);
    _logData('search', source: 'local', extra: 'query="$query" tracks=${tracks.length}');
    return (
      tracks: tracks,
      albums: const <AfAlbum>[],
      artists: const <AfArtist>[],
      playlists: const <AfPlaylist>[],
    );
  }

  final backend = ref.watch(musicBackendProvider);
  if (backend == null) {
    _logData('search', source: 'none', extra: 'query="$query" (no backend)');
    return (
      tracks: const <AfTrack>[],
      albums: const <AfAlbum>[],
      artists: const <AfArtist>[],
      playlists: const <AfPlaylist>[],
    );
  }
  final res = await backend.search(query);
  _logData('search',
      source: 'live',
      extra: 'query="$query" tracks=${res.tracks.length} '
          'albums=${res.albums.length} artists=${res.artists.length} '
          'playlists=${res.playlists.length}');
  return (
    tracks: res.tracks,
    albums: res.albums,
    artists: res.artists,
    playlists: res.playlists,
  );
});

/// Time-synced lyrics for a track. Returns `null` when the server has
/// none and the UI should render the "no lyrics" empty state. Parses
/// the raw LRC payload from `/Audio/{id}/Lyrics` into our [Lrc] type so
/// the screen doesn't have to know about LRC syntax.
final lyricsProvider =
    FutureProvider.autoDispose.family<Lrc?, String>((ref, trackId) async {
  final backend = ref.watch(musicBackendProvider);
  if (backend == null) {
    _logData('lyrics',
        source: 'demo', extra: 'trackId=$trackId (signed out)');
    return null;
  }
  final raw = await backend.lyrics(trackId);
  if (raw == null || raw.isEmpty) {
    _logData('lyrics',
        source: 'live', extra: 'trackId=$trackId result=none');
    return null;
  }
  final parsed = parseLrc(raw);
  _logData('lyrics',
      source: 'live',
      extra: 'trackId=$trackId lines=${parsed.lines.length}');
  return parsed;
});

/// ─────────────────────────────────────────────────────────────────────────
/// Settings
/// ─────────────────────────────────────────────────────────────────────────

final showNavLabelsProvider = StateProvider<bool>((ref) => false);

final reducedMotionProvider = Provider.autoDispose<bool>((ref) {
  // Read the platform accessibility setting so animations can be toned down
  // for users who prefer reduced motion. WidgetsBinding exposes this without
  // needing a BuildContext, making it safe to use in non-widget code.
  try {
    return WidgetsBinding.instance.accessibilityFeatures.reduceMotion;
  } catch (_) {
    return false;
  }
});

/// ─────────────────────────────────────────────────────────────────────────
/// Server discovery results (used by the onboarding flow)
/// ─────────────────────────────────────────────────────────────────────────

final discoveredServersProvider =
    StateProvider<List<JellyfinServer>>((ref) => const []);
