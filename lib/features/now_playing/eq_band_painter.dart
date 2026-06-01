import 'package:flutter/material.dart';

import '../../design_tokens/tokens.dart';

/// CustomPainter that draws 18-band EQ as vertical bars with
/// a center line and animated gain heights.
///
/// Each band is drawn as a rounded rectangle bar. Bars above center
/// represent boost (indigo), bars below represent cut (muted).
/// A horizontal center line marks unity gain (0 dB).
class EqBandPainter extends CustomPainter {
  EqBandPainter({required this.bands, required this.gains, this.enabled = true})
    : assert(
        bands.length == gains.length,
        'bands and gains must have same length',
      );

  /// Band labels (e.g. ['65 Hz', '92 Hz', ...]).
  final List<String> bands;

  /// Gain values for each band (1.0 = unity, 0..4 range).
  final List<double> gains;

  /// Whether the EQ is enabled (affects opacity).
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    if (bands.isEmpty) return;

    final barCount = bands.length;
    const gap = 3.0;
    final totalGap = gap * (barCount - 1);
    final barWidth = (size.width - totalGap) / barCount;
    final midY = size.height * 0.5;
    final maxBarH = size.height * 0.42;

    // Draw center line (unity gain).
    final centerPaint = Paint()
      ..color = AfColors.surfaceHigh
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, midY), Offset(size.width, midY), centerPaint);

    // Draw each band bar.
    for (var i = 0; i < barCount; i++) {
      final gain = gains[i].clamp(0.0, 4.0);
      // Normalize: 1.0 = center, 0 = full cut, 4 = full boost.
      final normalized = (gain - 1.0) / 3.0; // -1..+1
      final barH = maxBarH * normalized.abs();
      final x = i * (barWidth + gap);

      // Bar color: boost = indigo, cut = muted.
      final isBoost = normalized >= 0;
      final color = enabled
          ? (isBoost
                ? AfColors.indigo400
                : AfColors.textTertiary.withValues(alpha: 0.4))
          : AfColors.surfaceHigh;

      final paint = Paint()..color = color;

      // Bar origin: top if boost, bottom if cut.
      final barTop = isBoost ? midY - barH : midY;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, barTop, barWidth, barH),
        const Radius.circular(2),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(EqBandPainter oldDelegate) {
    return oldDelegate.bands != bands ||
        oldDelegate.gains != gains ||
        oldDelegate.enabled != enabled;
  }
}

/// Interactive EQ band visualization widget.
///
/// Draws 18 vertical bars representing EQ gain. Users can drag
/// vertically on any bar to adjust its gain. The visualization
/// uses [EqBandPainter] for rendering.
class EqBandVisualization extends StatefulWidget {
  const EqBandVisualization({
    super.key,
    required this.labels,
    required this.gains,
    required this.onGainChanged,
    required this.onGainChangeEnd,
    this.height = 160,
  });

  /// Band frequency labels (18 items).
  final List<String> labels;

  /// Current gain values (18 items, 1.0 = unity).
  final List<double> gains;

  /// Called when a band's gain changes during drag.
  final void Function(int bandIndex, double newGain) onGainChanged;

  /// Called when drag ends.
  final VoidCallback onGainChangeEnd;

  /// Total height of the visualization.
  final double height;

  @override
  State<EqBandVisualization> createState() => _EqBandVisualizationState();
}

class _EqBandVisualizationState extends State<EqBandVisualization> {
  int? _activeBand;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return GestureDetector(
            onVerticalDragStart: (details) {
              _activeBand = _bandAtX(
                details.localPosition.dx,
                constraints.maxWidth,
              );
              if (_activeBand != null) {
                _updateGain(details.localPosition.dy, constraints.maxHeight);
              }
            },
            onVerticalDragUpdate: (details) {
              if (_activeBand != null) {
                _updateGain(details.localPosition.dy, constraints.maxHeight);
              }
            },
            onVerticalDragEnd: (_) {
              _activeBand = null;
              widget.onGainChangeEnd();
            },
            child: CustomPaint(
              painter: EqBandPainter(bands: widget.labels, gains: widget.gains),
              size: Size(constraints.maxWidth, constraints.maxHeight),
            ),
          );
        },
      ),
    );
  }

  int? _bandAtX(double dx, double width) {
    final barCount = widget.labels.length;
    const gap = 3.0;
    final totalGap = gap * (barCount - 1);
    final barWidth = (width - totalGap) / barCount;

    for (var i = 0; i < barCount; i++) {
      final x = i * (barWidth + gap);
      if (dx >= x && dx <= x + barWidth) return i;
    }
    return null;
  }

  void _updateGain(double dy, double height) {
    if (_activeBand == null) return;
    // Map vertical position to gain: top = 4.0, center = 1.0, bottom = 0.0.
    final normalized = 1.0 - (dy / height); // 1 at top, 0 at bottom.
    final gain = normalized * 4.0;
    widget.onGainChanged(_activeBand!, gain.clamp(0.0, 4.0));
  }
}
