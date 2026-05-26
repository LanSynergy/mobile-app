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
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        val action = intent.action
        if (action == AetherfinMediaSessionService.ACTION_UPDATE_STATE || action == AppWidgetManager.ACTION_APPWIDGET_UPDATE) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val thisWidget = ComponentName(context, AetherfinAppWidgetProvider::class.java)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(thisWidget)

            val title = intent.getStringExtra("title")
            val artist = intent.getStringExtra("artist")
            val playing = intent.getBooleanExtra("playing", false)
            val artPath = intent.getStringExtra("artPath")
            val isFavorite = intent.getBooleanExtra("isFavorite", false)

            for (appWidgetId in appWidgetIds) {
                val views = RemoteViews(context.packageName, R.layout.aetherfin_widget)
                if (title != null) {
                    views.setTextViewText(R.id.widget_title, title)
                }
                if (artist != null) {
                    views.setTextViewText(R.id.widget_artist, artist)
                }
                
                // Play/Pause icon sync
                if (playing) {
                    views.setImageViewResource(R.id.widget_play_pause, android.R.drawable.ic_media_pause)
                } else {
                    views.setImageViewResource(R.id.widget_play_pause, android.R.drawable.ic_media_play)
                }

                // Favorite icon sync
                if (isFavorite) {
                    views.setImageViewResource(R.id.widget_favorite, android.R.drawable.btn_star_big_on)
                } else {
                    views.setImageViewResource(R.id.widget_favorite, android.R.drawable.btn_star_big_off)
                }

                // Artwork sync & Palette coloring
                var widgetBgColor = 0xFF251F58.toInt() // default purple
                if (!artPath.isNullOrEmpty()) {
                    try {
                        val file = File(artPath)
                        if (file.exists()) {
                            val bitmap = BitmapFactory.decodeFile(file.absolutePath)
                            if (bitmap != null) {
                                views.setImageViewBitmap(R.id.widget_album_art, bitmap)
                                
                                // Extract colors using Palette API
                                val palette = Palette.from(bitmap).generate()
                                widgetBgColor = palette.getMutedColor(0xFF251F58.toInt())
                            } else {
                                views.setImageViewResource(R.id.widget_album_art, android.R.drawable.ic_menu_gallery)
                            }
                        } else {
                            views.setImageViewResource(R.id.widget_album_art, android.R.drawable.ic_menu_gallery)
                        }
                    } catch (e: Exception) {
                        views.setImageViewResource(R.id.widget_album_art, android.R.drawable.ic_menu_gallery)
                    }
                } else {
                    views.setImageViewResource(R.id.widget_album_art, android.R.drawable.ic_menu_gallery)
                }

                // Apply background color dynamically
                views.setInt(R.id.widget_root, "setBackgroundColor", widgetBgColor)
                
                // Dynamic contrast text styling
                val isDark = ColorUtils.calculateLuminance(widgetBgColor) < 0.5
                val titleColor = if (isDark) 0xFFFFFFFF.toInt() else 0xFF000000.toInt()
                val artistColor = if (isDark) 0xFFAAAAAA.toInt() else 0xFF444444.toInt()
                views.setTextColor(R.id.widget_title, titleColor)
                views.setTextColor(R.id.widget_artist, artistColor)

                // Controls wiring
                views.setOnClickPendingIntent(R.id.widget_play_pause, getMediaButtonIntent(context, PlaybackStateCompat.ACTION_PLAY_PAUSE))
                views.setOnClickPendingIntent(R.id.widget_prev, getMediaButtonIntent(context, PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS))
                views.setOnClickPendingIntent(R.id.widget_next, getMediaButtonIntent(context, PlaybackStateCompat.ACTION_SKIP_TO_NEXT))
                views.setOnClickPendingIntent(R.id.widget_favorite, getServiceBroadcastIntent(context, AetherfinMediaSessionService.ACTION_TOGGLE_FAVORITE))

                appWidgetManager.updateAppWidget(appWidgetId, views)
            }
        }
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

    private fun updateAppWidget(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
        val views = RemoteViews(context.packageName, R.layout.aetherfin_widget)
        // Setup initial default views
        views.setOnClickPendingIntent(R.id.widget_play_pause, getMediaButtonIntent(context, PlaybackStateCompat.ACTION_PLAY_PAUSE))
        views.setOnClickPendingIntent(R.id.widget_prev, getMediaButtonIntent(context, PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS))
        views.setOnClickPendingIntent(R.id.widget_next, getMediaButtonIntent(context, PlaybackStateCompat.ACTION_SKIP_TO_NEXT))
        views.setOnClickPendingIntent(R.id.widget_favorite, getServiceBroadcastIntent(context, AetherfinMediaSessionService.ACTION_TOGGLE_FAVORITE))

        appWidgetManager.updateAppWidget(appWidgetId, views)
    }
}
