import 'dart:async';

import '../../utils/log.dart';
import '../jellyfin/models/items.dart';
import '../lastfm/lastfm_client.dart';
import 'player_service.dart';

/// Pushes Now Playing updates and Scrobbles to Last.fm.
///
/// Listens to [AfPlayerService.currentTrackStream]. When a track starts,
/// we update "Now Playing". When it changes or the reporter is disposed,
/// we submit a "Scrobble" if the user has listened to the track for at
/// least 50% of its duration or 4 minutes (whichever comes first), and
/// if the track duration is at least 30 seconds.
class LastFmPlaybackReporter {
  LastFmPlaybackReporter(
    this._player,
    this._clientGetter,
    this._enabledGetter,
  ) {
    _trackSub = _player.currentTrackStream.listen(_onTrackChanged);
  }

  final AfPlayerService _player;
  final LastFmClient? Function() _clientGetter;
  final bool Function() _enabledGetter;

  StreamSubscription<AfTrack?>? _trackSub;
  AfTrack? _lastReportedTrack;
  bool _disposed = false;

  Future<void> _onTrackChanged(AfTrack? track) async {
    if (_disposed) return;
    final client = _clientGetter();
    final enabled = _enabledGetter();

    if (client == null || !enabled) {
      _lastReportedTrack = track;
      return;
    }

    final previousTrack = _lastReportedTrack;

    // 1. Submit scrobble for the previous track if it met the threshold
    if (previousTrack != null && previousTrack.id != track?.id) {
      final listened = _player.listenedDuration;
      final duration = previousTrack.duration;

      // Last.fm criteria:
      // - Track must be >= 30 seconds long
      // - Listened for >= 50% of duration OR >= 4 minutes
      final isThresholdMet =
          duration >= const Duration(seconds: 30) &&
          ((duration > Duration.zero && listened >= duration * 0.5) ||
              listened >= const Duration(minutes: 4));

      if (isThresholdMet) {
        // Timestamp must be the starting play time in seconds since epoch.
        final timestamp =
            DateTime.now().millisecondsSinceEpoch ~/ 1000 - listened.inSeconds;
        unawaited(
          client.scrobble(
            artist: previousTrack.artistName,
            track: previousTrack.title,
            album: previousTrack.albumName,
            duration: previousTrack.duration,
            timestamp: timestamp,
          ),
        );
      } else {
        afLog(
          'data',
          'Last.fm track "${previousTrack.title}" skipped scrobble '
              '(listened: ${listened.inSeconds}s, duration: ${duration.inSeconds}s)',
        );
      }
    }

    // 2. Scrobble last track when queue ends, then clean up
    if (track == null) {
      if (previousTrack != null) {
        final listened = _player.listenedDuration;
        final duration = previousTrack.duration;
        final isThresholdMet =
            duration >= const Duration(seconds: 30) &&
            ((duration > Duration.zero && listened >= duration * 0.5) ||
                listened >= const Duration(minutes: 4));
        if (isThresholdMet) {
          final timestamp =
              DateTime.now().millisecondsSinceEpoch ~/ 1000 -
              listened.inSeconds;
          unawaited(
            client.scrobble(
              artist: previousTrack.artistName,
              track: previousTrack.title,
              album: previousTrack.albumName,
              duration: previousTrack.duration,
              timestamp: timestamp,
            ),
          );
        }
      }
      _lastReportedTrack = null;
      return;
    }

    if (track.id == previousTrack?.id) return;
    _lastReportedTrack = track;

    // Send Now Playing update
    unawaited(
      client.updateNowPlaying(
        artist: track.artistName,
        track: track.title,
        album: track.albumName,
        duration: track.duration,
      ),
    );
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _trackSub?.cancel();

    // Try scrobbling the final track upon disposal
    final track = _lastReportedTrack;
    final client = _clientGetter();
    final enabled = _enabledGetter();

    if (track != null && client != null && enabled) {
      final listened = _player.listenedDuration;
      final duration = track.duration;
      final isThresholdMet =
          duration >= const Duration(seconds: 30) &&
          ((duration > Duration.zero && listened >= duration * 0.5) ||
              listened >= const Duration(minutes: 4));

      if (isThresholdMet) {
        final timestamp =
            DateTime.now().millisecondsSinceEpoch ~/ 1000 - listened.inSeconds;
        try {
          await client.scrobble(
            artist: track.artistName,
            track: track.title,
            album: track.albumName,
            duration: track.duration,
            timestamp: timestamp,
          );
        } catch (e, stack) {
          afLog(
            'error',
            'Last.fm final scrobble on dispose failed',
            error: e,
            stackTrace: stack,
          );
        }
      }
    }
  }
}
