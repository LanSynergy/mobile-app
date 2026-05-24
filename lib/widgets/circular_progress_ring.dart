import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design_tokens/tokens.dart';

/// A 36dp circular ring around the play/pause glyph in the mini-player.
///
/// Per non-negotiable §4.1: this is the ONLY progress affordance on the
/// mini-player — never a linear hairline bar.
///
/// Track stroke 2dp `surface.high`, progress arc 2dp `spectral.energy`,
/// `strokeLinecap: round`, sweep clockwise from 12 o'clock.
///
/// Driven by [progress] in [0, 1] with a [linear] paint — there is NO
/// AnimationController internal to this widget. The caller wires it
/// directly to the single `Stream<Duration>` from the audio service so
/// the ring tells audio time honestly.
class CircularProgressRing extends StatelessWidget {

  const CircularProgressRing({
    super.key,
    required this.progress,
    required this.child,
    this.trackColor = AfColors.surfaceHigh,
    this.progressColor = AfColors.indigo300,
    this.size = 36,
    this.strokeWidth = 2,
    this.isIndeterminate = false,
  });
  final double progress; // 0 .. 1
  final Color trackColor;
  final Color progressColor;
  final double size;
  final double strokeWidth;
  final Widget child;

  /// True when buffering / loading — renders the indeterminate variant
  /// (90° arc rotating at 800ms per revolution, full-track at 30% alpha).
  final bool isIndeterminate;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (isIndeterminate)
            _IndeterminateArc(
              size: size,
              strokeWidth: strokeWidth,
              trackColor: trackColor,
              progressColor: progressColor,
            )
          else
            CustomPaint(
              size: Size.square(size),
              painter: _RingPainter(
                progress: progress.clamp(0.0, 1.0),
                trackColor: trackColor,
                progressColor: progressColor,
                strokeWidth: strokeWidth,
              ),
            ),
          child,
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {

  _RingPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
    required this.strokeWidth,
  });
  final double progress;
  final Color trackColor;
  final Color progressColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;

    final track = Paint()
      ..color = trackColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);

    final fg = Paint()
      ..color = progressColor
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(
      Offset(center.dx, center.dy - radius),
      strokeWidth / 2,
      fg..style = PaintingStyle.fill,
    );

    // Always draw at least a tiny arc so the ring never appears empty
    // when position briefly resets to 0 during track transitions.
    final sweepProgress = math.max(progress, 0.005);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * sweepProgress,
      false,
      fg
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.progressColor != progressColor;
}

class _IndeterminateArc extends StatefulWidget {

  const _IndeterminateArc({
    required this.size,
    required this.strokeWidth,
    required this.trackColor,
    required this.progressColor,
  });
  final double size;
  final double strokeWidth;
  final Color trackColor;
  final Color progressColor;

  @override
  State<_IndeterminateArc> createState() => _IndeterminateArcState();
}

class _IndeterminateArcState extends State<_IndeterminateArc>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return CustomPaint(
          size: Size.square(widget.size),
          painter: _IndeterminatePainter(
            value: _ctrl.value,
            // ignore: deprecated_member_use
            trackColor: widget.trackColor.withValues(alpha: 0.3),
            progressColor: widget.progressColor,
            strokeWidth: widget.strokeWidth,
          ),
        );
      },
    );
  }
}

class _IndeterminatePainter extends CustomPainter {

  _IndeterminatePainter({
    required this.value,
    required this.trackColor,
    required this.progressColor,
    required this.strokeWidth,
  });
  final double value;
  final Color trackColor;
  final Color progressColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;

    final track = Paint()
      ..color = trackColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, radius, track);

    final fg = Paint()
      ..color = progressColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      2 * math.pi * value - math.pi / 2,
      math.pi / 2,
      false,
      fg,
    );
  }

  @override
  bool shouldRepaint(_IndeterminatePainter oldDelegate) =>
      oldDelegate.value != value;
}
