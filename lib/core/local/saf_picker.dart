import 'package:flutter/services.dart';

/// Dart bridge to the Android SAF (Storage Access Framework) platform channel.
///
/// Provides folder picking, recursive audio file listing, metadata extraction,
/// and cover art reading — all via `content://` URIs that don't require
/// storage permissions (SAF grants per-tree persistent read access).
class SafPicker {
  static const _channel = MethodChannel('aetherfin.saf');

  /// Opens Android's folder picker (ACTION_OPEN_DOCUMENT_TREE).
  /// Returns the persistent tree URI string, or null if cancelled.
  static Future<String?> pickFolder() async {
    final result = await _channel.invokeMethod<String>('pickFolder');
    return result;
  }

  /// Recursively lists all audio files under a SAF tree URI.
  /// Returns a list of [SafFile] with uri, name, size, lastModified.
  static Future<List<SafFile>> listAudioFiles(String treeUri) async {
    final result = await _channel.invokeMethod<List<dynamic>>(
      'listAudioFiles',
      {'uri': treeUri},
    );
    if (result == null) return const [];
    return result
        .cast<Map<dynamic, dynamic>>()
        .map((m) => SafFile.fromMap(m.cast<String, dynamic>()))
        .toList(growable: false);
  }

  /// Reads metadata tags from a single audio file via MediaMetadataRetriever.
  static Future<SafMetadata> readMetadata(String fileUri) async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'readMetadata',
      {'uri': fileUri},
    );
    if (result == null) return const SafMetadata();
    return SafMetadata.fromMap(result.cast<String, dynamic>());
  }

  /// Reads embedded cover art bytes from a file. Returns null if none.
  static Future<Uint8List?> readCoverArt(String fileUri) async {
    final result = await _channel.invokeMethod<Uint8List>('readCoverArt', {
      'uri': fileUri,
    });
    return result;
  }

  /// Reads sidecar or embedded lyrics from a file via SAF. Returns null if none.
  static Future<String?> readLyrics(String fileUri) async {
    try {
      final result = await _channel.invokeMethod<String>('readLyrics', {
        'uri': fileUri,
      });
      return result;
    } catch (e) {
      return null;
    }
  }
}

/// A file discovered during SAF tree scan.
class SafFile {
  const SafFile({
    required this.uri,
    required this.name,
    required this.size,
    required this.lastModified,
  });

  factory SafFile.fromMap(Map<String, dynamic> m) => SafFile(
    uri: (m['uri'] as String?) ?? '',
    name: (m['name'] as String?) ?? '',
    size: (m['size'] as int?) ?? 0,
    lastModified: (m['lastModified'] as int?) ?? 0,
  );
  final String uri;
  final String name;
  final int size;
  final int lastModified;
}

/// Metadata extracted from a single audio file.
class SafMetadata {
  const SafMetadata({
    this.title,
    this.artist,
    this.album,
    this.albumArtist,
    this.trackNumber,
    this.duration,
    this.year,
    this.genre,
    this.bitrate,
    this.sampleRate,
    this.mimeType,
  });

  factory SafMetadata.fromMap(Map<String, dynamic> m) => SafMetadata(
    title: m['title'] as String?,
    artist: m['artist'] as String?,
    album: m['album'] as String?,
    albumArtist: m['albumArtist'] as String?,
    trackNumber: m['trackNumber'] as String?,
    duration: m['duration'] as String?,
    year: m['year'] as String?,
    genre: m['genre'] as String?,
    bitrate: m['bitrate'] as String?,
    sampleRate: m['sampleRate'] as String?,
    mimeType: m['mimeType'] as String?,
  );
  final String? title;
  final String? artist;
  final String? album;
  final String? albumArtist;
  final String? trackNumber;
  final String? duration;
  final String? year;
  final String? genre;
  final String? bitrate;
  final String? sampleRate;
  final String? mimeType;

  /// Parse duration string (milliseconds) to int.
  int get durationMs => int.tryParse(duration ?? '') ?? 0;

  /// Parse track number (handles "3/12" format).
  int? get trackNum {
    if (trackNumber == null) return null;
    final raw = trackNumber!.split('/').first.trim();
    return int.tryParse(raw);
  }

  /// Parse year to int.
  int? get yearInt => int.tryParse(year ?? '');

  /// Parse bitrate (bps) to kbps.
  int? get bitrateKbps {
    final bps = int.tryParse(bitrate ?? '');
    return bps != null ? bps ~/ 1000 : null;
  }

  /// Parse sample rate to int.
  int? get sampleRateHz => int.tryParse(sampleRate ?? '');

  /// Derive codec from mimeType.
  String get codec {
    if (mimeType == null) return '';
    if (mimeType!.contains('flac')) return 'flac';
    if (mimeType!.contains('mp3') || mimeType!.contains('mpeg')) return 'mp3';
    if (mimeType!.contains('opus')) return 'opus';
    if (mimeType!.contains('ogg') || mimeType!.contains('vorbis')) return 'ogg';
    if (mimeType!.contains('mp4') || mimeType!.contains('m4a')) return 'm4a';
    if (mimeType!.contains('wav') || mimeType!.contains('wave')) return 'wav';
    if (mimeType!.contains('aac')) return 'aac';
    return '';
  }
}
