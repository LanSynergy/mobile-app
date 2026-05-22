package dev.aetherfin.aetherfin

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat
import dev.aetherfin.aetherfin.battery.BatteryOptPlugin
import dev.aetherfin.aetherfin.live_update.LiveUpdatePlugin
import dev.aetherfin.aetherfin.saf.SafPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        var mediaSessionChannel: MethodChannel? = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(LiveUpdatePlugin())
        flutterEngine.plugins.add(BatteryOptPlugin())
        flutterEngine.plugins.add(SafPlugin())

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "aetherfin.media_session")
        mediaSessionChannel = channel

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "updateState" -> {
                    val intent = Intent(this, AetherfinMediaSessionService::class.java).apply {
                        action = AetherfinMediaSessionService.ACTION_UPDATE_STATE
                        putExtra("playing", call.argument<Boolean>("playing") ?: false)
                        putExtra("buffering", call.argument<Boolean>("buffering") ?: false)
                        putExtra("positionMs", call.argument<Number>("positionMs")?.toLong() ?: 0L)
                        putExtra("durationMs", call.argument<Number>("durationMs")?.toLong() ?: 0L)
                        putExtra("speed", call.argument<Number>("speed")?.toDouble() ?: 1.0)
                        putExtra("title", call.argument<String>("title") ?: "")
                        putExtra("artist", call.argument<String>("artist") ?: "")
                        putExtra("album", call.argument<String>("album") ?: "")
                        putExtra("artPath", call.argument<String>("artPath"))
                        putExtra("queueIndex", call.argument<Int>("queueIndex"))
                        putExtra("queueSize", call.argument<Int>("queueSize") ?: 0)
                    }
                    val playing = call.argument<Boolean>("playing") ?: false
                    if (playing) {
                        ContextCompat.startForegroundService(this, intent)
                    } else {
                        startService(intent)
                    }
                    result.success(null)
                }
                "clear" -> {
                    val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    notificationManager.cancel(AetherfinMediaSessionService.NOTIFICATION_ID)
                    val intent = Intent(this, AetherfinMediaSessionService::class.java)
                    stopService(intent)
                    result.success(null)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onDestroy() {
        mediaSessionChannel?.setMethodCallHandler(null)
        // Keep mediaSessionChannel reference alive across Activity recreation
        // so AetherfinMediaSessionService commands are not silently dropped.
        // The reference is overwritten on the next configureFlutterEngine call.
        super.onDestroy()
    }
}
