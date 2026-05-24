import 'dart:async';

import '../../utils/log.dart';
import '../backend/music_backend.dart';
import '../jellyfin/models/items.dart';
import 'player_service.dart';

/// Pushes playback-session lifecycle events from [AfPlayerService] to the
/// Jellyfin server so the "Now Playing" widgets, listening history, and
/// activity feed all reflect what's actually playing.
///
/// Wired up in `playerServiceProvider` so the player itself stays
/// Riverpod-free. [clientGetter] is a *lazy* lookup (called on every
/// emit) so when auth flips and `jellyfinClientProvider` rebuilds with a
/// new `JellyfinClient`, the reporter automatically targets the new
/// server without any re-subscription dance.
///
/// Endpoints used (per the Jellyfin REST conventions Finamp + the web
/// client agree on):
///   • `POST /Sessions/Playing`           — first emit for a new track
///   • `POST /Sessions/Playing/Progress`  — every 10s while playing,
///                                          and once on each pause / resume
///   • `POST /Sessions/Playing/Stopped`   — when the queue advances, the
///                                          player stops, or the reporter
///                                          is disposed
class JellyfinPlaybackReporter {

  JellyfinPlaybackReporter(this._player, this._clientGetter) {
    _trackSub = _player.currentTrackStream.listen(_onTrackChanged);
    _playingSub = _player.playingStream.listen(_onPlayingChanged);
  }
  final AfPlayerService _player;
  final MusicBackend? Function() _clientGetter;

  static const _progressInterval = Duration(seconds: 10);

  StreamSubscription<AfTrack?>? _trackSub;
  StreamSubscription<bool>? _playingSub;
  String? _lastReportedTrackId;
  bool _disposed = false;
  // dispose() must NOT send a `Stopped` ping when the reporter is being
  // torn down purely because the ProviderScope rebuilt around a still-
  // playing track — otherwise Jellyfin's activity feed flips to "stopped"
  // while audio keeps coming out the speaker. Set to false on every
  // intentional teardown (audio service stops, sign-out, app close).
  bool _shouldStopOnDispose = false;

  Future<void> _onTrackChanged(AfTrack? track) async {
    if (_disposed) return;
    final client = _clientGetter();
    final previousId = _lastReportedTrackId;

    // Stop the progress timer before sending playbackStop to prevent
    // the old loop from reporting progress for the previous track
    // after the stop has been sent.
    _stopProgressTimer();

    if (previousId != null && previousId != track?.id) {
      final position = _player.position;
      if (client != null) {
        try {
          await client
              .reportPlaybackStop(previousId, position)
              .timeout(const Duration(seconds: 5));
          if (_disposed) return;
          // Re-check after the await: a concurrent _onTrackChanged(null)
          // may have cleared _lastReportedTrackId, invalidating our context.
          if (_lastReportedTrackId != previousId) return;
          afLog(
            'data',
            'playbackStop source=live track=$previousId '
            'positionMs=${position.inMilliseconds}',
          );
        } catch (e, stack) {
          afLog('error', 'reportPlaybackStop failed', error: e, stackTrace: stack);
        }
      }
    }

    if (track == null) {
      _lastReportedTrackId = null;
      return;
    }
    if (track.id == previousId) return;
    if (_disposed) return;

    _lastReportedTrackId = track.id;
    if (client == null) {
      afLog('data', 'playbackStart source=demo track=${track.id} (signed out)');
      return;
    }
    try {
      await client
          .reportPlaybackStart(track.id)
          .timeout(const Duration(seconds: 5));
      if (_disposed) return;
      afLog('data', 'playbackStart source=live track=${track.id}');
      _startProgressTimer();
    } catch (e, stack) {
      afLog('error', 'reportPlaybackStart failed', error: e, stackTrace: stack);
    }
  }

  Future<void> _onPlayingChanged(bool isPlaying) async {
    if (_disposed) return;
    final trackId = _lastReportedTrackId;
    if (trackId == null) return;
    final client = _clientGetter();
    if (client == null) return;
    final position = _player.position;
    try {
      await client
          .reportProgress(trackId, position, isPaused: !isPlaying)
          .timeout(const Duration(seconds: 5));
      afLog(
        'data',
        'playbackProgress source=live track=$trackId '
        'positionMs=${position.inMilliseconds} paused=${!isPlaying}',
      );
    } catch (e, stack) {
      afLog('error', 'reportProgress (transition) failed', error: e, stackTrace: stack);
    }
    if (isPlaying) {
      _startProgressTimer();
    } else {
      _stopProgressTimer();
    }
  }

  void _startProgressTimer() {
    _stopProgressTimer();
    // Use a serialized loop instead of Timer.periodic to prevent concurrent
    // network calls. Timer.periodic does NOT await the callback — if the
    // server is slow, multiple in-flight requests pile up and stale progress
    // can arrive after newer progress, regressing backend state.
    //
    // The generation counter is what isolates restarts: a rapid
    // pause/resume within the 10s interval used to leave the previous
    // loop's `Future.delayed` still pending. When `_stopProgressTimer`
    // flips `_progressRunning` to false the old loop is sleeping, and by
    // the time it wakes a new `_startProgressTimer` has already flipped
    // it back to true — so the old loop kept ticking alongside the new
    // one. Bumping `_loopGeneration` per start lets every loop notice it
    // is no longer the active one regardless of the shared bool's value.
    _loopGeneration++;
    _progressRunning = true;
    _runProgressLoop(_loopGeneration);
  }

  bool _progressRunning = false;
  int _loopGeneration = 0;

  Future<void> _runProgressLoop(int generation) async {
    while (_progressRunning && generation == _loopGeneration) {
      await Future.delayed(_progressInterval);
      if (!_progressRunning || generation != _loopGeneration) break;
      final trackId = _lastReportedTrackId;
      if (trackId == null) break;
      final client = _clientGetter();
      if (client == null) break;
      final position = _player.position;
      try {
        await client
            .reportProgress(trackId, position)
            .timeout(const Duration(seconds: 5));
        afLog(
          'data',
          'playbackProgress source=live track=$trackId '
          'positionMs=${position.inMilliseconds} (tick)',
        );
      } catch (e, stack) {
        afLog('error', 'reportProgress (tick) failed', error: e, stackTrace: stack);
        // Continue loop — a single failed tick shouldn't stop reporting.
      }
    }
  }

  void _stopProgressTimer() {
    _progressRunning = false;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _trackSub?.cancel();
    await _playingSub?.cancel();
    _stopProgressTimer();
    final trackId = _lastReportedTrackId;
    if (trackId == null) return;
    if (!_shouldStopOnDispose) return;
    final client = _clientGetter();
    if (client == null) return;
    final position = _player.position;
    try {
      await client
          .reportPlaybackStop(trackId, position)
          .timeout(const Duration(seconds: 5));
      afLog(
        'data',
        'playbackStop source=live track=$trackId '
        'positionMs=${position.inMilliseconds} (reporter disposed)',
      );
    } catch (e, stack) {
      afLog('error', 'reportPlaybackStop (dispose) failed', error: e, stackTrace: stack);
    }
  }

  /// Call before [dispose] when the caller WANTS a final Stopped ping
  /// to be sent (sign-out, app close, queue cleared). Default is to
  /// keep the active session open so the activity feed isn't trashed
  /// by spurious teardowns.
  void requestStopOnDispose() {
    _shouldStopOnDispose = true;
  }
}
