import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/jellyfin/models/items.dart';
import '../utils/log.dart';
import 'library_providers.dart';
import 'music_backend_providers.dart';
import 'player_providers.dart';

void _logData(String feature, {required String source, String? extra}) {
  final detail = extra == null || extra.isEmpty ? '' : ' $extra';
  afLog('data', '$feature source=$source$detail');
}

/// Track-level favorite overrides written immediately on heart toggle.
final trackFavoriteOverridesProvider =
    StateProvider<Map<String, bool>>((ref) => const {});

final favoriteToggleProvider = Provider<Future<void> Function(AfTrack)>((ref) {
  return (AfTrack track) async {
    final backend = ref.read(musicBackendProvider);
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
