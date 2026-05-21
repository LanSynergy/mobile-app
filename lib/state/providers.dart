import 'dart:async' show Timer, unawaited;

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show Loop, FftFrame, MpvPlayerError;

import '../core/audio/jellyfin_playback_reporter.dart';
import '../core/audio/live_update_service.dart';
import '../core/audio/player_service.dart';
import '../core/audio/player_settings_store.dart';
import '../core/audio/spectral_extractor.dart';
import '../core/backend/music_backend.dart';
import '../core/jellyfin/auth_storage.dart';
import '../core/jellyfin/client.dart';
import '../core/jellyfin/models/items.dart';
import '../core/jellyfin/models/server.dart';
import '../core/local/local_backend.dart';
import '../core/local/local_library.dart';
import '../core/lyrics/lrc_parser.dart';
import '../core/search/search_history_store.dart';
import '../core/smart_playlist/smart_playlist_db.dart';
import '../core/smart_playlist/smart_playlist_engine.dart';
import '../core/smart_playlist/smart_playlist_model.dart';
import '../core/subsonic/client.dart';
import '../design_tokens/colors.dart';
import '../utils/log.dart';

// ─────────────────────────────────────────────────────────────────────────────
// App Mode
// ─────────────────────────────────────────────────────────────────────────────

enum AppMode { server, local }

final appModeProvider = StateProvider<AppMode?>((ref) => null);

final localScanProgressProvider =
    StateProvider<({int completed, int total})?>((ref) => null);

// ─────────────────────────────────────────────────────────────────────────────
// Local library providers
// ─────────────────────────────────────────────────────────────────────────────

final localLibraryProvider = Provider<LocalLibrary>((ref) {
  final lib = LocalLibrary();
  ref.onDispose(() => lib.close());
  return lib;
});

final localAlbumsProvider = FutureProvider.autoDispose<List<AfAlbum>>((ref) {
  final lib = ref.watch(localLibraryProvider);
  return lib.albums();
});

final localArtistsProvider = FutureProvider.autoDispose<List<AfArtist>>((ref) {
  final lib = ref.watch(localLibraryProvider);
  return lib.artists();
});

final localTracksProvider = FutureProvider.autoDispose<List<AfTrack>>((ref) {
  final lib = ref.watch(localLibraryProvider);
  return lib.tracks();
});

final localGenresProvider = FutureProvider.autoDispose<List<AfGenre>>((ref) {
  final lib = ref.watch(localLibraryProvider);
  return lib.genres();
});

// ─────────────────────────────────────────────────────────────────────────────
// Smart Playlists
// ─────────────────────────────────────────────────────────────────────────────

final selectedLibraryIdsProvider = StateProvider<Set<String>?>((ref) => null);

final smartPlaylistDbProvider = Provider<SmartPlaylistDb>((ref) {
  final db = SmartPlaylistDb();
  ref.onDispose(() => db.close());
  return db;
});

final smartPlaylistsProvider =
    FutureProvider.autoDispose<List<SmartPlaylist>>((ref) {
  final db = ref.watch(smartPlaylistDbProvider);
  return db.getAll();
});

final smartPlaylistTracksProvider =
    FutureProvider.autoDispose.family<List<AfTrack>, String>((ref, playlistId) async {
  final db = ref.read(smartPlaylistDbProvider);
  final playlist = await db.getById(playlistId);
  if (playlist == null) return const <AfTrack>[];

  final engine = SmartPlaylistEngine();
  final mode = ref.read(appModeProvider);

  if (mode == AppMode.local) {
    final localLib = ref.read(localLibraryProvider);
    return engine.resolveLocal(playlist, localLib.db);
  }

  final allTracks = await ref.read(allTracksProvider.future);
  return engine.resolveFromList(playlist, allTracks);
});

void _logData(String feature, {required String source, String? extra}) {
  final detail = extra == null || extra.isEmpty ? '' : ' $extra';
  afLog('data', '$feature source=$source$detail');
}

// ─────────────────────────────────────────────────────────────────────────────
// Auth
// ─────────────────────────────────────────────────────────────────────────────

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
    await _storage.save(auth);
    state = auth;
  }

  Future<void> clear() async {
    await _storage.clear();
    state = null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Music backend
// ─────────────────────────────────────────────────────────────────────────────

final musicBackendProvider = Provider.autoDispose<MusicBackend?>((ref) {
  final auth = ref.watch(authProvider);
  if (auth == null) {
    // Local mode is no longer a degraded sub-mode — it has its own
    // backend that implements the same MusicBackend contract over
    // the on-device SQLite store. This lets favorites, playlists and
    // "Save to playlist" work in either mode without per-call
    // “if (backend == null)” branches scattered through the UI.
    if (ref.watch(appModeProvider) == AppMode.local) {
      final lib = ref.watch(localLibraryProvider);
      _logData('musicBackend', source: 'live', extra: 'type=local');
      return LocalBackend(library: lib, db: lib.db);
    }
    _logData('musicBackend', source: 'demo', extra: '(signed out)');
    return null;
  }

  _logData(
    'musicBackend',
    source: 'live',
    extra: 'type=${auth.serverType.name} '
        'server=${kReleaseMode ? '<redacted>' : auth.server.baseUrl} '
        'user=${kReleaseMode ? '<redacted>' : auth.userName}',
  );

  final clientVersion = ref.watch(aetherfinVersionProvider);

  final MusicBackend client;
  switch (auth.serverType) {
    case ServerType.subsonic:
      client = SubsonicClient(
        server: auth.server,
        username: auth.userName,
        password: auth.accessToken,
        clientVersion: clientVersion,
      );
    case ServerType.jellyfin:
      client = JellyfinClient(
        server: auth.server,
        deviceId: ref.watch(deviceIdProvider),
        accessToken: auth.accessToken,
        userId: auth.userId,
        clientVersion: clientVersion,
      );
    case ServerType.local:
      // Local mode normally arrives via the `auth == null` branch
      // above. Persisted auth shouldn't be tagged as local, but if
      // some future migration ever stores one, fall back to the
      // on-device backend instead of throwing.
      final lib = ref.watch(localLibraryProvider);
      return LocalBackend(library: lib, db: lib.db);
  }

  ref.onDispose(client.close);
  return client;
});

final jellyfinClientProvider = Provider<JellyfinClient?>((ref) {
  final backend = ref.watch(musicBackendProvider);
  if (backend is JellyfinClient) return backend;
  return null;
});

// ─────────────────────────────────────────────────────────────────────────────
// Audio player
// ─────────────────────────────────────────────────────────────────────────────

void wirePlayerService(Ref ref, AfPlayerService svc) {
  svc.onTrackChanged = (track) {
    ref.read(currentTrackProvider.notifier).state = track;
    ref.read(positionStreamProvider.notifier).state = Duration.zero;
    // Reset duration to track's known duration or zero.
    // This fixes: (1) duration persisting after song ends, (2) duration
    // starting from previous song's length when queue advances.
    ref.read(durationStreamProvider.notifier).state =
        track.duration > Duration.zero ? track.duration : Duration.zero;
    ref.read(abLoopAProvider.notifier).state = null;
    ref.read(abLoopBProvider.notifier).state = null;
  };

  _startPositionPolling(ref, svc);

  svc.errorStream.listen((error) {
    ref.read(playbackErrorProvider.notifier).state = error;
  });

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
    return PlayerSettingsStore.applyPersisted(svc);
  }));

  ref.listen(authProvider, (prev, next) {
    if (prev != null && next == null) {
      reporter?.requestStopOnDispose();
      unawaited(reporter?.dispose());
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

final playerQueueProvider = StreamProvider.autoDispose<List<AfTrack>>((ref) {
  final svc = ref.watch(playerServiceProvider);
  return Stream<List<AfTrack>>.multi((controller) {
    controller.add(svc.currentQueue);
    final sub = svc.queueStream.listen(controller.add);
    controller.onCancel = sub.cancel;
  });
});

final positionStreamProvider = StateProvider<Duration>((ref) => Duration.zero);
final durationStreamProvider = StateProvider<Duration>((ref) => Duration.zero);
final playbackErrorProvider = StateProvider<MpvPlayerError?>((ref) => null);
final abLoopAProvider = StateProvider<Duration?>((ref) => null);
final abLoopBProvider = StateProvider<Duration?>((ref) => null);

/// Bridges [AfPlayerService] position/duration streams into Riverpod
/// providers and handles EOF state reset.
///
/// Position polling and extrapolation happen exclusively inside
/// [AfPlayerService._pollAndEmitPosition] (200 ms timer). This function
/// only subscribes to the service's streams and forwards them, plus
/// polls raw duration once per 250 ms so the UI gets mpv's authoritative
/// duration even when `stream.duration` stalls.
void _startPositionPolling(Ref ref, AfPlayerService svc) {
  var disposed = false;

  ref.onDispose(() {
    disposed = true;
  });

  // Forward service position → provider (no duplicate polling here).
  svc.positionStream.listen((pos) {
    ref.read(positionStreamProvider.notifier).state = pos;
  });

  // Forward service duration → provider.
  svc.durationStream.listen((dur) {
    if (dur > Duration.zero) {
      ref.read(durationStreamProvider.notifier).state = dur;
    }
  });

  // Poll raw duration and handle EOF reset. The service's own poller
  // handles position; we only need duration + completion state here.
  final timer = Timer.periodic(const Duration(milliseconds: 250), (_) async {
    if (disposed) return;

    final rawDur = await svc.getRawDuration();
    if (disposed) return;

    // When track completes and playback stops, reset duration & position to zero.
    // mpv keeps reporting the old duration/position after EOF, so we must
    // explicitly clear them based on completion state.
    // Guard: only reset if we are actually on the last track. This prevents
    // false resets on Samsung One UI where `isCompleted` can flicker true
    // during audio pipeline pauses/nudges.
    final isLastTrack = svc.currentQueue.isNotEmpty &&
        svc.currentTrack != null &&
        svc.currentQueue.last.id == svc.currentTrack!.id;
    if (svc.isCompleted && !svc.isPlaying && svc.isUserPaused && isLastTrack) {
      try {
        ref.read(durationStreamProvider.notifier).state = Duration.zero;
        ref.read(positionStreamProvider.notifier).state = Duration.zero;
      } catch (_) {}
      return;
    }

    if (rawDur > Duration.zero) {
      try {
        ref.read(durationStreamProvider.notifier).state = rawDur;
      } catch (_) {}
    } else {
      final track = ref.read(currentTrackProvider);
      if (track != null && track.duration > Duration.zero) {
        try {
          ref.read(durationStreamProvider.notifier).state = track.duration;
        } catch (_) {}
      }
    }
  });

  ref.onDispose(timer.cancel);
}

final playingStreamProvider = StreamProvider.autoDispose<bool>((ref) {
  final svc = ref.watch(playerServiceProvider);
  return svc.playingStream;
});

final shuffleModeProvider = StreamProvider.autoDispose<bool>((ref) {
  final svc = ref.watch(playerServiceProvider);
  return Stream<bool>.multi((controller) {
    controller.add(svc.isShuffleEnabled);
    final sub = svc.shuffleModeStream.listen(controller.add);
    controller.onCancel = sub.cancel;
  });
});

final loopModeProvider = StreamProvider.autoDispose<Loop>((ref) {
  final svc = ref.watch(playerServiceProvider);
  return Stream<Loop>.multi((controller) {
    controller.add(svc.loopMode);
    final sub = svc.loopModeStream.listen(controller.add);
    controller.onCancel = sub.cancel;
  });
});

final playbackSpeedProvider = StreamProvider.autoDispose<double>((ref) {
  final svc = ref.watch(playerServiceProvider);
  return Stream<double>.multi((controller) {
    controller.add(svc.speed);
    final sub = svc.speedStream.listen(controller.add);
    controller.onCancel = sub.cancel;
  });
});

final fftSpectrumProvider = StreamProvider.autoDispose<FftFrame>((ref) {
  final svc = ref.watch(playerServiceProvider);
  return svc.spectrumStream.cast<FftFrame>();
});

final currentTrackProvider = StateProvider<AfTrack?>((ref) => null);

/// Track-level favorite overrides written immediately on heart toggle.
///
/// Detail providers ([albumDetailProvider], [playlistDetailProvider],
/// `artistTopTracks`, [searchProvider], etc.) each cache their own track
/// list. When the user toggles favorite from one screen and navigates
/// to another that has the same track cached, the cached
/// `AfTrack.isFavorite` is stale — so the heart icon shows the
/// pre-toggle state on every screen except the one where the toggle
/// happened. Invalidating every detail provider on every favorite
/// toggle would force a full re-fetch of any actively-watched album /
/// playlist / search-results list just to flip a single icon, which is
/// wasteful (the user is paying server round-trips for one bit of
/// state).
///
/// Instead, this map is the authoritative "latest-known" favorite
/// state per track id. UI that renders a track heart
/// ([FavoriteHeartButton], Now Playing's icon) consults this map first
/// and only falls back to the track model's own `isFavorite` field if
/// no override is present. Writes happen on the optimistic flip (so
/// every heart for that track id flips in lock-step) and on rollback
/// after a failed backend call.
///
/// Not autoDispose: lives for the session so an override set early in
/// the app's life is still respected on screens visited much later.
/// The map is bounded by the number of distinct tracks the user has
/// favorited this session, so unbounded growth in practice isn't a
/// concern.
final trackFavoriteOverridesProvider =
    StateProvider<Map<String, bool>>((ref) => const {});

final favoriteToggleProvider = Provider<Future<void> Function(AfTrack)>((ref) {
  return (AfTrack track) async {
    final backend = ref.read(musicBackendProvider);
    // `trackFavoriteOverridesProvider` is the latest-known state — fall
    // back to the model only when no override is present.
    final overrides = ref.read(trackFavoriteOverridesProvider);
    final wasFavorite = overrides[track.id] ?? track.isFavorite;
    final next = !wasFavorite;
    final updated = track.copyWith(isFavorite: next);
    final current = ref.read(currentTrackProvider);

    if (current?.id == track.id) {
      ref.read(currentTrackProvider.notifier).state = updated;
    }
    ref.read(trackFavoriteOverridesProvider.notifier).update(
          (s) => {...s, track.id: next},
        );

    if (backend == null) {
      _logData('favoriteToggle',
          source: 'demo', extra: '(signed out) id=${track.id} isFavorite=$next');
      return;
    }

    try {
      await backend.setFavorite(track.id, next);
      _logData('favoriteToggle',
          source: 'live', extra: 'id=${track.id} isFavorite=$next');
      ref.invalidate(favoriteAlbumsProvider);
      ref.invalidate(favoriteTracksProvider);
      ref.invalidate(recentlyPlayedTracksProvider);
    } catch (e, stack) {
      afLog('error', 'favoriteToggle failed', error: e, stackTrace: stack);
      if (current?.id == track.id) {
        ref.read(currentTrackProvider.notifier).state = track;
      }
      ref.read(trackFavoriteOverridesProvider.notifier).update(
            (s) => {...s, track.id: wasFavorite},
          );
      rethrow;
    }
  };
});

final hasActivePlaybackProvider = Provider<bool>((ref) {
  return ref.watch(currentTrackProvider) != null;
});

// ─────────────────────────────────────────────────────────────────────────────
// Spectral accent
// ─────────────────────────────────────────────────────────────────────────────

final spectralExtractorProvider = Provider<SpectralExtractor>((ref) {
  return SpectralExtractor();
});

final currentSpectralProvider = Provider<Spectral>((ref) {
  final track = ref.watch(currentTrackProvider);
  final imageUrl = track?.imageUrl;
  final async = ref.watch(spectralFromUrlProvider(imageUrl));
  return async.maybeWhen(data: (s) => s, orElse: () => Spectral.fallback);
});

final spectralFromUrlProvider =
    FutureProvider.autoDispose.family<Spectral, String?>((ref, imageUrl) async {
  if (imageUrl == null) return Spectral.fallback;
  final backend = ref.watch(musicBackendProvider);
  final headers = backend?.authHeaders;
  try {
    return await ref
        .watch(spectralExtractorProvider)
        .fromImageUrl(imageUrl, headers: headers);
  } catch (e) {
    afLog('spectral', 'spectral extraction failed', error: e);
    return Spectral.fallback;
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// Library
// ─────────────────────────────────────────────────────────────────────────────

final recentlyAddedAlbumsProvider =
    FutureProvider.autoDispose<List<AfAlbum>>((ref) async {
  final backend = ref.watch(musicBackendProvider);
  if (backend == null) {
    _logData('recentlyAddedAlbums', source: 'demo', extra: '(signed out)');
    return const <AfAlbum>[];
  }
  final res = await backend.recentlyAddedAlbums();
  _logData('recentlyAddedAlbums', source: 'live', extra: 'count=${res.length}');
  return res;
});

final recentlyPlayedTracksProvider =
    FutureProvider.autoDispose<List<AfTrack>>((ref) async {
  final backend = ref.watch(musicBackendProvider);
  if (backend == null) {
    _logData('recentlyPlayedTracks', source: 'demo', extra: '(signed out)');
    return const <AfTrack>[];
  }
  final res = await backend.recentlyPlayed();
  _logData('recentlyPlayedTracks', source: 'live', extra: 'count=${res.length}');
  return res;
});

final allArtistsProvider = FutureProvider.autoDispose<List<AfArtist>>((ref) async {
  final backend = ref.watch(musicBackendProvider);
  if (backend == null) {
    _logData('allArtists', source: 'demo', extra: '(signed out)');
    return const <AfArtist>[];
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
    return const <AfPlaylist>[];
  }
  final res = await backend.playlists();
  _logData('allPlaylists', source: 'live', extra: 'count=${res.length}');
  return res;
});

final savedTrackIdsProvider = StateProvider<Set<String>>((ref) => <String>{});

// ─────────────────────────────────────────────────────────────────────────────
// Search history
// ─────────────────────────────────────────────────────────────────────────────

/// Most-recently-used list of search queries, persisted across runs.
///
/// The notifier auto-loads from disk on first read and writes through
/// on every mutation. The in-memory state is the source of truth for
/// the UI, so reads after a mutation are synchronous — no extra
/// awaitable hop between "committed query" and "chip on screen."
class SearchHistoryNotifier extends StateNotifier<List<String>> {
  SearchHistoryNotifier() : super(const <String>[]) {
    _hydrate();
  }

  Future<void> _hydrate() async {
    final saved = await SearchHistoryStore.load();
    if (mounted) state = saved;
  }

  Future<void> push(String query) async {
    final updated = await SearchHistoryStore.push(query);
    if (mounted) state = updated;
  }

  Future<void> remove(String query) async {
    final updated = await SearchHistoryStore.remove(query);
    if (mounted) state = updated;
  }

  Future<void> clear() async {
    await SearchHistoryStore.clear();
    if (mounted) state = const <String>[];
  }
}

final searchHistoryProvider =
    StateNotifierProvider<SearchHistoryNotifier, List<String>>(
  (ref) => SearchHistoryNotifier(),
);

final playlistTrackIdsProvider =
    FutureProvider.autoDispose<Set<String>>((ref) async {
  final backend = ref.watch(musicBackendProvider);
  if (backend == null) return <String>{};

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

final favoriteAlbumsProvider =
    FutureProvider.autoDispose<List<AfAlbum>>((ref) async {
  final backend = ref.watch(musicBackendProvider);
  if (backend == null) {
    _logData('favoriteAlbums', source: 'demo', extra: '(signed out)');
    return const <AfAlbum>[];
  }
  final res = await backend.favoriteAlbums();
  _logData('favoriteAlbums', source: 'live', extra: 'count=${res.length}');
  return res;
});

final favoriteTracksProvider =
    FutureProvider.autoDispose<List<AfTrack>>((ref) async {
  final backend = ref.watch(musicBackendProvider);
  if (backend == null) {
    _logData('favoriteTracks', source: 'demo', extra: '(signed out)');
    return const <AfTrack>[];
  }
  final res = await backend.favoriteTracks();
  _logData('favoriteTracks', source: 'live', extra: 'count=${res.length}');
  return res;
});

final allAlbumsProvider = FutureProvider.autoDispose<List<AfAlbum>>((ref) async {
  final backend = ref.watch(musicBackendProvider);
  if (backend == null) {
    _logData('allAlbums', source: 'demo', extra: '(signed out)');
    return const <AfAlbum>[];
  }
  final res = await backend.allAlbums();
  _logData('allAlbums', source: 'live', extra: 'count=${res.length}');
  return res;
});

final allTracksProvider = FutureProvider.autoDispose<List<AfTrack>>((ref) async {
  final backend = ref.watch(musicBackendProvider);
  if (backend == null) {
    _logData('allTracks', source: 'demo', extra: '(signed out)');
    return const <AfTrack>[];
  }
  final res = await backend.allTracks();
  _logData('allTracks', source: 'live', extra: 'count=${res.length}');
  return res;
});

final playlistDetailProvider = FutureProvider.autoDispose
    .family<({AfPlaylist playlist, List<AfTrack> tracks})?, String>(
        (ref, id) async {
  final backend = ref.watch(musicBackendProvider);
  if (backend == null) {
    _logData('playlistDetail', source: 'demo', extra: 'id=$id (signed out)');
    return null;
  }
  final res = await backend.playlist(id);
  _logData('playlistDetail',
      source: 'live', extra: 'id=$id tracks=${res?.tracks.length ?? 0}');
  return res;
});

final instantMixProvider =
    FutureProvider.autoDispose.family<List<AfTrack>, String>((ref, seedId) async {
  final backend = ref.watch(musicBackendProvider);
  if (backend == null) {
    _logData('instantMix', source: 'demo', extra: 'seedId=$seedId (signed out)');
    return const <AfTrack>[];
  }
  final res = await backend.instantMix(seedId);
  _logData('instantMix', source: 'live', extra: 'seedId=$seedId count=${res.length}');
  return res;
});

final genreAlbumsProvider =
    FutureProvider.autoDispose.family<List<AfAlbum>, String>((ref, genre) async {
  final backend = ref.watch(musicBackendProvider);
  if (backend == null) {
    _logData('genreAlbums', source: 'demo', extra: 'genre=$genre (signed out)');
    return const <AfAlbum>[];
  }
  final res = await backend.albumsByGenre(genre);
  _logData('genreAlbums', source: 'live', extra: 'genre=$genre count=${res.length}');
  return res;
});

final allGenresProvider = FutureProvider.autoDispose<List<AfGenre>>((ref) async {
  final backend = ref.watch(musicBackendProvider);
  if (backend == null) {
    _logData('allGenres', source: 'none', extra: '(signed out)');
    return const <AfGenre>[];
  }

  final res = await backend.genres();
  _logData('allGenres', source: 'live', extra: 'count=${res.length}');

  if (res.every((g) => g.imageUrl != null)) return res;

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
  if (id.startsWith('local:album:')) {
    final lib = ref.read(localLibraryProvider);
    final rest = id.substring('local:album:'.length);
    // Split on the LAST colon — album names commonly contain colons
    // ("Greatest Hits: The Best") while artist names rarely do.
    final sep = rest.lastIndexOf(':');
    if (sep < 0) return null;
    final albumName = rest.substring(0, sep);
    final artistName = rest.substring(sep + 1);
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
    return null;
  }

  final backend = ref.watch(musicBackendProvider);
  if (backend != null) {
    final res = await backend.album(id);
    _logData('albumDetail',
        source: 'live', extra: 'id=$id tracks=${res?.tracks.length ?? 0}');
    return res;
  }

  _logData('albumDetail', source: 'none', extra: 'id=$id (no backend)');
  return null;
});

/// Full per-track details (file size, container, channels, sample rate,
/// bit depth, bitrate, path, genres, play count). Used by the "Show
/// details" bottom sheet on track rows and the Now Playing "More" menu.
///
/// Source selection mirrors the rest of the data layer:
/// `content://` / `local:` ids resolve through [localLibraryProvider]
/// (SQLite tag cache); everything else hits the active server backend.
final trackDetailsProvider =
    FutureProvider.autoDispose.family<AfTrackDetails?, String>((ref, id) async {
  if (id.startsWith('local:') || id.startsWith('content://')) {
    final lib = ref.read(localLibraryProvider);
    final res = await lib.trackDetails(id);
    _logData('trackDetails',
        source: 'local',
        extra: 'id=$id container=${res?.container} size=${res?.sizeBytes}');
    return res;
  }

  final backend = ref.watch(musicBackendProvider);
  if (backend != null) {
    final res = await backend.trackDetails(id);
    _logData('trackDetails',
        source: 'live',
        extra: 'id=$id container=${res?.container} size=${res?.sizeBytes}');
    return res;
  }

  _logData('trackDetails', source: 'none', extra: 'id=$id (no backend)');
  return null;
});

final artistDetailProvider =
    FutureProvider.autoDispose.family<AfArtist?, String>((ref, id) async {
  if (id.startsWith('local:artist:')) {
    final name = id.substring('local:artist:'.length);
    return AfArtist(id: id, name: name, albumCount: 0);
  }

  final backend = ref.watch(musicBackendProvider);
  if (backend != null) {
    final res = await backend.artist(id);
    _logData('artistDetail', source: 'live', extra: 'id=$id found=${res != null}');
    return res;
  }

  _logData('artistDetail', source: 'none', extra: 'id=$id (no backend)');
  return null;
});

final artistAlbumsProvider =
    FutureProvider.autoDispose.family<List<AfAlbum>, String>((ref, artistId) async {
  if (artistId.startsWith('local:artist:')) {
    final name = artistId.substring('local:artist:'.length);
    final allAlbums = await ref.read(localLibraryProvider).albums();
    return allAlbums.where((a) => a.artistName == name).toList();
  }

  final backend = ref.watch(musicBackendProvider);
  if (backend == null) {
    _logData('artistAlbums', source: 'none', extra: 'artistId=$artistId (no backend)');
    return const <AfAlbum>[];
  }

  final res = await backend.artistAlbums(artistId);
  _logData('artistAlbums', source: 'live', extra: 'artistId=$artistId count=${res.length}');
  return res;
});

final artistTopTracksProvider =
    FutureProvider.autoDispose.family<List<AfTrack>, String>((ref, artistId) async {
  if (artistId.startsWith('local:artist:')) {
    final name = artistId.substring('local:artist:'.length);
    final tracks = await ref.read(localLibraryProvider).tracksByArtist(name);
    return tracks.take(10).toList();
  }

  final backend = ref.watch(musicBackendProvider);
  if (backend == null) {
    _logData('artistTopTracks',
        source: 'none', extra: 'artistId=$artistId (no backend)');
    return const <AfTrack>[];
  }

  final res = await backend.artistTopTracks(artistId, limit: 5);
  _logData('artistTopTracks',
      source: 'live', extra: 'artistId=$artistId count=${res.length}');
  return res;
});

// ─────────────────────────────────────────────────────────────────────────────
// Search & lyrics
// ─────────────────────────────────────────────────────────────────────────────

typedef SearchResults = ({
  List<AfTrack> tracks,
  List<AfAlbum> albums,
  List<AfArtist> artists,
  List<AfPlaylist> playlists,
});

final searchProvider =
    FutureProvider.autoDispose.family<SearchResults, String>((ref, raw) async {
  final query = raw.trim();
  if (query.isEmpty) {
    return (
      tracks: const <AfTrack>[],
      albums: const <AfAlbum>[],
      artists: const <AfArtist>[],
      playlists: const <AfPlaylist>[],
    );
  }

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
  _logData(
    'search',
    source: 'live',
    extra: 'query="$query" tracks=${res.tracks.length} '
        'albums=${res.albums.length} artists=${res.artists.length} '
        'playlists=${res.playlists.length}',
  );
  return (
    tracks: res.tracks,
    albums: res.albums,
    artists: res.artists,
    playlists: res.playlists,
  );
});

final lyricsProvider = FutureProvider.autoDispose.family<Lrc?, String>((ref, trackId) async {
  final backend = ref.watch(musicBackendProvider);
  if (backend == null) {
    _logData('lyrics', source: 'demo', extra: 'trackId=$trackId (signed out)');
    return null;
  }

  final raw = await backend.lyrics(trackId);
  if (raw == null || raw.isEmpty) {
    _logData('lyrics', source: 'live', extra: 'trackId=$trackId result=none');
    return null;
  }

  final parsed = parseLrc(raw);
  _logData('lyrics', source: 'live', extra: 'trackId=$trackId lines=${parsed.lines.length}');
  return parsed;
});

// ─────────────────────────────────────────────────────────────────────────────
// Settings
// ─────────────────────────────────────────────────────────────────────────────

final reducedMotionProvider = Provider.autoDispose<bool>((ref) {
  try {
    return WidgetsBinding.instance.accessibilityFeatures.reduceMotion;
  } catch (_) {
    return false;
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// Server discovery results (used by the onboarding flow)
// ─────────────────────────────────────────────────────────────────────────────

final discoveredServersProvider = StateProvider<List<JellyfinServer>>((ref) => const <JellyfinServer>[]);

// ─────────────────────────────────────────────────────────────────────────────
// Appearance
// ─────────────────────────────────────────────────────────────────────────────

final artworkPulseEnabledProvider = StateProvider<bool>((ref) => true);
