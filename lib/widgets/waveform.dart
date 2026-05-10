import 'package:flutter/material.dart';

import '../design_tokens/tokens.dart';

/// Waveform scrubber for Now Playing.
///
/// Geometry: 64dp tall, [bars] vertical sticks.
///   - Played portion: solid `spectral.energy`.
///   - Unplayed portion: `text.tertiary` 30% alpha.
///   - Playhead: vertical bar `text.primary` 1dp, full waveform height.
///
/// Driven by [progress] in [0, 1] (current position / duration). The caller
/// wires it directly to the single `Stream<Duration>` — there is no internal
/// timer.
class Waveform extends StatelessWidget {
  /// Per-bar peak amplitudes in [0, 100]. Server-provided when possible;
  /// otherwise a deterministic pattern seeded by the track ID.
  final List<int> peaks;
  final double progress;
  final Color playedColor;
  final Color unplayedColor;
  final double height;
  final double playheadWidth;
  final ValueChanged<double>? onScrub;
  final ValueChanged<double>? onScrubEnd;

  const Waveform({
    super.key,
    required this.peaks,
    required this.progress,
    this.playedColor = AfColors.indigo300,
    this.unplayedColor = AfColors.textTertiary,
    this.height = 64,
    this.playheadWidth = 1.5,
    this.onScrub,
    this.onScrubEnd,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: onScrub == null
          ? null
          : (d) => _emit(d.localPosition.dx, context, onScrub!),
      onHorizontalDragUpdate: onScrub == null
          ? null
          : (d) => _emit(d.localPosition.dx, context, onScrub!),
      onHorizontalDragEnd: onScrubEnd == null
          ? null
          : (_) => onScrubEnd!.call(progress),
      onTapDown: onScrub == null
          ? null
          : (d) => _emit(d.localPosition.dx, context, onScrub!),
      child: SizedBox(
        height: height,
        child: CustomPaint(
          painter: _WaveformPainter(
            peaks: peaks,
            progress: progress.clamp(0.0, 1.0),
            playedColor: playedColor,
            unplayedColor: unplayedColor,
            playheadWidth: playheadWidth,
          ),
        ),
      ),
    );
  }

  void _emit(double dx, BuildContext context, ValueChanged<double> sink) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final width = box.size.width;
    if (width <= 0) return;
    sink((dx / width).clamp(0.0, 1.0));
  }
}

class _WaveformPainter extends CustomPainter {
  final List<int> peaks;
  final double progress;
  final Color playedColor;
  final Color unplayedColor;
  final double playheadWidth;

  _WaveformPainter({
    required this.peaks,
    required this.progress,
    required this.playedColor,
    required this.unplayedColor,
    required this.playheadWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (peaks.isEmpty) return;
    final barCount = peaks.length;
    final barWidth = size.width / (barCount * 1.5 + 0.5);
    final gap = barWidth / 2;
    final playedBars = (progress * barCount).floor();

    final played = Paint()
      ..color = playedColor
      ..style = PaintingStyle.fill;
    // ignore: deprecated_member_use
    final unplayed = Paint()
      // ignore: deprecated_member_use
      ..color = unplayedColor.withOpacity(0.3)
      ..style = PaintingStyle.fill;
    final centerY = size.height / 2;

    for (var i = 0; i < barCount; i++) {
      final amp = peaks[i] / 100.0;
      final h = (size.height * amp).clamp(2, size.height);
      final x = i * (barWidth + gap);
      final paint = i < playedBars ? played : unplayed;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          x,
          centerY - h / 2,
          barWidth,
          h.toDouble(),
        ),
        const Radius.circular(1),
      );
      canvas.drawRRect(rect, paint);
    }

    // Playhead.
    final headX = (progress * size.width).clamp(0.0, size.width);
    final head = Paint()
      ..color = AfColors.textPrimary
      ..strokeWidth = playheadWidth
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(headX, 0),
      Offset(headX, size.height),
      head,
    );
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress ||
      old.peaks != peaks ||
      old.playedColor != playedColor ||
      old.unplayedColor != unplayedColor;
}
