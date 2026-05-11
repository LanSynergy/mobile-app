package dev.aetherfin.aetherfin

import com.ryanheise.audioservice.AudioServiceActivity
import dev.aetherfin.aetherfin.live_update.LiveUpdatePlugin
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(LiveUpdatePlugin())
    }
}
