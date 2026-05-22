import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/jellyfin/models/items.dart';
import '../utils/log.dart';
import 'music_backend_providers.dart';

void _logData(String feature, {required String source, String? extra}) {
  final detail = extra == null || extra.isEmpty ? '' : ' $extra';
  afLog('data', '$feature source=$source$detail');
}

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

final playlistTrackIdsProvider =
    FutureProvider.autoDispose<Set<String>>((ref) async {
  final backend = ref.watch(musicBackendProvider);
  if (backend == null) return <String>{};

  final playlists = await ref.watch(allPlaylistsProvider.future);
  final ids = <String>{};

  final results = await Future.wait(
    playlists.map((pl) => backend.playlist(pl.id)),
    eagerError: false,
  );
  for (var i = 0; i < results.length; i++) {
    final detail = results[i];
    if (detail != null) {
      for (final t in detail.tracks) {
        ids.add(t.id);
      }
    } else {
      afLog('data', 'playlist track fetch returned null id=${playlists[i].id}');
    }
  }

  return ids;
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
