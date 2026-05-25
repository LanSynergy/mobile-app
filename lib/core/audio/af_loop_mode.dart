import 'package:mpv_audio_kit/mpv_audio_kit.dart';

/// Loop mode enum matching mpv's loop types plus a Dart-managed forNtimes.
enum AfLoopMode {
  off,
  file,
  playlist,
  forNtimes;

  Loop toMpvLoop() {
    switch (this) {
      case AfLoopMode.off:
        return Loop.off;
      case AfLoopMode.file:
        return Loop.file;
      case AfLoopMode.playlist:
        return Loop.playlist;
      case AfLoopMode.forNtimes:
        return Loop.off; // Dart handles forNtimes
    }
  }
}
