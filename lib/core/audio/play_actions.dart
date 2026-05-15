import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../../utils/log.dart';
import '../jellyfin/models/items.dart';

/// Cross-cutting "Play" entry points used by every screen so that we
/// don't replicate the wiring (and so the spectral provider always
/// updates first — per spec §3.4).
class PlayActions {
  final Ref ref;
  PlayActions(this.ref);

  /// Replace the queue with [tracks] and start playback at [startIndex].
  /// If shuffle mode is ON, the selected track plays first and the rest
  /// are shuffled below it.
  Future<void> playQueue(
    List<AfTrack> tracks, {
    int startIndex = 0,
  }) async {
    if (tracks.isEmpty) return;
    final svc = ref.read(playerServiceProvider);
    final backend = ref.read(musicBackendProvider);

    String resolveStreamUrl(AfTrack t) {
      if (backend != null) {
        return backend.trackStreamUrl(t.id, maxBitrateKbps: 320);
      }
      return 'about:blank';
    }

    final safeIndex = startIndex < 0
        ? 0
        : (startIndex >= tracks.length ? tracks.length - 1 : startIndex);

    // If shuffle is ON, put the selected track first and shuffle the rest.
    List<AfTrack> finalQueue;
    int finalIndex;
    if (svc.isShuffleEnabled) {
      final selected = tracks[safeIndex];
      final rest = List.of(tracks)..removeAt(safeIndex);
      rest.shuffle();
      finalQueue = [selected, ...rest];
      finalIndex = 0;
    } else {
      finalQueue = tracks;
      finalIndex = safeIndex;
    }

    ref.read(currentTrackProvider.notifier).state = finalQueue[finalIndex];
    if (backend != null) {
      try {
        await svc.playQueue(
          finalQueue,
          startIndex: finalIndex,
          resolveStreamUrl: resolveStreamUrl,
          streamHeaders: backend.authHeaders,
        );
      } catch (e, stack) {
        afLog(
          'audio',
          'playQueue failed',
          error: e,
          stackTrace: stack,
        );
      }
    }
  }

  Future<void> playAlbum(List<AfTrack> tracks) => playQueue(tracks);

  Future<void> playSingle(AfTrack track) =>
      playQueue([track], startIndex: 0);

  /// Replace the queue with the seed track followed by [Jellyfin's Instant
  /// Mix](https://api.jellyfin.org/#tag/InstantMix/operation/GetInstantMixFromItem)
  /// of similar songs. Implements the user's "generate queue related song
  /// based on the song played" feature.
  ///
  /// On signed-out / demo builds this falls back to `playSingle` because
  /// there's no server to query — surfacing an error toast would be
  /// noisier than silently playing what we have.
  Future<void> playInstantMix(AfTrack seed) async {
    final backend = ref.read(musicBackendProvider);
    if (backend == null) {
      await playSingle(seed);
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
      afLog(
        'audio',
        'instantMix failed',
        error: e,
        stackTrace: stack,
      );
      // Best-effort fallback: at least play the seed track.
      await playSingle(seed);
    }
  }
}

final playActionsProvider = Provider<PlayActions>((ref) => PlayActions(ref));
