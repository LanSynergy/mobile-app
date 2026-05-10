/// Time-formatting helpers.
///
/// All durations are formatted in track time (mm:ss / hh:mm:ss).
String formatTrackDuration(Duration d) {
  if (d.isNegative) d = Duration.zero;
  final total = d.inSeconds;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  if (hours > 0) {
    return '${two(hours)}:${two(minutes)}:${two(seconds)}';
  }
  return '${two(minutes)}:${two(seconds)}';
}

/// Returns "-MM:SS" remaining time for the given remaining duration.
String formatRemaining(Duration d) {
  return '-${formatTrackDuration(d)}';
}

/// Whole-hour readout, e.g. `103h`. Used on the All Set artwork wall.
String formatHourCount(Duration d) {
  final hours = d.inMinutes / 60;
  if (hours < 1) {
    return '${d.inMinutes}m';
  }
  return '${hours.round()}h';
}

/// "2,247" → "2.2K", "12,400" → "12K", small numbers untouched.
String formatCompactCount(int n) {
  if (n < 1000) return n.toString();
  if (n < 10_000) return '${(n / 1000).toStringAsFixed(1)}K';
  if (n < 1_000_000) return '${(n / 1000).round()}K';
  if (n < 10_000_000) return '${(n / 1_000_000).toStringAsFixed(1)}M';
  return '${(n / 1_000_000).round()}M';
}
