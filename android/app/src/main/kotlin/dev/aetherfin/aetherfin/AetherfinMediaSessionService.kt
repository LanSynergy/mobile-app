package dev.aetherfin.aetherfin

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.os.IBinder
import android.os.SystemClock
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import androidx.core.app.NotificationCompat
import androidx.media.session.MediaButtonReceiver
import java.io.File

class AetherfinMediaSessionService : Service() {

    companion object {
        const val ACTION_UPDATE_STATE = "dev.aetherfin.aetherfin.UPDATE_STATE"
        const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "dev.aetherfin.audio"
    }

    private var mediaSession: MediaSessionCompat? = null

    private val mediaSessionCallback = object : MediaSessionCompat.Callback() {
        override fun onPlay() {
            sendCommandToFlutter("play")
        }

        override fun onPause() {
            sendCommandToFlutter("pause")
        }

        override fun onSkipToNext() {
            sendCommandToFlutter("next")
        }

        override fun onSkipToPrevious() {
            sendCommandToFlutter("previous")
        }

        override fun onStop() {
            sendCommandToFlutter("stop")
            stopSelf()
        }

        override fun onSeekTo(pos: Long) {
            sendCommandToFlutter("seek", mapOf("positionMs" to pos))
        }

        override fun onSkipToQueueItem(id: Long) {
            sendCommandToFlutter("skipTo", mapOf("queueIndex" to id.toInt()))
        }
    }

    override fun onCreate() {
        super.onCreate()
        
        mediaSession = MediaSessionCompat(this, "AetherfinMediaSession").apply {
            setCallback(mediaSessionCallback)
            setFlags(MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS or MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS)
            isActive = true
            
            // Set session activity intent
            val intent = Intent(this@AetherfinMediaSessionService, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            val pendingIntent = PendingIntent.getActivity(
                this@AetherfinMediaSessionService,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            setSessionActivity(pendingIntent)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent != null && intent.action == ACTION_UPDATE_STATE) {
            val playing = intent.getBooleanExtra("playing", false)
            val buffering = intent.getBooleanExtra("buffering", false)
            val positionMs = intent.getLongExtra("positionMs", 0L)
            val durationMs = intent.getLongExtra("durationMs", 0L)
            val speed = intent.getDoubleExtra("speed", 1.0)
            val title = intent.getStringExtra("title") ?: ""
            val artist = intent.getStringExtra("artist") ?: ""
            val album = intent.getStringExtra("album") ?: ""
            val artPath = intent.getStringExtra("artPath")
            val queueIndex = if (intent.hasExtra("queueIndex")) intent.getIntExtra("queueIndex", -1) else -1
            val queueSize = intent.getIntExtra("queueSize", 0)

            updateMediaSessionState(playing, buffering, positionMs, durationMs, speed, queueIndex, queueSize)
            updateMediaSessionMetadata(title, artist, album, durationMs, artPath, queueIndex)

            val notification = buildNotification(title, artist, album, playing, artPath, queueIndex > 0, queueIndex < queueSize - 1)
            
            if (playing) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    startForeground(NOTIFICATION_ID, notification, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
                } else {
                    startForeground(NOTIFICATION_ID, notification)
                }
            } else {
                // If paused, stop foreground to allow swiping notification away, but keep it visible
                stopForeground(false)
                val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.notify(NOTIFICATION_ID, notification)
            }
        }
        
        // Handle media buttons via receiver
        MediaButtonReceiver.handleIntent(mediaSession, intent)
        return START_NOT_STICKY
    }

    private fun updateMediaSessionState(
        playing: Boolean,
        buffering: Boolean,
        positionMs: Long,
        durationMs: Long,
        speed: Double,
        queueIndex: Int,
        queueSize: Int
    ) {
        val state = when {
            buffering -> PlaybackStateCompat.STATE_BUFFERING
            playing -> PlaybackStateCompat.STATE_PLAYING
            else -> PlaybackStateCompat.STATE_PAUSED
        }

        var actions = PlaybackStateCompat.ACTION_PLAY or
                PlaybackStateCompat.ACTION_PAUSE or
                PlaybackStateCompat.ACTION_PLAY_PAUSE or
                PlaybackStateCompat.ACTION_SEEK_TO

        if (queueIndex > 0) {
            actions = actions or PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS
        }
        if (queueIndex < queueSize - 1 && queueIndex >= 0) {
            actions = actions or PlaybackStateCompat.ACTION_SKIP_TO_NEXT
        }

        val stateBuilder = PlaybackStateCompat.Builder()
            .setActions(actions)
            .setState(state, positionMs, speed.toFloat(), SystemClock.elapsedRealtime())

        if (queueIndex >= 0) {
            stateBuilder.setActiveQueueItemId(queueIndex.toLong())
        }

        mediaSession?.setPlaybackState(stateBuilder.build())
    }

    private fun updateMediaSessionMetadata(
        title: String,
        artist: String,
        album: String,
        durationMs: Long,
        artPath: String?,
        queueIndex: Int
    ) {
        val metadataBuilder = MediaMetadataCompat.Builder()
            .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
            .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, artist)
            .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, album)
            .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, durationMs)

        if (queueIndex >= 0) {
            metadataBuilder.putLong(MediaMetadataCompat.METADATA_KEY_TRACK_NUMBER, queueIndex.toLong() + 1)
        }

        if (!artPath.isNullOrEmpty()) {
            try {
                val file = File(artPath)
                if (file.exists()) {
                    val bitmap = BitmapFactory.decodeFile(file.absolutePath)
                    if (bitmap != null) {
                        metadataBuilder.putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, bitmap)
                    }
                }
            } catch (e: Exception) {
                // Ignore
            }
        }

        mediaSession?.setMetadata(metadataBuilder.build())
    }

    private fun buildNotification(
        title: String,
        artist: String,
        album: String,
        playing: Boolean,
        artPath: String?,
        hasPrev: Boolean,
        hasNext: Boolean
    ): Notification {
        createNotificationChannel()

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(title)
            .setContentText(artist)
            .setSubText(album)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(playing)
            .setShowWhen(false)

        if (!artPath.isNullOrEmpty()) {
            try {
                val file = File(artPath)
                if (file.exists()) {
                    val bitmap = BitmapFactory.decodeFile(file.absolutePath)
                    if (bitmap != null) {
                        builder.setLargeIcon(bitmap)
                    }
                }
            } catch (e: Exception) {
                // Ignore
            }
        }

        // Action when content is clicked
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        builder.setContentIntent(pendingIntent)

        // Notification media control actions
        val prevIntent = MediaButtonReceiver.buildMediaButtonPendingIntent(this, PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS)
        val playPauseAction = if (playing) {
            NotificationCompat.Action(
                android.R.drawable.ic_media_pause,
                "Pause",
                MediaButtonReceiver.buildMediaButtonPendingIntent(this, PlaybackStateCompat.ACTION_PAUSE)
            )
        } else {
            NotificationCompat.Action(
                android.R.drawable.ic_media_play,
                "Play",
                MediaButtonReceiver.buildMediaButtonPendingIntent(this, PlaybackStateCompat.ACTION_PLAY)
            )
        }
        val nextIntent = MediaButtonReceiver.buildMediaButtonPendingIntent(this, PlaybackStateCompat.ACTION_SKIP_TO_NEXT)

        var actionCount = 0
        val compactIndices = ArrayList<Int>()

        if (hasPrev) {
            builder.addAction(android.R.drawable.ic_media_previous, "Previous", prevIntent)
            compactIndices.add(actionCount++)
        }

        builder.addAction(playPauseAction)
        compactIndices.add(actionCount++) // Play/Pause is always present

        if (hasNext) {
            builder.addAction(android.R.drawable.ic_media_next, "Next", nextIntent)
            compactIndices.add(actionCount++)
        }

        val style = androidx.media.app.NotificationCompat.MediaStyle()
            .setMediaSession(mediaSession?.sessionToken)
            .setShowActionsInCompactView(*compactIndices.toIntArray())

        builder.setStyle(style)
        return builder.build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "Aetherfin playback"
            val descriptionText = "Playback notification controls"
            val importance = NotificationManager.IMPORTANCE_LOW
            val channel = NotificationChannel(CHANNEL_ID, name, importance).apply {
                description = descriptionText
                setShowBadge(false)
                setSound(null, null)
                enableLights(false)
                enableVibration(false)
            }
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun sendCommandToFlutter(method: String, args: Any? = null) {
        MainActivity.mediaSessionChannel?.let { channel ->
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                try {
                    channel.invokeMethod(method, args)
                } catch (e: Exception) {
                    // Stale channel during Activity recreation — safe to ignore.
                }
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        sendCommandToFlutter("stop")
        stopSelf()
    }

    override fun onDestroy() {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(NOTIFICATION_ID)
        mediaSession?.apply {
            isActive = false
            release()
        }
        mediaSession = null
        super.onDestroy()
    }
}
