import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../../utils/log.dart';
import '../jellyfin/models/items.dart';

/// Cross-cutting "Play" entry points used by every screen so that we
/// don't replicate the wiring (and so the spectral provider always
/// updates first — per spec §3.4).
class PlayActions {
  PlayActions(this.ref);
  final Ref ref;

  /// Replace the queue with [tracks] and start playback at [startIndex].
  /// If shuffle mode is ON, the selected track plays first and the rest
  /// are shuffled below it.
  Future<void> playQueue(List<AfTrack> tracks, {int startIndex = 0}) async {
    if (tracks.isEmpty) return;
    final svc = ref.read(playerServiceProvider);
    final mode = ref.read(appModeProvider);
    final backend = ref.read(musicBackendProvider);

    // In local mode, the track ID is the content:// URI itself.
    // In server mode, check offline cache first, then the backend.
    String resolveStreamUrl(AfTrack t) {
      if (mode == AppMode.local) return t.id;
      final cache = ref.read(offlineCacheServiceProvider);
      if (ref.read(offlineCacheEnabledProvider)) {
        final cachedUri = cache.cachedFileUri(t.id);
        if (cachedUri != null) return cachedUri;
      }
      if (backend != null) {
        final maxBitrate = ref.read(maxBitrateProvider);
        return backend.trackStreamUrl(
          t.id,
          maxBitrateKbps: maxBitrate == 0 ? null : maxBitrate,
        );
      }
      return 'about:blank';
    }

    final safeIndex = startIndex < 0
        ? 0
        : (startIndex >= tracks.length ? tracks.length - 1 : startIndex);

    // Don't pre-shuffle here — let mpv's shuffle mode handle randomization.
    // Pre-shuffling corrupts _originalQueue so that toggling shuffle off
    // later restores to the shuffled order instead of the original.
    final wasShuffleEnabled = svc.isShuffleEnabled == true;
    try {
      await svc.playQueue(
        tracks,
        startIndex: safeIndex,
        resolveStreamUrl: resolveStreamUrl,
        // No auth headers needed for local files.
        streamHeaders: mode == AppMode.local
            ? const {}
            : (backend?.authHeaders ?? const {}),
      );
      if (wasShuffleEnabled) {
        await svc.setAfShuffleMode(true);
      }
      ref.read(currentTrackProvider.notifier).state = tracks[safeIndex];

      // Save to queue history (non-critical — log warnings, don't throw)
      try {
        final repo = ref.read(queueHistoryRepositoryProvider);
        final sourceLabel = _computeSourceLabel(tracks);
        final sourceType = _computeSourceType();
        final sourceId = tracks.isNotEmpty
            ? tracks[0].albumId ?? tracks[0].artistId
            : null;
        await repo.save(
          trackIds: tracks.map((t) => t.id).toList(),
          sourceLabel: sourceLabel,
          sourceType: sourceType,
          sourceId: sourceId,
        );
      } catch (e) {
        afLog('data', 'queueHistory save failed', error: e);
      }
    } catch (e, stack) {
      afLog('audio', 'playQueue failed', error: e, stackTrace: stack);
      rethrow;
    }
  }

  Future<void> playAlbum(List<AfTrack> tracks) => playQueue(tracks);

  Future<void> playSingle(AfTrack track) async {
    final autoplay = ref.read(autoplayEnabledProvider);
    if (autoplay) {
      await playInstantMix(track);
    } else {
      await playQueue([track], startIndex: 0);
    }
  }

  /// Replace the queue with the seed track followed by [Jellyfin's Instant
  /// Mix](https://api.jellyfin.org/#tag/InstantMix/operation/GetInstantMixFromItem)
  /// of similar songs. Implements the user's "generate queue related song
  /// based on the song played" feature.
  ///
  /// On signed-out / demo builds this falls back to playing the single track
  /// because there's no server to query — surfacing an error toast would be
  /// noisier than silently playing what we have.
  Future<void> playInstantMix(AfTrack seed) async {
    final backend = ref.read(musicBackendProvider);
    if (backend == null) {
      await playQueue([seed], startIndex: 0);
      return;
    }
    try {
      final mix = await backend.instantMix(seed.id);
      // Server-generated mix sometimes excludes the seed; prepend it so
      // the user hears the song they tapped first, then the radio.
      final queue = <AfTrack>[
        seed,
        for (final t in mix)
          if (t.id != seed.id) t,
      ];
      afLog(
        'audio',
        'instantMix seed=${seed.id} '
            'queue=${queue.length} (from server: ${mix.length})',
      );
      await playQueue(queue);
    } catch (e, stack) {
      afLog('audio', 'instantMix failed', error: e, stackTrace: stack);
      // Best-effort fallback: at least play the seed track.
      await playQueue([seed], startIndex: 0);
    }
  }


  String _computeSourceLabel(List<AfTrack> tracks) {
    if (tracks.isEmpty) return 'Unknown';
    final first = tracks.first;
    if (first.albumName.isNotEmpty) return 'Album: ${first.albumName}';
    if (first.artistName.isNotEmpty) return 'Artist: ${first.artistName}';
    if (tracks.length == 1) return 'Single: ${first.title}';
    return 'Queue (${tracks.length} tracks)';
  }

  String _computeSourceType() {
    return 'manual';
  }
}

final playActionsProvider = Provider<PlayActions>(PlayActions.new);
