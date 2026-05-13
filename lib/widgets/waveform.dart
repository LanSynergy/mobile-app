import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design_tokens/tokens.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Waveform — static peaks scrubber
//
// Renders a track's pre-computed peak waveform as a progress scrubber.
// No FFT, no live animation — purely static peaks data with a playhead.
//
// Architecture:
//   _ScrubNotifier (ChangeNotifier) — drag state + display progress
//   _ScrubPainter  (CustomPainter, repaint: notifier) — pure rendering
//   No ticker needed — repaints only on drag or external progress updates.
//
// Visual:
//   • Uniform bars, center-anchored (symmetric above and below baseline)
//   • Played region: accent color at full opacity
//   • Unplayed region: accent color at 22% opacity
//   • Playhead: 2dp line + 5dp thumb dot
//   • Drag state: thumb grows to 7.5dp, subtle glow
// ─────────────────────────────────────────────────────────────────────────────

class Waveform extends StatefulWidget {
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
    this.height        = 48,
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
      peaks: widget.peaks,
      progress: widget.progress,
      playedColor: widget.playedColor,
      unplayedColor: widget.unplayedColor,
    );
  }

  @override
  void didUpdateWidget(covariant Waveform old) {
    super.didUpdateWidget(old);
    _notifier.update(
      peaks: widget.peaks,
      progress: widget.progress,
      playedColor: widget.playedColor,
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
  Float32List _peaks;
  double _progress;
  Color _playedColor;
  Color _unplayedColor;

  bool   _dragging     = false;
  double _dragProgress = 0.0;

  _ScrubNotifier({
    required List<int> peaks,
    required double progress,
    required Color playedColor,
    required Color unplayedColor,
  })  : _peaks        = _normalizePeaks(peaks),
        _progress     = progress,
        _playedColor  = playedColor,
        _unplayedColor = unplayedColor;

  Float32List get peaks        => _peaks;
  double      get displayProgress =>
      _dragging ? _dragProgress : _progress.clamp(0.0, 1.0);
  bool        get dragging     => _dragging;
  double      get dragProgress => _dragProgress;
  Color       get playedColor  => _playedColor;
  Color       get unplayedColor => _unplayedColor;

  void update({
    required List<int> peaks,
    required double progress,
    required Color playedColor,
    required Color unplayedColor,
  }) {
    _peaks        = _normalizePeaks(peaks);
    _progress     = progress;
    _playedColor  = playedColor;
    _unplayedColor = unplayedColor;
    notifyListeners();
  }

  void setDrag(bool dragging, double progress) {
    _dragging     = dragging;
    _dragProgress = progress;
    notifyListeners();
  }

  static Float32List _normalizePeaks(List<int> peaks) {
    if (peaks.isEmpty) return Float32List(0);
    final out = Float32List(peaks.length);
    for (var i = 0; i < peaks.length; i++) {
      out[i] = (peaks[i] / 100.0).clamp(0.0, 1.0);
    }
    return out;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ScrubPainter
// ─────────────────────────────────────────────────────────────────────────────

class _ScrubPainter extends CustomPainter {
  final _ScrubNotifier notifier;

  static const double _gapFraction    = 0.30;
  static const double _minBarPx       = 2.0;
  static const double _headWidth      = 2.0;
  static const double _thumbR         = 5.0;
  static const double _thumbRDrag     = 7.5;

  _ScrubPainter({required this.notifier}) : super(repaint: notifier);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final peaks      = notifier.peaks;
    final barCount   = peaks.isEmpty ? 64 : peaks.length;
    final progress   = notifier.displayProgress;
    final headX      = progress * size.width;
    final headBarF   = progress * barCount;
    final isDragging = notifier.dragging;
    final played     = notifier.playedColor;
    final unplayed   = notifier.unplayedColor.withValues(alpha: 0.22);

    final slotW  = size.width / barCount;
    final barW   = slotW * (1.0 - _gapFraction);
    final barOffX = (slotW - barW) / 2;
    final halfH  = size.height / 2;

    final paint = Paint()..style = PaintingStyle.fill;
    final capR  = Radius.circular(barW / 2);

    for (var i = 0; i < barCount; i++) {
      final peakVal = peaks.isEmpty ? 0.5 : peaks[i];
      final barH    = (peakVal * size.height * 0.85).clamp(_minBarPx, size.height);
      final x       = i * slotW + barOffX;
      final y       = halfH - barH / 2;

      // Played/unplayed split with sub-bar interpolation at the boundary.
      final Color color;
      if (i < headBarF.floor()) {
        color = played;
      } else if (i == headBarF.floor()) {
        final frac = headBarF - headBarF.floor();
        color = Color.lerp(unplayed, played, frac)!;
      } else {
        color = unplayed;
      }
      paint.color = color;

      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, y, barW, barH), capR),
        paint,
      );
    }

    // ── Playhead glow ────────────────────────────────────────────────────
    canvas.drawRect(
      Rect.fromLTWH(headX - 8, 0, 16, size.height),
      Paint()
        ..color = played.withValues(alpha: isDragging ? 0.20 : 0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    // ── Playhead line ────────────────────────────────────────────────────
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(headX - _headWidth / 2, 0, _headWidth, size.height),
        const Radius.circular(1),
      ),
      Paint()
        ..color = isDragging
            ? AfColors.textPrimary
            : played.withValues(alpha: 0.9)
        ..style = PaintingStyle.fill,
    );

    // ── Scrub thumb ──────────────────────────────────────────────────────
    final thumbR = isDragging ? _thumbRDrag : _thumbR;
    if (isDragging) {
      canvas.drawCircle(
        Offset(headX, halfH),
        thumbR + 6,
        Paint()
          ..color = played.withValues(alpha: 0.20)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
      );
    }
    canvas.drawCircle(
      Offset(headX, halfH),
      thumbR,
      Paint()
        ..color = AfColors.textPrimary
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_ScrubPainter _) => false;
}
