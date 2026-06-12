import 'dart:math';

import 'package:flutter/material.dart';

import '../design_tokens/pro_audio.dart';

/// Professional 18-band graphic EQ painter with dB grid and frequency labels.
///
/// Features:
/// - dB grid lines at ±3/6/12
/// - Frequency labels below bars
/// - Frequency-coded bar colors (red bass → blue treble)
/// - Active band highlight during drag
/// - Disabled state (dimmed)
class GraphicEqPainter extends CustomPainter {
  GraphicEqPainter({
    required this.bands,
    required this.gains,
    required this.accentColor,
    this.enabled = true,
    this.selectedBand,
  });

  final List<String> bands;
  final List<double> gains;
  final Color accentColor;
  final bool enabled;
  final int? selectedBand;

  // ── Static helpers ────────────────────────────────────────────────────────

  /// Convert multiplier gain to dB: 20*log10(multiplier).
  static double gainToDb(double gain) {
    if (gain <= 0) return -double.infinity;
    return 20 * log(gain) / ln10;
  }

  /// Calculate bar height for a given dB value.
  /// Returns absolute pixel height from center.
  static double dbToBarHeight(
    double db,
    double maxHeight, {
    double dbRange = 12.0,
  }) {
    return (db.abs() / dbRange) * maxHeight;
  }

  /// Returns a frequency-coded color for the band at [index].
  /// Red (bass) → Orange → Yellow → Green → Blue (treble).
  static Color bandColor(int index, int totalBands) {
    final hue = (index / (totalBands - 1)) * 240; // 0=red, 240=blue
    return HSVColor.fromAHSV(1.0, hue, 0.8, 0.9).toColor();
  }

  // ── Painting ──────────────────────────────────────────────────────────────

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Background
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = ProAudioColors.bgPanel,
    );

    // 2. dB grid lines
    _drawDbGrid(canvas, size);

    // 3. EQ bars
    _drawBars(canvas, size);

    // 4. Active band highlight
    if (selectedBand != null) {
      _drawActiveIndicator(canvas, size, selectedBand!);
    }

    // 5. Frequency labels
    _drawFreqLabels(canvas, size);
  }

  void _drawDbGrid(Canvas canvas, Size size) {
    const dbValues = [-12.0, -6.0, 0.0, 6.0, 12.0];
    const dbRange = 12.0;

    for (final db in dbValues) {
      final y = _dbToY(db, size.height, dbRange);
      final isCenter = db == 0.0;

      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = isCenter
              ? ProAudioColors.gridLineCenter
              : ProAudioColors.gridLine
          ..strokeWidth = isCenter ? 1.0 : 0.5,
      );

      // dB label on left edge
      final label = db > 0 ? '+${db.toInt()}' : '${db.toInt()}';
      final tp = TextPainter(
        text: TextSpan(text: label, style: ProAudioTypography.dbLabel),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(0, y - 6));
    }
  }

  void _drawBars(Canvas canvas, Size size) {
    final barCount = gains.length;
    if (barCount == 0) return;
    const gap = 3.0;
    final totalGap = gap * (barCount - 1);
    final barWidth = (size.width - totalGap) / barCount;
    const dbRange = 12.0;
    final midY = size.height * 0.5;
    final maxBarH = size.height * 0.42;

    for (var i = 0; i < barCount; i++) {
      final gain = gains[i].clamp(0.0, 4.0);
      final db = gainToDb(gain);
      final clampedDb = db.clamp(-dbRange, dbRange);
      final normalized = clampedDb / dbRange; // -1..+1
      final barH = maxBarH * normalized.abs();
      final x = i * (barWidth + gap);

      // Color: frequency-coded
      final color = enabled ? bandColor(i, barCount) : ProAudioColors.textDim;

      // Bar origin: top if boost, bottom if cut
      final barTop = normalized >= 0 ? midY - barH : midY;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, barTop, barWidth, barH),
        const Radius.circular(1),
      );

      // Gradient fill (brighter at peak)
      final gradient = LinearGradient(
        begin: normalized >= 0 ? Alignment.bottomCenter : Alignment.topCenter,
        end: normalized >= 0 ? Alignment.topCenter : Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.6), color],
      );

      canvas.drawRRect(
        rect,
        Paint()..shader = gradient.createShader(rect.outerRect),
      );
    }
  }

  void _drawActiveIndicator(Canvas canvas, Size size, int index) {
    final barCount = gains.length;
    if (barCount == 0 || index >= barCount) return;
    const gap = 3.0;
    final totalGap = gap * (barCount - 1);
    final barWidth = (size.width - totalGap) / barCount;
    final x = index * (barWidth + gap);

    // Draw highlight rectangle behind the active bar
    canvas.drawRect(
      Rect.fromLTWH(x - 1, 0, barWidth + 2, size.height),
      Paint()
        ..color = accentColor.withValues(alpha: 0.08)
        ..style = PaintingStyle.fill,
    );
  }

  void _drawFreqLabels(Canvas canvas, Size size) {
    final barCount = bands.length;
    if (barCount == 0) return;
    const gap = 3.0;
    final totalGap = gap * (barCount - 1);
    final barWidth = (size.width - totalGap) / barCount;

    for (var i = 0; i < barCount; i++) {
      final x = i * (barWidth + gap) + barWidth / 2;
      final tp = TextPainter(
        text: TextSpan(text: bands[i], style: ProAudioTypography.freqLabel),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, size.height - tp.height));
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static double _dbToY(double db, double height, double dbRange) {
    final center = height / 2;
    return center - (db / dbRange) * center;
  }

  @override
  bool shouldRepaint(covariant GraphicEqPainter oldDelegate) =>
      oldDelegate.gains != gains ||
      oldDelegate.enabled != enabled ||
      oldDelegate.selectedBand != selectedBand ||
      oldDelegate.accentColor != accentColor;
}
