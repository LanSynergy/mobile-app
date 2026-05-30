import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/jellyfin/models/items.dart';
import '../utils/log.dart';
import 'library_providers.dart';
import 'music_backend_providers.dart';
import 'settings_providers.dart';

void _logData(String feature, {required String source, String? extra}) {
  final detail = extra == null || extra.isEmpty ? '' : ' $extra';
  afLog('data', '$feature source=$source$detail');
}

/// Track-level favorite overrides written immediately on heart toggle.
final trackFavoriteOverridesProvider = StateProvider<Map<String, bool>>(
  (ref) => const {},
);

/// Derives the favorite state for a specific track by merging overrides
/// (from optimistic UI) with the server/library favorite IDs.
final isFavoriteProvider = Provider.family<bool, String>((ref, trackId) {
  final overrides = ref.watch(trackFavoriteOverridesProvider);
  if (overrides.containsKey(trackId)) return overrides[trackId]!;
  final favIds = ref.watch(favoriteIdsProvider);
  return favIds.contains(trackId);
});

final favoriteToggleProvider = Provider<Future<void> Function(AfTrack)>((ref) {
  /// Serializer: any previous in-flight toggle must resolve before the
  /// next one starts. Without this, rapid double-taps create a race
  /// between optimistic overrides and backend responses — the earlier
  /// toggle's error-handler can restore a stale value, and two
  /// concurrent `setFavorite` calls can leave the server in the
  /// opposite state from what the override map shows.
  Future<void>? pending;

  return (AfTrack track) async {
    while (pending != null) {
      try {
        await pending!;
      } catch (_) {}
    }

    final backend = ref.read(musicBackendProvider);
    final overrides = ref.read(trackFavoriteOverridesProvider);
    final wasFavorite = overrides[track.id] ?? track.isFavorite;
    final next = !wasFavorite;
    ref
        .read(trackFavoriteOverridesProvider.notifier)
        .update((s) => {...s, track.id: next});

    if (backend == null) {
      _logData(
        'favoriteToggle',
        source: 'demo',
        extra: '(signed out) id=${track.id} isFavorite=$next',
      );
      return;
    }

    pending = (() async {
      try {
        await backend.setFavorite(track.id, next);
        _logData(
          'favoriteToggle',
          source: 'live',
          extra: 'id=${track.id} isFavorite=$next',
        );

        // Sync to Last.fm if account is linked
        final lastFmClient = ref.read(lastFmClientProvider);
        final sessionKey = ref.read(lastfmSessionKeyProvider);
        if (lastFmClient != null && sessionKey.isNotEmpty) {
          try {
            if (next) {
              await lastFmClient.love(
                artist: track.artistName,
                track: track.title,
              );
            } else {
              await lastFmClient.unlove(
                artist: track.artistName,
                track: track.title,
              );
            }
          } catch (e, stack) {
            afLog(
              'error',
              'Last.fm love/unlove failed during toggle',
              error: e,
              stackTrace: stack,
            );
          }
        }

        ref.invalidate(favoriteAlbumsProvider);
        ref.invalidate(favoriteTracksProvider);
        ref.invalidate(recentlyPlayedTracksProvider);
      } catch (e, stack) {
        afLog('error', 'favoriteToggle failed', error: e, stackTrace: stack);
        ref
            .read(trackFavoriteOverridesProvider.notifier)
            .update((s) => {...s, track.id: wasFavorite});
        rethrow;
      }
    })();

    try {
      await pending!;
    } finally {
      pending = null;
    }
  };
});
