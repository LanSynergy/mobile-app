package dev.aetherfin.aetherfin.battery

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * Exposes Android battery-optimization exemption to Flutter.
 *
 * MethodChannel: `aetherfin.battery_opt`
 *
 * Methods:
 *   - `isIgnoringBatteryOptimizations() -> Boolean`
 *       Returns true if the app is already exempt from battery
 *       optimizations (i.e. the user has already granted it, or the
 *       device doesn't enforce Doze for this app).
 *
 *   - `requestIgnoreBatteryOptimizations() -> Boolean`
 *       Fires ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS so the system
 *       shows the "Allow background activity?" dialog. Returns true if
 *       the intent was dispatched, false if the activity is unavailable
 *       or the app is already exempt.
 *       Requires REQUEST_IGNORE_BATTERY_OPTIMIZATIONS in the manifest.
 */
class BatteryOptPlugin : FlutterPlugin, ActivityAware, MethodCallHandler {

    companion object {
        const val CHANNEL_NAME = "aetherfin.battery_opt"
    }

    private var channel: MethodChannel? = null
    private var appContext: Context? = null
    private var activityBinding: ActivityPluginBinding? = null

    // ── FlutterPlugin ────────────────────────────────────────────────────────

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        appContext = null
    }

    // ── ActivityAware ────────────────────────────────────────────────────────

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activityBinding = binding
    }

    override fun onDetachedFromActivity() {
        activityBinding = null
    }

    // ── MethodCallHandler ────────────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "isIgnoringBatteryOptimizations" -> {
                result.success(isIgnoring())
            }
            "requestIgnoreBatteryOptimizations" -> {
                if (isIgnoring()) {
                    // Already exempt — nothing to do.
                    result.success(false)
                    return
                }
                val activity = activityBinding?.activity
                if (activity == null) {
                    result.success(false)
                    return
                }
                try {
                    val intent = Intent(
                        Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                        Uri.parse("package:${activity.packageName}"),
                    )
                    activity.startActivity(intent)
                    result.success(true)
                } catch (e: Exception) {
                    // Some OEMs remove this settings screen entirely.
                    // Fall back to the general battery settings page.
                    try {
                        activity.startActivity(
                            Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                        )
                        result.success(true)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    private fun isIgnoring(): Boolean {
        val ctx = appContext ?: return false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pm = ctx.getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(ctx.packageName)
    }
}
