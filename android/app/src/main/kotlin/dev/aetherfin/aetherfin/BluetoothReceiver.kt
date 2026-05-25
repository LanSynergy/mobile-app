package dev.aetherfin.aetherfin

import android.bluetooth.BluetoothDevice
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class BluetoothReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val intentAction = intent.action ?: return
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

        when (intentAction) {
            BluetoothDevice.ACTION_ACL_CONNECTED -> {
                val autoPlay = prefs.getBoolean("flutter.autoPlayOnBluetooth", false)
                if (autoPlay) {
                    val playIntent = Intent(context, AetherfinMediaSessionService::class.java).apply {
                        action = Intent.ACTION_MEDIA_BUTTON
                        putExtra(Intent.EXTRA_KEY_EVENT, android.view.KeyEvent(
                            android.view.KeyEvent.ACTION_DOWN,
                            android.view.KeyEvent.KEYCODE_MEDIA_PLAY
                        ))
                    }
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            context.startForegroundService(playIntent)
                        } else {
                            context.startService(playIntent)
                        }
                    } catch (e: Exception) {
                        // Ignore
                    }
                }
            }
            BluetoothDevice.ACTION_ACL_DISCONNECTED -> {
                val autoPause = prefs.getBoolean("flutter.autoPauseOnBluetooth", true)
                if (autoPause) {
                    val pauseIntent = Intent(context, AetherfinMediaSessionService::class.java).apply {
                        action = Intent.ACTION_MEDIA_BUTTON
                        putExtra(Intent.EXTRA_KEY_EVENT, android.view.KeyEvent(
                            android.view.KeyEvent.ACTION_DOWN,
                            android.view.KeyEvent.KEYCODE_MEDIA_PAUSE
                        ))
                    }
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            context.startForegroundService(pauseIntent)
                        } else {
                            context.startService(pauseIntent)
                        }
                    } catch (e: Exception) {
                        // Ignore
                    }
                }
            }
        }
    }
}
