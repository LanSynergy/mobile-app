/// A single timestamped lyric line.
class LrcLine {
  final Duration start;
  final String text;
  const LrcLine(this.start, this.text);
}

/// Parsed LRC payload.
class Lrc {
  /// Lines sorted by [LrcLine.start].
  final List<LrcLine> lines;

  /// Track-level metadata (`[ti:..]`, `[ar:..]`, `[al:..]`).
  final Map<String, String> meta;

  const Lrc({this.lines = const [], this.meta = const {}});

  bool get isEmpty => lines.isEmpty;

  /// Index of the active line for the given playback position. Returns -1
  /// when no line is active yet (e.g. before the first lyric).
  int activeIndex(Duration position) {
    var idx = -1;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].start <= position) {
        idx = i;
      } else {
        break;
      }
    }
    return idx;
  }
}

/// A minimal LRC parser. Handles single timestamp lines like:
///   `[mm:ss.xx] lyric text`
/// Multi-timestamp lines (`[00:12.34][00:25.67] text`) are expanded.
/// Bracketed metadata (`[ti:Track Title]`) is collected into [Lrc.meta].
Lrc parseLrc(String src) {
  final lines = <LrcLine>[];
  final meta = <String, String>{};
  final lineRegex = RegExp(r'^(.*?)$', multiLine: true);
  final tagRegex = RegExp(r'\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]');
  final metaRegex = RegExp(r'^\[([a-zA-Z]+):(.+)\]$');

  for (final m in lineRegex.allMatches(src)) {
    final raw = m.group(1)?.trim() ?? '';
    if (raw.isEmpty) continue;

    final metaMatch = metaRegex.firstMatch(raw);
    if (metaMatch != null && tagRegex.firstMatch(raw) == null) {
      meta[metaMatch.group(1)!.toLowerCase()] = metaMatch.group(2)!.trim();
      continue;
    }

    final tags = tagRegex.allMatches(raw).toList();
    if (tags.isEmpty) continue;

    final text = raw.replaceAll(tagRegex, '').trim();
    for (final tag in tags) {
      final mm = int.parse(tag.group(1)!);
      final ss = int.parse(tag.group(2)!);
      final fragRaw = tag.group(3) ?? '0';
      final ms = (int.parse(fragRaw) *
              (fragRaw.length == 3
                  ? 1
                  : fragRaw.length == 2
                      ? 10
                      : 100))
          .clamp(0, 999);
      lines.add(LrcLine(
        Duration(minutes: mm, seconds: ss, milliseconds: ms),
        text,
      ));
    }
  }
  lines.sort((a, b) => a.start.compareTo(b.start));
  return Lrc(lines: lines, meta: meta);
}
