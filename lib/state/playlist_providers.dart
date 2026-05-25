import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/jellyfin/models/items.dart';
import '../core/smart_playlist/smart_playlist_db.dart';
import '../core/smart_playlist/smart_playlist_engine.dart';
import '../core/smart_playlist/smart_playlist_model.dart';
import '../utils/log.dart';
import 'app_mode_providers.dart';
import 'library_providers.dart';
import 'local_library_providers.dart';
import 'music_backend_providers.dart';

void _logData(String feature, {required String source, String? extra}) {
  final detail = extra == null || extra.isEmpty ? '' : ' $extra';
  afLog('data', '$feature source=$source$detail');
}

final selectedLibraryIdsProvider = StateProvider<Set<String>?>((ref) => null);

final smartPlaylistDbProvider = Provider<SmartPlaylistDb>((ref) {
  final appDb = ref.watch(appDatabaseProvider);
  return SmartPlaylistDb(database: appDb);
});

final smartPlaylistsProvider = FutureProvider.autoDispose<List<SmartPlaylist>>((
  ref,
) {
  final db = ref.watch(smartPlaylistDbProvider);
  return db.getAll();
});

final smartPlaylistTracksProvider = FutureProvider.autoDispose
    .family<List<AfTrack>, String>((ref, playlistId) async {
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

final playlistDetailProvider = FutureProvider.autoDispose
    .family<({AfPlaylist playlist, List<AfTrack> tracks})?, String>((
      ref,
      id,
    ) async {
      final backend = ref.watch(musicBackendProvider);
      if (backend == null) {
        _logData(
          'playlistDetail',
          source: 'demo',
          extra: 'id=$id (signed out)',
        );
        return null;
      }
      final res = await backend.playlist(id);
      _logData(
        'playlistDetail',
        source: 'live',
        extra: 'id=$id tracks=${res?.tracks.length ?? 0}',
      );
      return res;
    });

final instantMixProvider = FutureProvider.autoDispose
    .family<List<AfTrack>, String>((ref, seedId) async {
      final backend = ref.watch(musicBackendProvider);
      if (backend == null) {
        _logData(
          'instantMix',
          source: 'demo',
          extra: 'seedId=$seedId (signed out)',
        );
        return const <AfTrack>[];
      }
      final res = await backend.instantMix(seedId);
      _logData(
        'instantMix',
        source: 'live',
        extra: 'seedId=$seedId count=${res.length}',
      );
      return res;
    });

final genreAlbumsProvider = FutureProvider.autoDispose
    .family<List<AfAlbum>, String>((ref, genre) async {
      final backend = ref.watch(musicBackendProvider);
      if (backend == null) {
        _logData(
          'genreAlbums',
          source: 'demo',
          extra: 'genre=$genre (signed out)',
        );
        return const <AfAlbum>[];
      }
      final res = await backend.albumsByGenre(genre);
      _logData(
        'genreAlbums',
        source: 'live',
        extra: 'genre=$genre count=${res.length}',
      );
      return res;
    });
