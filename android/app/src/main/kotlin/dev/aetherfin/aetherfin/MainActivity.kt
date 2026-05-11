package dev.aetherfin.aetherfin

import com.ryanheise.audioservice.AudioServiceActivity
import dev.aetherfin.aetherfin.live_update.LiveUpdatePlugin
import io.flutter.embedding.engine.FlutterEngine

/// Extends [AudioServiceActivity] (from the `audio_service` plugin) instead
/// of FlutterActivity so audio_service's foreground service can attach to
/// the running Flutter engine. Without this, AudioService.init throws:
///   "The Activity class declared in your AndroidManifest.xml is wrong or
///    has not provided the correct FlutterEngine."
class MainActivity : AudioServiceActivity() {
    /// Manual registration for the in-app [LiveUpdatePlugin] — it lives
    /// in `android/app/src/main/kotlin/.../live_update/` rather than as
    /// a separate published plugin, so Flutter's auto-registration
    /// doesn't pick it up.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(LiveUpdatePlugin())
    }
}
