package dev.aetherfin.aetherfin.visualizer

import android.media.audiofx.Visualizer
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.sqrt

/**
 * Bridges Android's [android.media.audiofx.Visualizer] into Flutter so
 * the Now Playing screen can drive a real-time FFT-based artwork pulse.
 *
 * ## Channels
 *
 * MethodChannel `aetherfin.visualizer`:
 *   - `attach(audioSessionId: Int)` — attach the Visualizer to the given
 *     ExoPlayer audio session. Safe to call multiple times; re-attaches
 *     cleanly. Returns `true` on success, `false` if the session ID is
 *     invalid or RECORD_AUDIO permission is missing.
 *   - `detach()` — release the Visualizer. Called on pause / stop / dispose.
 *
 * EventChannel `aetherfin.visualizer/fft`:
 *   - Emits a [Double] in [0.0, 1.0] on every Visualizer capture (~60 Hz).
 *     The value is the RMS magnitude of the low-to-mid FFT bins (roughly
 *     20 Hz – 4 kHz), normalised against a rolling peak so the scale
 *     adapts to the track's loudness rather than being fixed.
 *
 * ## Threading
 *
 * [Visualizer.OnDataCaptureListener] fires on a native audio thread.
 * We post results to the main thread via [Handler] before calling
 * [EventChannel.EventSink.success] — Flutter's EventChannel sink is not
 * thread-safe.
 */
class VisualizerPlugin : FlutterPlugin, MethodCallHandler {

    companion object {
        const val METHOD_CHANNEL = "aetherfin.visualizer"
        const val EVENT_CHANNEL  = "aetherfin.visualizer/fft"

        /** Capture size must be a power of two in [Visualizer.getCaptureSizeRange()].
         *  256 gives 128 FFT bins at ~43 Hz/bin for 44.1 kHz audio — enough
         *  resolution to isolate the bass/mid energy without heavy allocation. */
        private const val CAPTURE_SIZE = 256

        /** Capture rate in millihertz. 60_000_000 mHz = 60 Hz. */
        private const val CAPTURE_RATE_MHZ = 60_000_000

        /** Number of low-to-mid bins to average (bins 1..LOW_MID_BINS).
         *  Bin 0 is DC; bins 1..32 cover ~43 Hz – 1.4 kHz at 44.1 kHz / 256. */
        private const val LOW_MID_BINS = 32

        /** Rolling peak decay per frame (multiplicative). 0.97 ≈ half-life ~23
         *  frames at 60 Hz, which gives a ~0.4 s adaptation window. */
        private const val PEAK_DECAY = 0.97f

        /** Minimum peak floor so we never divide by zero and the artwork
         *  still pulses gently on near-silence. */
        private const val PEAK_FLOOR = 0.01f
    }

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    private var visualizer: Visualizer? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    /** Rolling peak for normalisation — decays toward PEAK_FLOOR each frame. */
    @Volatile private var rollingPeak = PEAK_FLOOR

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

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "attach" -> {
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
                        mainHandler.post {
                            eventSink?.success(magnitude)
                        }
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

    /**
     * Compute a normalised [0.0, 1.0] magnitude from the FFT byte array
     * returned by [Visualizer].
     *
     * Android's Visualizer FFT format (from the docs):
     *   fft[0] = Re[0]  (DC component, real only)
     *   fft[1] = Re[N/2] (Nyquist, real only)
     *   fft[2k]   = Re[k]  for k = 1 .. N/2-1
     *   fft[2k+1] = Im[k]  for k = 1 .. N/2-1
     *
     * We compute the RMS of the magnitudes of bins 1..LOW_MID_BINS,
     * then normalise against a rolling peak so the output adapts to the
     * track's loudness level.
     */
    private fun computeMagnitude(fft: ByteArray): Double {
        var sumSq = 0.0
        val bins = minOf(LOW_MID_BINS, fft.size / 2 - 1)
        for (k in 1..bins) {
            val re = fft[2 * k].toFloat()
            val im = fft[2 * k + 1].toFloat()
            sumSq += (re * re + im * im).toDouble()
        }
        val rms = sqrt(sumSq / bins).toFloat()

        // Update rolling peak with decay.
        rollingPeak = max(PEAK_FLOOR, max(rms, rollingPeak * PEAK_DECAY))

        // Normalise and clamp.
        return (rms / rollingPeak).toDouble().coerceIn(0.0, 1.0)
    }
}
