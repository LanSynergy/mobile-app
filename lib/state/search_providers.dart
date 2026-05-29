import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../core/jellyfin/models/items.dart';
import '../core/lyrics/lrc_parser.dart';
import '../core/lyrics/lrclib_client.dart';
import '../utils/log.dart';
import 'app_mode_providers.dart';
import 'detail_providers.dart';
import 'local_library_providers.dart';
import 'music_backend_providers.dart';
import 'player_providers.dart';

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

final searchProvider = FutureProvider.autoDispose.family<SearchResults, String>(
  (ref, raw) async {
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
      _logData(
        'search',
        source: 'local',
        extra: 'query="$query" tracks=${tracks.length}',
      );
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
      extra:
          'query="$query" tracks=${res.tracks.length} '
          'albums=${res.albums.length} artists=${res.artists.length} '
          'playlists=${res.playlists.length}',
    );
    return (
      tracks: res.tracks,
      albums: res.albums,
      artists: res.artists,
      playlists: res.playlists,
    );
  },
);

final lyricsProvider = FutureProvider.autoDispose.family<Lrc?, String>((
  ref,
  trackId,
) async {
  // 1. Try local cache directory for previously fetched LRCLib lyrics (synced/plain)
  try {
    final cacheDir = await getApplicationCacheDirectory();
    final cacheFile = File(p.join(cacheDir.path, 'lyrics', '$trackId.lrc'));
    if (await cacheFile.exists()) {
      final raw = await cacheFile.readAsString();
      if (raw.isNotEmpty) {
        _logData(
          'lyrics',
          source: 'cache',
          extra: 'trackId=$trackId fromLocalCache=true',
        );
        return parseLrc(raw);
      }
    }
  } catch (e) {
    afLog('error', 'Failed to read lyrics from local cache', error: e);
  }

  final backend = ref.watch(musicBackendProvider);
  if (backend == null) {
    _logData('lyrics', source: 'demo', extra: 'trackId=$trackId (signed out)');
    return null;
  }

  // 2. Fetch from Jellyfin/Navidrome server or local embedded tag / sidecar
  final raw = await backend.lyrics(trackId);
  if (raw != null && raw.isNotEmpty) {
    final parsed = parseLrc(raw);
    _logData(
      'lyrics',
      source: 'live',
      extra: 'trackId=$trackId lines=${parsed.lines.length}',
    );
    return parsed;
  }

  // 3. Fallback: query LRCLib if the server doesn't have it
  _logData(
    'lyrics',
    source: 'fallback_check',
    extra: 'trackId=$trackId (backend yielded none, trying lrclib.net)',
  );

  // Try to get track details from currently playing track first to avoid loading
  AfTrack? track;
  final current = ref.read(currentTrackProvider);
  if (current != null && current.id == trackId) {
    track = current;
  } else {
    try {
      final details = await ref.read(trackDetailsProvider(trackId).future);
      track = details?.track;
    } catch (_) {}
  }

  if (track == null) {
    _logData(
      'lyrics',
      source: 'lrclib',
      extra: 'trackId=$trackId (missing track metadata)',
    );
    return null;
  }

  final lrclib = LrcLibClient();
  final fetched = await lrclib.fetchLyrics(
    trackName: track.title,
    artistName: track.artistName,
    albumName: track.albumName,
    duration: track.duration,
  );

  if (fetched != null) {
    final rawLyrics = fetched.synced ?? fetched.plain;
    if (rawLyrics != null && rawLyrics.isNotEmpty) {
      // Parse the retrieved lyrics
      final parsed = parseLrc(rawLyrics);

      // Cache it for next time
      try {
        final cacheDir = await getApplicationCacheDirectory();
        final cacheFile = File(p.join(cacheDir.path, 'lyrics', '$trackId.lrc'));
        await cacheFile.parent.create(recursive: true);
        await cacheFile.writeAsString(rawLyrics);
        _logData(
          'lyrics',
          source: 'lrclib_write',
          extra: 'cached to local cache path',
        );
      } catch (e) {
        afLog('error', 'Failed to write lyrics cache', error: e);
      }

      _logData(
        'lyrics',
        source: 'lrclib',
        extra:
            'trackId=$trackId lines=${parsed.lines.length} synced=${fetched.synced != null}',
      );
      return parsed;
    }
  }

  _logData('lyrics', source: 'live', extra: 'trackId=$trackId result=none');
  return null;
});
