package dev.aetherfin.aetherfin.saf

import android.app.Activity
import android.content.Intent
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.provider.DocumentsContract
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import kotlinx.coroutines.*

/**
 * Platform channel for SAF (Storage Access Framework) operations.
 *
 * Methods:
 *   pickFolder()       → String? (tree URI)
 *   listAudioFiles(uri) → List<Map> (uri, name, size, lastModified)
 *   readMetadata(uri)  → Map (title, artist, album, etc.)
 *   readCoverArt(uri)  → ByteArray? (embedded cover art)
 */
class SafPlugin : FlutterPlugin, MethodChannel.MethodCallHandler,
    ActivityAware, PluginRegistry.ActivityResultListener {

    private lateinit var channel: MethodChannel
    private var activity: Activity? = null
    private var pendingResult: MethodChannel.Result? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    companion object {
        private const val CHANNEL = "aetherfin.saf"
        private const val PICK_FOLDER_REQUEST = 9001
        private val AUDIO_EXTENSIONS = setOf(
            "mp3", "flac", "opus", "ogg", "m4a", "wav", "aac", "wma",
            "alac", "aiff", "ape", "wv", "dsf", "dff"
        )
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        scope.cancel()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickFolder" -> pickFolder(result)
            "listAudioFiles" -> {
                val uri = call.argument<String>("uri")
                    ?: return result.error("INVALID_ARG", "uri required", null)
                scope.launch {
                    try {
                        val files = listAudioFiles(uri)
                        withContext(Dispatchers.Main) { result.success(files) }
                    } catch (e: Exception) {
                        withContext(Dispatchers.Main) {
                            result.error("SCAN_ERROR", e.message, null)
                        }
                    }
                }
            }
            "readMetadata" -> {
                val uri = call.argument<String>("uri")
                    ?: return result.error("INVALID_ARG", "uri required", null)
                scope.launch {
                    try {
                        val meta = readMetadata(uri)
                        withContext(Dispatchers.Main) { result.success(meta) }
                    } catch (e: Exception) {
                        withContext(Dispatchers.Main) {
                            result.error("META_ERROR", e.message, null)
                        }
                    }
                }
            }
            "readCoverArt" -> {
                val uri = call.argument<String>("uri")
                    ?: return result.error("INVALID_ARG", "uri required", null)
                scope.launch {
                    try {
                        val art = readCoverArt(uri)
                        withContext(Dispatchers.Main) { result.success(art) }
                    } catch (e: Exception) {
                        withContext(Dispatchers.Main) { result.success(null) }
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    // ── Folder picker ─────────────────────────────────────────────────────

    private fun pickFolder(result: MethodChannel.Result) {
        val act = activity
        if (act == null) {
            result.error("NO_ACTIVITY", "Activity not available", null)
            return
        }
        pendingResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
            )
        }
        act.startActivityForResult(intent, PICK_FOLDER_REQUEST)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PICK_FOLDER_REQUEST) return false
        val result = pendingResult ?: return true
        pendingResult = null

        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result.success(null)
            return true
        }

        val treeUri = data.data!!
        // Take persistent permission
        val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION
        activity?.contentResolver?.takePersistableUriPermission(treeUri, flags)

        result.success(treeUri.toString())
        return true
    }

    // ── List audio files ──────────────────────────────────────────────────

    private fun listAudioFiles(treeUriStr: String): List<Map<String, Any?>> {
        val ctx = activity ?: return emptyList()
        val treeUri = Uri.parse(treeUriStr)
        val root = DocumentFile.fromTreeUri(ctx, treeUri) ?: return emptyList()
        val results = mutableListOf<Map<String, Any?>>()
        scanDirectory(root, results)
        return results
    }

    private fun scanDirectory(dir: DocumentFile, results: MutableList<Map<String, Any?>>) {
        for (file in dir.listFiles()) {
            if (file.isDirectory) {
                scanDirectory(file, results)
            } else if (file.isFile) {
                val name = file.name ?: continue
                val ext = name.substringAfterLast('.', "").lowercase()
                if (ext in AUDIO_EXTENSIONS) {
                    results.add(mapOf(
                        "uri" to file.uri.toString(),
                        "name" to name,
                        "size" to file.length(),
                        "lastModified" to file.lastModified(),
                    ))
                }
            }
        }
    }

    // ── Read metadata ─────────────────────────────────────────────────────

    private fun readMetadata(fileUriStr: String): Map<String, Any?> {
        val ctx = activity ?: return emptyMap()
        val uri = Uri.parse(fileUriStr)
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(ctx, uri)
            mapOf(
                "title" to retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE),
                "artist" to retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST),
                "album" to retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUM),
                "albumArtist" to retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUMARTIST),
                "trackNumber" to retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_CD_TRACK_NUMBER),
                "duration" to retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION),
                "year" to retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_YEAR),
                "genre" to retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_GENRE),
                "bitrate" to retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE),
                "sampleRate" to retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_SAMPLERATE),
                "mimeType" to retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_MIMETYPE),
            )
        } finally {
            retriever.release()
        }
    }

    // ── Read cover art ────────────────────────────────────────────────────

    private fun readCoverArt(fileUriStr: String): ByteArray? {
        val ctx = activity ?: return null
        val uri = Uri.parse(fileUriStr)
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(ctx, uri)
            retriever.embeddedPicture
        } finally {
            retriever.release()
        }
    }

    // ── ActivityAware ─────────────────────────────────────────────────────

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() { activity = null }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this)
    }
    override fun onDetachedFromActivity() { activity = null }
}
