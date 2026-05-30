import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/backend/music_backend.dart';
import '../core/jellyfin/models/items.dart';
import '../utils/log.dart';
import 'library_providers.dart';
import 'local_library_providers.dart';
import 'music_backend_providers.dart';
import 'settings_providers.dart';

/// Provider exposing favorite syncing action.
final lastFmSyncProvider =
    Provider<Future<({int toApp, int toLastFm})> Function()>((ref) {
      return () async {
        final client = ref.read(lastFmClientProvider);
        final sessionKey = ref.read(lastfmSessionKeyProvider);
        final username = ref.read(lastfmUsernameProvider);
        final backend = ref.read(musicBackendProvider);

        if (client == null ||
            sessionKey.isEmpty ||
            username.isEmpty ||
            backend == null) {
          throw StateError(
            'Last.fm integration or audio library is not connected.',
          );
        }

        afLog('data', 'Starting Last.fm favorite synchronization');

        // 1. Fetch loved tracks from Last.fm
        final lovedLastFm = await client.getLovedTracks(
          username: username,
          limit: 200,
        );

        // 2. Fetch favorite tracks from Backend
        final appFavorites = await backend.favoriteTracks(limit: 500);

        final backendKeys =
            appFavorites
                .map(
                  (t) =>
                      '${t.artistName.toLowerCase().trim()}::${t.title.toLowerCase().trim()}',
                )
                .toSet();

        final lastFmKeys =
            lovedLastFm
                .map(
                  (t) =>
                      '${t.artist.toLowerCase().trim()}::${t.title.toLowerCase().trim()}',
                )
                .toSet();

        int toApp = 0;
        int toLastFm = 0;

        // --- Sync: Last.fm -> App ---
        final missingInApp =
            lovedLastFm.where((t) {
              final key =
                  '${t.artist.toLowerCase().trim()}::${t.title.toLowerCase().trim()}';
              return !backendKeys.contains(key);
            }).toList();

        // Limit syncing searches in one run to protect backend rate limits
        final limitAppSync = missingInApp.take(30);
        for (final item in limitAppSync) {
          try {
            AfTrack? resolved;
            if (backend.serverType == ServerType.local) {
              final db = ref.read(localLibraryProvider).db;
              resolved = await db.searchTrackByArtistAndTitle(
                item.artist,
                item.title,
              );
            } else {
              final results = await backend.search(
                '${item.artist} ${item.title}',
              );
              for (final t in results.tracks) {
                if (t.title.toLowerCase() == item.title.toLowerCase() &&
                    t.artistName.toLowerCase() == item.artist.toLowerCase()) {
                  resolved = t;
                  break;
                }
              }
              if (resolved == null) {
                for (final t in results.tracks) {
                  if (t.title.toLowerCase().contains(
                        item.title.toLowerCase(),
                      ) &&
                      t.artistName.toLowerCase().contains(
                        item.artist.toLowerCase(),
                      )) {
                    resolved = t;
                    break;
                  }
                }
              }
            }

            if (resolved != null) {
              await backend.setFavorite(resolved.id, true);
              toApp++;
            }
          } catch (e) {
            afLog(
              'error',
              'Failed to resolve/sync track ${item.artist} - ${item.title}',
              error: e,
            );
          }
        }

        // --- Sync: App -> Last.fm ---
        final missingInLastFm =
            appFavorites.where((t) {
              final key =
                  '${t.artistName.toLowerCase().trim()}::${t.title.toLowerCase().trim()}';
              return !lastFmKeys.contains(key);
            }).toList();

        final limitLastFmSync = missingInLastFm.take(30);
        for (final item in limitLastFmSync) {
          try {
            await client.love(artist: item.artistName, track: item.title);
            toLastFm++;
          } catch (e) {
            afLog(
              'error',
              'Failed to love track ${item.artistName} - ${item.title} on Last.fm',
              error: e,
            );
          }
        }

        if (toApp > 0 || toLastFm > 0) {
          ref.invalidate(favoriteTracksProvider);
          ref.invalidate(favoriteIdsProvider);
        }

        return (toApp: toApp, toLastFm: toLastFm);
      };
    });
