import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:romanize/romanize.dart' show JapaneseRomanizer;

import '../core/jellyfin/models/items.dart';
import '../core/lyrics/lrc_parser.dart';
import '../core/lyrics/lrclib_client.dart';
import '../core/lyrics/netease_client.dart';
import '../utils/text_utils.dart';
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
    if (mode == null) {
      return (
        tracks: const <AfTrack>[],
        albums: const <AfAlbum>[],
        artists: const <AfArtist>[],
        playlists: const <AfPlaylist>[],
      );
    }
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

final lyricsProvider = FutureProvider.autoDispose.family<LyricsResult?, String>(
  (ref, trackId) async {
    Future<AfTrack?> resolveTrack(String trackId) async {
      final current = ref.read(currentTrackProvider);
      if (current != null && current.id == trackId) return current;
      try {
        final details = await ref.read(trackDetailsProvider(trackId).future);
        return details?.track;
      } on Exception catch (e) {
        afLog('lyrics', 'Track details fetch failed', error: e);
        return null;
      }
    }

    Future<LyricsResult?> tryNeteaseRomaji(AfTrack track) async {
      final netease = NetEaseClient();
      final neteaseFetched = await netease.fetchLyrics(
        trackName: track.title,
        artistName: track.artistName,
        albumName: track.albumName,
        duration: track.duration,
      );
      if (neteaseFetched?.romaji != null &&
          neteaseFetched!.romaji!.isNotEmpty) {
        final parsed = parseLrc(neteaseFetched.romaji!);
        try {
          final cacheDir = await getApplicationCacheDirectory();
          final cacheFile = File(
            p.join(cacheDir.path, 'lyrics', '$trackId.lrc'),
          );
          await cacheFile.parent.create(recursive: true);
          await cacheFile.writeAsString(neteaseFetched.romaji!);
        } on Exception catch (e) {
          afLog('error', 'Failed to cache NetEase romaji', error: e);
        }
        _logData(
          'lyrics',
          source: 'netease_romaji',
          extra: 'trackId=$trackId lines=${parsed.lines.length}',
        );
        return LyricsResult(lrc: parsed, source: LyricsSource.neteaseRomaji);
      }
      return null;
    }

    LyricsResult romanizeLrc(String rawLrc) {
      final romanizer = JapaneseRomanizer();
      final lines = rawLrc.split('\n');
      final buffer = StringBuffer();
      for (final line in lines) {
        final timestampMatch = RegExp(r'^(\[\d{1,2}:\d{2}(?:\.\d{1,3})?\])').firstMatch(line);
        if (timestampMatch != null) {
          final timestamp = timestampMatch.group(1)!;
          final text = line.substring(timestamp.length);
          buffer.writeln('$timestamp${romanizer.romanize(text)}');
        } else if (RegExp(r'^\[[a-zA-Z]+:.+\]$').hasMatch(line)) {
          buffer.writeln(line);
        } else {
          buffer.writeln(romanizer.romanize(line));
        }
      }
      final parsed = parseLrc(buffer.toString());
      _logData(
        'lyrics',
        source: 'romanize',
        extra: 'trackId=$trackId lines=${parsed.lines.length}',
      );
      return LyricsResult(lrc: parsed, source: LyricsSource.romanize);
    }

    // 1. Check cache
    try {
      final cacheDir = await getApplicationCacheDirectory();
      final cacheFile = File(
        p.join(cacheDir.path, 'lyrics', '$trackId.lrc'),
      );
      if (await cacheFile.exists()) {
        final raw = await cacheFile.readAsString();
        if (raw.isNotEmpty) {
          if (containsJapanese(raw)) {
            final track = await resolveTrack(trackId);
            if (track != null) {
              final romajiResult = await tryNeteaseRomaji(track);
              if (romajiResult != null) return romajiResult;
            }
          }
          _logData(
            'lyrics',
            source: 'cache',
            extra: 'trackId=$trackId fromLocalCache=true',
          );
          return LyricsResult(
            lrc: parseLrc(raw),
            source: LyricsSource.cache,
          );
        }
      }
    } on Exception catch (e) {
      afLog('error', 'Failed to read lyrics from local cache', error: e);
    }

    final backend = ref.watch(musicBackendProvider);
    if (backend == null) {
      _logData(
        'lyrics',
        source: 'demo',
        extra: 'trackId=$trackId (signed out)',
      );
      return null;
    }

    // 2. Embedded lyrics from server
    final raw = await backend.lyrics(trackId);
    if (raw != null && raw.isNotEmpty) {
      if (containsJapanese(raw)) {
        final track = await resolveTrack(trackId);
        if (track != null) {
          final romajiResult = await tryNeteaseRomaji(track);
          if (romajiResult != null) return romajiResult;
        }
        return romanizeLrc(raw);
      }
      final parsed = parseLrc(raw);
      _logData(
        'lyrics',
        source: 'server',
        extra: 'trackId=$trackId lines=${parsed.lines.length}',
      );
      return LyricsResult(lrc: parsed, source: LyricsSource.server);
    }

    // 3. LRCLib
    _logData(
      'lyrics',
      source: 'fallback_check',
      extra: 'trackId=$trackId (backend yielded none, trying lrclib.net)',
    );

    AfTrack? track;
    final current = ref.read(currentTrackProvider);
    if (current != null && current.id == trackId) {
      track = current;
    } else {
      try {
        final details = await ref.read(trackDetailsProvider(trackId).future);
        track = details?.track;
      } on Exception catch (e) {
        afLog('lyrics', 'Track details fetch failed for lyrics', error: e);
      }
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
        final parsed = parseLrc(rawLyrics);
        try {
          final cacheDir = await getApplicationCacheDirectory();
          final cacheFile = File(
            p.join(cacheDir.path, 'lyrics', '$trackId.lrc'),
          );
          await cacheFile.parent.create(recursive: true);
          await cacheFile.writeAsString(rawLyrics);
        } on Exception catch (e) {
          afLog('error', 'Failed to write lyrics cache', error: e);
        }
        _logData(
          'lyrics',
          source: 'lrclib',
          extra:
              'trackId=$trackId lines=${parsed.lines.length} synced=${fetched.synced != null}',
        );
        return LyricsResult(lrc: parsed, source: LyricsSource.lrclib);
      }
    }

    // 4. NetEase
    _logData(
      'lyrics',
      source: 'fallback_check',
      extra: 'trackId=$trackId (lrclib yielded none, trying NetEase)',
    );

    final netease = NetEaseClient();
    final neteaseFetched = await netease.fetchLyrics(
      trackName: track.title,
      artistName: track.artistName,
      albumName: track.albumName,
      duration: track.duration,
    );

    if (neteaseFetched != null) {
      final rawLyrics = neteaseFetched.synced ?? neteaseFetched.plain;
      if (rawLyrics != null && rawLyrics.isNotEmpty) {
        final parsed = parseLrc(rawLyrics);
        try {
          final cacheDir = await getApplicationCacheDirectory();
          final cacheFile = File(
            p.join(cacheDir.path, 'lyrics', '$trackId.lrc'),
          );
          await cacheFile.parent.create(recursive: true);
          await cacheFile.writeAsString(rawLyrics);
        } on Exception catch (e) {
          afLog('error', 'Failed to write lyrics cache', error: e);
        }
        _logData(
          'lyrics',
          source: 'netease',
          extra:
              'trackId=$trackId lines=${parsed.lines.length} synced=${neteaseFetched.synced != null}',
        );
        return LyricsResult(lrc: parsed, source: LyricsSource.netease);
      }
    }

    _logData('lyrics', source: 'live', extra: 'trackId=$trackId result=none');
    return null;
  },
);
