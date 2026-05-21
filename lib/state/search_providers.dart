import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/jellyfin/models/items.dart';
import '../core/lyrics/lrc_parser.dart';
import '../utils/log.dart';
import 'app_mode_providers.dart';
import 'local_library_providers.dart';
import 'music_backend_providers.dart';

void _logData(String feature, {required String source, String? extra}) {
  final detail = extra == null || extra.isEmpty ? '' : ' $extra';
  afLog('data', '$feature source=$source$detail');
}

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
