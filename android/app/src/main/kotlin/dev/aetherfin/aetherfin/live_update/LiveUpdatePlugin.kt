package dev.aetherfin.aetherfin.live_update

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.graphics.Color
import android.os.Build
import androidx.core.content.ContextCompat

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * Bridge between the Flutter side (`lib/core/audio/live_update_service.dart`)
 * and Android 16's "Live Updates" / Promoted Ongoing Notifications API.
 *
 * On Android 16 (API 36) and newer, this plugin publishes a separate
 * `Notification.ProgressStyle` notification that requests promotion via
 * `setRequestPromotedOngoing(true)`. The system surfaces it as a
 * status-bar chip and a prominent lock-screen tile while playback is
 * ongoing.
 *
 * On Android 15 and older, every method is a no-op. The existing
 * `audio_service` `MediaStyle` notification continues to render unchanged
 * on those devices (and *also* on Android 16 — the two notifications are
 * complementary: ProgressStyle for the chip, MediaStyle for the
 * expanded shade with transport controls).
 *
 * Why not promote the `MediaStyle` notification itself? Per the Live
 * Updates documentation, only the following styles qualify for
 * promotion: Standard, BigTextStyle, CallStyle, ProgressStyle,
 * MetricStyle. `MediaStyle` is intentionally not in that list. A
 * notification can only have one Style, so we run a parallel
 * ProgressStyle notification rather than mutate `audio_service`'s.
 *
 * MethodChannel: `aetherfin.live_update`
 *
 * Methods:
 *   - `isSupported() -> Boolean` — true on API 36+, false otherwise.
 *   - `start(args) -> Void` — post the live update for the first time.
 *   - `update(args) -> Void` — refresh the existing notification's
 *     position / playing state. No-op if `start` hasn't been called.
 *   - `stop() -> Void` — cancel the notification.
 *
 * `args` shape (Map<String, Object>):
 *   - `title`: String — track title (shown as contentTitle)
 *   - `artist`: String — artist name (shown as contentText)
 *   - `durationMs`: Long — total track length, > 0
 *   - `positionMs`: Long — current playback position, [0, durationMs]
 *   - `isPlaying`: Boolean — whether the track is actively playing
 *   - `shortCriticalText`: String — formatted "M:SS / M:SS", shown on
 *     the status-bar chip when there's room
 */
class LiveUpdatePlugin : FlutterPlugin, MethodCallHandler {

    companion object {
        private const val CHANNEL_NAME = "aetherfin.live_update"
        private const val NOTIFICATION_CHANNEL_ID = "aetherfin.live_update"
        private const val NOTIFICATION_CHANNEL_NAME = "Now Playing (Live Update)"
        private const val NOTIFICATION_ID = 0x4146_1701 // "AF" + arbitrary

        /** Android 16. Matches `Build.VERSION_CODES.BAKLAVA` on SDKs that
         *  expose the constant; using the int literal keeps this file
         *  compilable on older `compileSdk` while still gating correctly
         *  at runtime. */
        private const val SDK_LIVE_UPDATES = 36

        /** Don't post a notification update more than once every 5
         *  seconds — that's the rate cap the platform documentation
         *  recommends. The Dart side already throttles, but this is a
         *  defensive lower bound in case it stops throttling. */
        private const val MIN_UPDATE_INTERVAL_MS = 5_000L
    }

    private var channel: MethodChannel? = null
    private var appContext: Context? = null
    private var lastPostMs: Long = 0L
    private var isLive: Boolean = false

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

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "isSupported" -> result.success(Build.VERSION.SDK_INT >= SDK_LIVE_UPDATES)
            "start" -> {
                if (!isApiSupported()) {
                    result.success(false); return
                }
                val args = call.arguments as? Map<*, *>
                if (args == null) {
                    result.error("ARGS", "expected a map argument", null); return
                }
                if (!hasPostNotificationsPermission()) {
                    // Without runtime POST_NOTIFICATIONS, the system silently
                    // drops the notification. Report it explicitly so the
                    // Dart side can request the permission and retry.
                    result.success(false); return
                }
                ensureNotificationChannel()
                lastPostMs = 0L
                isLive = true
                postNotification(args, force = true)
                result.success(true)
            }
            "update" -> {
                if (!isLive || !isApiSupported()) {
                    result.success(false); return
                }
                val args = call.arguments as? Map<*, *>
                if (args == null) {
                    result.error("ARGS", "expected a map argument", null); return
                }
                postNotification(args, force = false)
                result.success(true)
            }
            "stop" -> {
                cancelNotification()
                isLive = false
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // ----------------------------------------------------------------------
    // Internals
    // ----------------------------------------------------------------------

    private fun isApiSupported(): Boolean = Build.VERSION.SDK_INT >= SDK_LIVE_UPDATES

    private fun hasPostNotificationsPermission(): Boolean {
        val ctx = appContext ?: return false
        if (Build.VERSION.SDK_INT < 33) return true
        return ContextCompat.checkSelfPermission(
            ctx,
            "android.permission.POST_NOTIFICATIONS",
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun ensureNotificationChannel() {
        val ctx = appContext ?: return
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(NOTIFICATION_CHANNEL_ID) != null) return
        // IMPORTANCE_LOW: no sound or pop-up, but the notification still
        // shows in the shade and is eligible for Live-Update promotion
        // (IMPORTANCE_MIN would disqualify it per the docs).
        val channel = NotificationChannel(
            NOTIFICATION_CHANNEL_ID,
            NOTIFICATION_CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Status-bar chip and lock-screen tile showing the currently playing track."
            setShowBadge(false)
        }
        nm.createNotificationChannel(channel)
    }

    /**
     * Build and post the ProgressStyle notification. Idempotent — re-posts
     * are gated by the [MIN_UPDATE_INTERVAL_MS] throttle unless [force].
     */
    @Suppress("DEPRECATION") // Notification.ProgressStyle is API 36+ only.
    private fun postNotification(args: Map<*, *>, force: Boolean) {
        val ctx = appContext ?: return
        if (Build.VERSION.SDK_INT < SDK_LIVE_UPDATES) return

        val now = System.currentTimeMillis()
        if (!force && now - lastPostMs < MIN_UPDATE_INTERVAL_MS) return
        lastPostMs = now

        val title = (args["title"] as? String)?.takeIf { it.isNotEmpty() } ?: "Now playing"
        val artist = (args["artist"] as? String) ?: ""
        val durationMs = (args["durationMs"] as? Number)?.toLong()?.coerceAtLeast(1L) ?: 1L
        val positionMs = (args["positionMs"] as? Number)?.toLong()?.coerceIn(0L, durationMs) ?: 0L
        val isPlaying = (args["isPlaying"] as? Boolean) ?: true
        val shortCriticalText = (args["shortCriticalText"] as? String) ?: ""
        val artworkPath = args["artworkPath"] as? String

        val contentIntent = buildContentIntent(ctx)

        // Load artwork bitmap for the large icon (shown in the chip).
        val largeIcon = if (artworkPath != null) {
            try {
                BitmapFactory.decodeFile(artworkPath)
            } catch (_: Exception) {
                null
            }
        } else null

        // Reflection-free reference: Notification.ProgressStyle is API 36+;
        // we already gated on SDK_INT above so the linker won't trip.
        val style = Notification.ProgressStyle()
            .setStyledByProgress(true)
            .setProgress(positionMs.toInt())
            .addProgressSegment(
                Notification.ProgressStyle.Segment(durationMs.toInt())
                    .setColor(if (isPlaying) Color.parseColor("#5644C9") else Color.parseColor("#9B9BAA"))
            )

        val builder = Notification.Builder(ctx, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(ctx.applicationInfo.icon.takeIf { it != 0 }
                ?: android.R.drawable.ic_media_play)
            .setContentTitle(title)
            .setContentText(artist)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setStyle(style)
            .setContentIntent(contentIntent)
            // The chip needs SOMETHING textual to show alongside the
            // small icon. "M:SS / M:SS" reads naturally and fits within
            // the chip's 96dp width as long as durations are < 100min.
            .setShortCriticalText(shortCriticalText)

        // Set large icon (artwork) for the chip and notification.
        if (largeIcon != null) {
            builder.setLargeIcon(largeIcon)
        }

        // Promotion request — the system decides whether to honour it based on
        // Live-Updates settings + OEM policy. We can't call
        // `builder.setRequestPromotedOngoing(true)` directly because that method
        // landed in API 36.1 (Notification.Builder diff 36 → 36.1) and Flutter
        // 3.41.9 pins compileSdk to 36.0. The platform reads the same flag via
        // the documented Notification.EXTRA_REQUEST_PROMOTED_ONGOING string
        // ("android.requestPromotedOngoing") on every API 36+ build, so set it
        // directly on the extras Bundle. The constant value is part of the
        // Android public API contract; the *Java symbol* exposing it is the
        // thing that's gated on 36.1+.
        builder.extras.putBoolean("android.requestPromotedOngoing", true)

        val notification = builder.build()
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIFICATION_ID, notification)
    }

    private fun cancelNotification() {
        val ctx = appContext ?: return
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(NOTIFICATION_ID)
    }

    /** Tapping the chip launches the app (singleTop, like a deep-link). */
    private fun buildContentIntent(ctx: Context): PendingIntent {
        val launch = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)
            ?: Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
                .setPackage(ctx.packageName)
        launch.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        return PendingIntent.getActivity(
            ctx,
            0,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
