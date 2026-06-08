class M3UEntry {
  const M3UEntry({
    this.title,
    this.artist,
    this.duration,
    required this.path,
    this.comment,
    this.tags = const {},
  });

  final String? title;
  final String? artist;
  final Duration? duration;
  final String path;
  final String? comment;
  final Map<String, String> tags;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is M3UEntry &&
          runtimeType == other.runtimeType &&
          path == other.path &&
          title == other.title &&
          artist == other.artist &&
          duration == other.duration;

  @override
  int get hashCode => Object.hash(path, title, artist, duration);

  @override
  String toString() =>
      'M3UEntry(title: $title, artist: $artist, duration: $duration, path: $path)';
}

class M3uWriteOptions {
  const M3uWriteOptions({this.includeExtInf = true, this.commentPrefix});

  final bool includeExtInf;
  final String? commentPrefix;
}

class M3uParseException implements Exception {
  const M3uParseException(this.message, this.lineNumber);

  final String message;
  final int lineNumber;

  @override
  String toString() => 'M3uParseException(line $lineNumber: $message)';
}

class M3uParser {
  /// Parse standard/extended M3U content.
  /// Throws M3uParseException on unrecoverable corruption.
  static List<M3UEntry> parse(String content) {
    if (content.trim().isEmpty) return [];

    final lines = content.split('\n');
    final entries = <M3UEntry>[];
    M3UEntry? pendingEntry;
    final tags = <String, String>{};

    for (int i = 0; i < lines.length; i++) {
      final raw = lines[i];
      final line = raw.trimRight();

      if (line.isEmpty) continue;

      if (line.startsWith('#EXTM3U')) {
        // Header marker, continue
        continue;
      }

      if (line.startsWith('#EXTINF:')) {
        // Parse EXTINF line
        final extinfContent = line.substring(8); // remove '#EXTINF:'
        final commaIndex = extinfContent.indexOf(',');

        Duration? duration;
        String? titleArtist;

        if (commaIndex >= 0) {
          final durationStr = extinfContent.substring(0, commaIndex).trim();
          duration = _parseDuration(durationStr);
          titleArtist = extinfContent.substring(commaIndex + 1).trim();
        } else {
          // No comma — malformed EXTINF
          duration = _parseDuration(extinfContent.trim());
        }

        String? title;
        String? artist;

        if (titleArtist != null && titleArtist.contains(' - ')) {
          final dashIndex = titleArtist.indexOf(' - ');
          artist = titleArtist.substring(0, dashIndex).trim();
          title = titleArtist.substring(dashIndex + 3).trim();
        } else {
          title = titleArtist;
        }

        pendingEntry = M3UEntry(
          title: title,
          artist: artist,
          duration: duration,
          path: '',
          tags: Map.from(tags),
        );
        tags.clear();
        continue;
      }

      // Custom Aetherfin tag line
      if (line.startsWith('# Aetherfin:')) {
        final tagContent = line.substring(12); // remove '# Aetherfin:'
        final colonIdx = tagContent.indexOf(':');
        if (colonIdx >= 0) {
          final key = tagContent.substring(0, colonIdx).trim();
          final value = tagContent.substring(colonIdx + 1).trim();
          tags[key] = value;
        }
        continue;
      }

      // Comment line
      if (line.startsWith('#')) {
        continue;
      }

      // Track path line
      final path = line.trim();
      if (path.isEmpty) continue;

      if (pendingEntry != null) {
        entries.add(
          M3UEntry(
            title: pendingEntry.title,
            artist: pendingEntry.artist,
            duration: pendingEntry.duration,
            path: path,
            tags: pendingEntry.tags,
          ),
        );
        pendingEntry = null;
      } else {
        entries.add(M3UEntry(path: path));
      }
    }

    return entries;
  }

  /// Write entries to M3U format string.
  static String write(List<M3UEntry> entries, {M3uWriteOptions? options}) {
    options ??= const M3uWriteOptions();
    final buffer = StringBuffer();

    buffer.writeln('#EXTM3U');

    for (final entry in entries) {
      if (options.includeExtInf && entry.duration != null) {
        final durationSec = entry.duration!.inSeconds;
        final titleArtist = <String>[];
        if (entry.artist != null) titleArtist.add(entry.artist!);
        if (entry.title != null) titleArtist.add(entry.title!);
        final display = titleArtist.isNotEmpty
            ? titleArtist.join(' - ')
            : entry.path;
        buffer.writeln('#EXTINF:$durationSec,$display');
      }

      // Write custom tags
      for (final e in entry.tags.entries) {
        buffer.writeln('# Aetherfin:${e.key}:${e.value}');
      }

      buffer.writeln(entry.path);
    }

    return buffer.toString();
  }

  static Duration? _parseDuration(String value) {
    try {
      final seconds = int.tryParse(value);
      if (seconds != null && seconds >= 0) {
        return Duration(seconds: seconds);
      }
      // Try parsing as HH:MM:SS or MM:SS
      final parts = value.split(':');
      if (parts.length == 2) {
        final minutes = int.tryParse(parts[0]);
        final secs = int.tryParse(parts[1]);
        if (minutes != null && secs != null) {
          return Duration(minutes: minutes, seconds: secs);
        }
      } else if (parts.length == 3) {
        final hours = int.tryParse(parts[0]);
        final minutes = int.tryParse(parts[1]);
        final secs = int.tryParse(parts[2]);
        if (hours != null && minutes != null && secs != null) {
          return Duration(hours: hours, minutes: minutes, seconds: secs);
        }
      }
    } on FormatException {
      // Malformed duration — return null
    }
    return null;
  }
}
