package dev.aetherfin.aetherfin

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.support.v4.media.session.PlaybackStateCompat
import android.widget.RemoteViews
import androidx.palette.graphics.Palette
import androidx.core.graphics.ColorUtils
import java.io.File

class AetherfinAppWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        super.onUpdate(context, appWidgetManager, appWidgetIds)
        for (appWidgetId in appWidgetIds) {
            updateWidgetFromPrefs(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        // Update on any broadcast (from Flutter HomeWidget.updateWidget or manual)
        val appWidgetManager = AppWidgetManager.getInstance(context)
        val thisWidget = ComponentName(context, AetherfinAppWidgetProvider::class.java)
        val appWidgetIds = appWidgetManager.getAppWidgetIds(thisWidget)

        for (appWidgetId in appWidgetIds) {
            updateWidgetFromPrefs(context, appWidgetManager, appWidgetId)
        }
    }

    private fun updateWidgetFromPrefs(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
        val prefs = try {
            context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        } catch (e: Exception) {
            context.getSharedPreferences(context.packageName + "_preferences", Context.MODE_PRIVATE)
        }

        val title = prefs.getString("flutter.title", null) ?: "Not Playing"
        val artist = prefs.getString("flutter.artist", null) ?: ""
        val playing = prefs.getString("flutter.playing", "false") == "true"
        val artPath = prefs.getString("flutter.artPath", null)
        val isFavorite = prefs.getString("flutter.isFavorite", "false") == "true"

        val views = RemoteViews(context.packageName, R.layout.aetherfin_widget)

        // Text
        views.setTextViewText(R.id.widget_title, title)
        views.setTextViewText(R.id.widget_artist, artist)

        // Play/Pause icon
        views.setImageViewResource(
            R.id.widget_play_pause,
            if (playing) R.drawable.ic_widget_pause else R.drawable.ic_widget_play
        )

        // Favorite icon
        views.setImageViewResource(
            R.id.widget_favorite,
            if (isFavorite) R.drawable.ic_widget_heart_filled else R.drawable.ic_widget_heart
        )

        // Artwork + dynamic background
        var widgetBgColor = 0xFF1A1A2E.toInt() // default dark
        if (!artPath.isNullOrEmpty()) {
            try {
                val file = File(artPath)
                if (file.exists()) {
                    val bitmap = BitmapFactory.decodeFile(file.absolutePath)
                    if (bitmap != null) {
                        views.setImageViewBitmap(R.id.widget_album_art, bitmap)
                        val palette = Palette.from(bitmap).generate()
                        widgetBgColor = palette.getMutedColor(0xFF1A1A2E.toInt())
                    } else {
                        views.setImageViewResource(R.id.widget_album_art, R.drawable.ic_music_note)
                    }
                } else {
                    views.setImageViewResource(R.id.widget_album_art, R.drawable.ic_music_note)
                }
            } catch (e: Exception) {
                views.setImageViewResource(R.id.widget_album_art, R.drawable.ic_music_note)
            }
        } else {
            views.setImageViewResource(R.id.widget_album_art, R.drawable.ic_music_note)
        }

        // Apply dynamic background — darken the palette color for widget bg
        val darkenedBg = ColorUtils.blendARGB(widgetBgColor, 0xFF0A0A14.toInt(), 0.6f)
        views.setInt(R.id.widget_root, "setBackgroundColor", darkenedBg)

        // Dynamic contrast text
        val isDark = ColorUtils.calculateLuminance(darkenedBg) < 0.5
        val titleColor = if (isDark) 0xFFFFFFFF.toInt() else 0xFF000000.toInt()
        val artistColor = if (isDark) 0xBBFFFFFF.toInt() else 0xFF444444.toInt()
        views.setTextColor(R.id.widget_title, titleColor)
        views.setTextColor(R.id.widget_artist, artistColor)

        // Controls
        views.setOnClickPendingIntent(R.id.widget_play_pause, getMediaButtonIntent(context, PlaybackStateCompat.ACTION_PLAY_PAUSE))
        views.setOnClickPendingIntent(R.id.widget_prev, getMediaButtonIntent(context, PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS))
        views.setOnClickPendingIntent(R.id.widget_next, getMediaButtonIntent(context, PlaybackStateCompat.ACTION_SKIP_TO_NEXT))
        views.setOnClickPendingIntent(R.id.widget_favorite, getServiceBroadcastIntent(context, AetherfinMediaSessionService.ACTION_TOGGLE_FAVORITE))

        // Open app on artwork or text tap
        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val launchPi = PendingIntent.getActivity(
            context, 0, launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.widget_album_art, launchPi)
        views.setOnClickPendingIntent(R.id.widget_title, launchPi)

        appWidgetManager.updateAppWidget(appWidgetId, views)
    }

    private fun getMediaButtonIntent(context: Context, action: Long): PendingIntent {
        val intent = Intent(context, AetherfinMediaSessionService::class.java).apply {
            this.action = Intent.ACTION_MEDIA_BUTTON
            putExtra(Intent.EXTRA_KEY_EVENT, android.view.KeyEvent(
                android.view.KeyEvent.ACTION_DOWN,
                when (action) {
                    PlaybackStateCompat.ACTION_PLAY_PAUSE -> android.view.KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
                    PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS -> android.view.KeyEvent.KEYCODE_MEDIA_PREVIOUS
                    PlaybackStateCompat.ACTION_SKIP_TO_NEXT -> android.view.KeyEvent.KEYCODE_MEDIA_NEXT
                    else -> android.view.KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
                }
            ))
        }
        return PendingIntent.getService(
            context,
            action.toInt(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun getServiceBroadcastIntent(context: Context, customAction: String): PendingIntent {
        val intent = Intent(context, AetherfinMediaSessionService::class.java).apply {
            this.action = customAction
        }
        return PendingIntent.getService(
            context,
            customAction.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
}
