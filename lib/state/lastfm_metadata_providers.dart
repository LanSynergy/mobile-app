import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'music_backend_providers.dart';
import 'settings_providers.dart';

/// Fetches artist wiki/biography from Last.fm, falling back to server-supplied overview/bio.
final artistWikiProvider = FutureProvider.family.autoDispose<
  ({String? bio, String? listeners, String? playCount})?,
  String
>((ref, artistId) async {
  final backend = ref.watch(musicBackendProvider);
  if (backend == null) return null;
  final artist = await backend.artist(artistId);
  if (artist == null) return null;

  final lastFmClient = ref.watch(lastFmClientProvider);
  if (lastFmClient != null) {
    try {
      final info = await lastFmClient.getArtistInfo(artistName: artist.name);
      if (info != null) {
        final bioText =
            info['bio']?['content'] as String? ??
            info['bio']?['summary'] as String?;
        final listeners = info['stats']?['listeners'] as String?;
        final playCount = info['stats']?['playcount'] as String?;
        return (
          bio: bioText != null && bioText.isNotEmpty ? bioText : artist.bio,
          listeners: listeners,
          playCount: playCount,
        );
      }
    } catch (_) {}
  }

  // Fallback to server overview/bio
  if (artist.bio != null && artist.bio!.isNotEmpty) {
    return (
      bio: artist.bio,
      listeners: null as String?,
      playCount: null as String?,
    );
  }

  return null;
});

typedef AlbumWikiParams = ({String artistName, String albumName});

/// Fetches album wiki/description from Last.fm.
final albumWikiProvider = FutureProvider.family.autoDispose<
  ({String? wiki, String? listeners, String? playCount})?,
  AlbumWikiParams
>((ref, params) async {
  final lastFmClient = ref.watch(lastFmClientProvider);
  if (lastFmClient == null) return null;

  try {
    final info = await lastFmClient.getAlbumInfo(
      artistName: params.artistName,
      albumName: params.albumName,
    );
    if (info == null) return null;
    final wikiText =
        info['wiki']?['content'] as String? ??
        info['wiki']?['summary'] as String?;
    final listeners = info['listeners'] as String?;
    final playCount = info['playcount'] as String?;
    return (wiki: wikiText, listeners: listeners, playCount: playCount);
  } catch (_) {
    return null;
  }
});
