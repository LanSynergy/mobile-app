package dev.aetherfin.aetherfin.visualizer

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.media.audiofx.Visualizer
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import kotlin.math.max
import kotlin.math.sqrt

/**
 * Bridges Android's [android.media.audiofx.Visualizer] into Flutter.
 *
 * ## Permission handling
 *
 * [Visualizer] requires `RECORD_AUDIO` at runtime on Android 6+. The
 * permission is declared in AndroidManifest.xml; this plugin also handles
 * the runtime request/check flow so the Dart side never has to import a
 * separate permission package.
 *
 * ## Channels
 *
 * MethodChannel `aetherfin.visualizer`:
 *   - `hasPermission() → Boolean` — true if RECORD_AUDIO is granted.
 *   - `requestPermission() → Boolean` — requests the permission and
 *     returns the result. Resolves immediately if already granted.
 *   - `attach(audioSessionId: Int) → Boolean` — attach the Visualizer.
 *     Returns false if permission is missing or the session ID is invalid.
 *   - `detach() → void` — release the Visualizer.
 *
 * EventChannel `aetherfin.visualizer/fft`:
 *   - Emits a [Double] in [0.0, 1.0] at ~60 Hz while attached.
 */
class VisualizerPlugin : FlutterPlugin, MethodCallHandler, ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {

    companion object {
        const val METHOD_CHANNEL = "aetherfin.visualizer"
        const val EVENT_CHANNEL  = "aetherfin.visualizer/fft"

        private const val CAPTURE_SIZE      = 256
        private const val CAPTURE_RATE_MHZ  = 60_000_000
        private const val LOW_MID_BINS      = 32
        private const val PEAK_DECAY        = 0.97f
        private const val PEAK_FLOOR        = 0.01f
        private const val PERMISSION_REQ_ID = 0xAF_01
    }

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    private var visualizer: Visualizer? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private var activity: Activity? = null
    // Pending result for an in-flight requestPermission() call.
    private var permissionResult: Result? = null

    @Volatile private var rollingPeak = PEAK_FLOOR

    // -------------------------------------------------------------------------
    // FlutterPlugin
    // -------------------------------------------------------------------------

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL).also {
            it.setMethodCallHandler(this)
        }
        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL).also {
            it.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                    eventSink = sink
                }
                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        releaseVisualizer()
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        eventChannel?.setStreamHandler(null)
        eventChannel = null
        eventSink = null
    }

    // -------------------------------------------------------------------------
    // ActivityAware
    // -------------------------------------------------------------------------

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    // -------------------------------------------------------------------------
    // PluginRegistry.RequestPermissionsResultListener
    // -------------------------------------------------------------------------

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != PERMISSION_REQ_ID) return false
        val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
        permissionResult?.success(granted)
        permissionResult = null
        return true
    }

    // -------------------------------------------------------------------------
    // MethodCallHandler
    // -------------------------------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "hasPermission" -> result.success(hasRecordAudio())

            "requestPermission" -> {
                if (hasRecordAudio()) {
                    result.success(true)
                    return
                }
                val act = activity
                if (act == null) {
                    // No activity — can't show the dialog. Return false so
                    // the Dart side falls back gracefully.
                    result.success(false)
                    return
                }
                permissionResult = result
                ActivityCompat.requestPermissions(
                    act,
                    arrayOf(Manifest.permission.RECORD_AUDIO),
                    PERMISSION_REQ_ID,
                )
                // Result delivered via onRequestPermissionsResult.
            }

            "attach" -> {
                if (!hasRecordAudio()) {
                    result.success(false)
                    return
                }
                val sessionId = call.arguments as? Int
                if (sessionId == null || sessionId < 0) {
                    result.success(false)
                    return
                }
                result.success(attachVisualizer(sessionId))
            }

            "detach" -> {
                releaseVisualizer()
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    // -------------------------------------------------------------------------
    // Internals
    // -------------------------------------------------------------------------

    private fun hasRecordAudio(): Boolean {
        val ctx = activity ?: return false
        return ContextCompat.checkSelfPermission(
            ctx, Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun attachVisualizer(audioSessionId: Int): Boolean {
        releaseVisualizer()
        return try {
            val v = Visualizer(audioSessionId)
            val range = Visualizer.getCaptureSizeRange()
            val size = CAPTURE_SIZE.coerceIn(range[0], range[1])
            v.captureSize = size
            v.setDataCaptureListener(
                object : Visualizer.OnDataCaptureListener {
                    override fun onWaveFormDataCapture(
                        vis: Visualizer, waveform: ByteArray, samplingRate: Int
                    ) { /* unused */ }

                    override fun onFftDataCapture(
                        vis: Visualizer, fft: ByteArray, samplingRate: Int
                    ) {
                        val magnitude = computeMagnitude(fft)
                        mainHandler.post { eventSink?.success(magnitude) }
                    }
                },
                CAPTURE_RATE_MHZ,
                /* waveform = */ false,
                /* fft = */ true,
            )
            v.enabled = true
            visualizer = v
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun releaseVisualizer() {
        try {
            visualizer?.enabled = false
            visualizer?.release()
        } catch (_: Exception) {}
        visualizer = null
        rollingPeak = PEAK_FLOOR
    }

    private fun computeMagnitude(fft: ByteArray): Double {
        var sumSq = 0.0
        val bins = minOf(LOW_MID_BINS, fft.size / 2 - 1)
        for (k in 1..bins) {
            val re = fft[2 * k].toFloat()
            val im = fft[2 * k + 1].toFloat()
            sumSq += (re * re + im * im).toDouble()
        }
        val rms = sqrt(sumSq / bins).toFloat()
        rollingPeak = max(PEAK_FLOOR, max(rms, rollingPeak * PEAK_DECAY))
        return (rms / rollingPeak).toDouble().coerceIn(0.0, 1.0)
    }
}
