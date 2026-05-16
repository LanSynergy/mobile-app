import 'dart:async';

import 'player_service.dart';

/// Bridges [AfPlayerService] state into the native Android 16 "Live
/// Updates" / Promoted Ongoing Notifications system via the
/// `aetherfin.live_update` MethodChannel.
///
/// CURRENTLY DISABLED: On Android 16+ the OS already promotes the
/// audio_service MediaStyle notification to a rich media widget (with
/// artwork, seekbar, and transport controls). Posting a second
/// ProgressStyle notification just creates a duplicate in the
/// notification shade — this applies to ALL Android 16 devices
/// (Samsung, Pixel, etc.).
///
/// The native plugin (`LiveUpdatePlugin.kt`) and manifest permissions
/// are kept intact so this can be re-enabled if Android introduces a
/// way to link ProgressStyle to MediaStyle without duplication, or if
/// we want to target pre-16 custom ROMs that support promoted ongoing
/// notifications.
class LiveUpdateService {
  // ignore: unused_field
  final AfPlayerService _player;

  LiveUpdateService(this._player);

  /// No-op. See class doc for rationale.
  Future<void> attach() async {}

  /// No-op — nothing to tear down when attach is disabled.
  Future<void> dispose() async {}
}
