import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design_tokens/tokens.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Waveform — progress scrubber
//
// A clean, minimal track scrubber. Single filled pill, no waveform bars.
//
// Visual anatomy:
//   Track:  full-width rounded pill, 3dp tall, textTertiary at 20% opacity
//   Fill:   accent color, grows left-to-right with progress
//   Thumb:  6dp circle, textPrimary, appears only during drag
//   Glow:   soft radial bloom behind thumb during drag
//
// The hit area is the full widget height (36dp default) for comfortable
// scrubbing without a visually heavy element.
//
// Architecture:
//   _ScrubNotifier (ChangeNotifier) — drag state + display progress
//   _ScrubPainter  (CustomPainter, repaint: notifier) — pure rendering
//   No ticker — repaints only on drag or external progress updates.
// ─────────────────────────────────────────────────────────────────────────────

class Waveform extends StatefulWidget {
  // peaks kept for API compatibility — not rendered in this design.
  final List<int> peaks;
  final double progress;
  final Color playedColor;
  final Color unplayedColor;
  final double height;
  final ValueChanged<double>? onScrub;
  final ValueChanged<double>? onScrubEnd;
  final bool isPlaying;

  const Waveform({
    super.key,
    required this.peaks,
    required this.progress,
    this.playedColor   = AfColors.indigo300,
    this.unplayedColor = AfColors.textTertiary,
    this.height        = 36,
    this.onScrub,
    this.onScrubEnd,
    this.isPlaying     = true,
  });

  @override
  State<Waveform> createState() => _WaveformState();
}

class _WaveformState extends State<Waveform> {
  late final _ScrubNotifier _notifier;

  @override
  void initState() {
    super.initState();
    _notifier = _ScrubNotifier(
      progress:      widget.progress,
      playedColor:   widget.playedColor,
      unplayedColor: widget.unplayedColor,
    );
  }

  @override
  void didUpdateWidget(covariant Waveform old) {
    super.didUpdateWidget(old);
    _notifier.update(
      progress:      widget.progress,
      playedColor:   widget.playedColor,
      unplayedColor: widget.unplayedColor,
    );
  }

  @override
  void dispose() {
    _notifier.dispose();
    super.dispose();
  }

  void _handleDragStart(DragStartDetails d) {
    HapticFeedback.selectionClick();
    _notifier.setDrag(true, _toProgress(d.localPosition.dx));
    widget.onScrub?.call(_notifier.dragProgress);
  }

  void _handleDragUpdate(DragUpdateDetails d) {
    _notifier.setDrag(true, _toProgress(d.localPosition.dx));
    widget.onScrub?.call(_notifier.dragProgress);
  }

  void _handleDragEnd(DragEndDetails _) {
    widget.onScrubEnd?.call(_notifier.dragProgress);
    _notifier.setDrag(false, _notifier.dragProgress);
  }

  void _handleTap(TapDownDetails d) {
    HapticFeedback.selectionClick();
    final p = _toProgress(d.localPosition.dx);
    widget.onScrub?.call(p);
    widget.onScrubEnd?.call(p);
  }

  double _toProgress(double dx) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || box.size.width <= 0) return 0;
    return (dx / box.size.width).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: _handleDragStart,
        onHorizontalDragUpdate: _handleDragUpdate,
        onHorizontalDragEnd: _handleDragEnd,
        onTapDown: _handleTap,
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: CustomPaint(
            painter: _ScrubPainter(notifier: _notifier),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ScrubNotifier
// ─────────────────────────────────────────────────────────────────────────────

class _ScrubNotifier extends ChangeNotifier {
  double _progress;
  Color  _playedColor;
  Color  _unplayedColor;

  bool   _dragging     = false;
  double _dragProgress = 0.0;

  _ScrubNotifier({
    required double progress,
    required Color  playedColor,
    required Color  unplayedColor,
  })  : _progress      = progress,
        _playedColor   = playedColor,
        _unplayedColor = unplayedColor;

  double get displayProgress =>
      _dragging ? _dragProgress : _progress.clamp(0.0, 1.0);
  bool   get dragging      => _dragging;
  double get dragProgress  => _dragProgress;
  Color  get playedColor   => _playedColor;
  Color  get unplayedColor => _unplayedColor;

  void update({
    required double progress,
    required Color  playedColor,
    required Color  unplayedColor,
  }) {
    _progress      = progress;
    _playedColor   = playedColor;
    _unplayedColor = unplayedColor;
    notifyListeners();
  }

  void setDrag(bool dragging, double progress) {
    _dragging     = dragging;
    _dragProgress = progress;
    notifyListeners();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ScrubPainter — minimal pill progress bar
// ─────────────────────────────────────────────────────────────────────────────

class _ScrubPainter extends CustomPainter {
  final _ScrubNotifier notifier;

  static const double _trackH = 3.0;
  static const double _thumbR = 6.0;
  static const double _glowR  = 18.0;

  _ScrubPainter({required this.notifier}) : super(repaint: notifier);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final progress   = notifier.displayProgress;
    final isDragging = notifier.dragging;
    final played     = notifier.playedColor;
    final unplayed   = notifier.unplayedColor;
    final midY       = size.height / 2;
    final fillW      = (progress * size.width).clamp(0.0, size.width);
    final trackR     = const Radius.circular(_trackH / 2);

    // ── Track background ─────────────────────────────────────────────────
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, midY - _trackH / 2, size.width, _trackH),
        trackR,
      ),
      Paint()
        ..color = unplayed.withValues(alpha: 0.20)
        ..style = PaintingStyle.fill,
    );

    // ── Filled portion ───────────────────────────────────────────────────
    if (fillW > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, midY - _trackH / 2, fillW, _trackH),
          trackR,
        ),
        Paint()
          ..color = played
          ..style = PaintingStyle.fill,
      );
    }

    // ── Thumb + glow (drag only) ─────────────────────────────────────────
    if (isDragging) {
      final cx = fillW.clamp(_thumbR, size.width - _thumbR);

      // Soft glow bloom.
      canvas.drawCircle(
        Offset(cx, midY),
        _glowR,
        Paint()
          ..color = played.withValues(alpha: 0.18)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );

      // Thumb dot.
      canvas.drawCircle(
        Offset(cx, midY),
        _thumbR,
        Paint()
          ..color = AfColors.textPrimary
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(_ScrubPainter _) => false;
}
