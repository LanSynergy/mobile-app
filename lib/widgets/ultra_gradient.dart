import 'dart:math';

import 'package:flutter/material.dart';

import '../design_tokens/tokens.dart';

/// GPU-rendered gradient using blurred blobs + [BlendMode.overlay].
///
/// Eliminates banding because color mixing is per-pixel (no discrete stops).
/// Used as a full-bleed background behind content.
class UltraGradient extends StatelessWidget {
  const UltraGradient({super.key, this.colors, this.seed = 42});

  /// Colors for the soft blobs. Defaults to the app accent palette.
  final List<Color>? colors;

  /// Random seed for deterministic blob placement.
  final int seed;

  static const _defaults = [
    AfColors.accentPrimary,
    AfColors.accentSecondary,
    AfColors.accentMuted,
  ];

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _UltraGradientPainter(
          colors: colors ?? _defaults,
          seed: seed,
        ),
        size: Size.infinite,
      ),
    );
  }
}

/// Paints blurred color blobs over a dark base.
///
/// Soft blobs use heavy blur for broad color washes.
/// Contrasting blobs use lighter blur + [BlendMode.overlay] for richness.
class _UltraGradientPainter extends CustomPainter {
  _UltraGradientPainter({required this.colors, required this.seed});

  final List<Color> colors;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    // Base — solid dark.
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = AfColors.surfaceCanvas,
    );

    final rng = Random(seed);
    final center = Offset(size.width / 2, size.height / 2);

    // ── Soft blobs — heavy blur, broad color wash ──
    _paintSoftBlobs(canvas, size, center, rng);

    // ── Contrasting blobs — lighter blur, overlay blend ──
    _paintContrastingBlobs(canvas, size, center, rng);
  }

  void _paintSoftBlobs(
    Canvas canvas,
    Size size,
    Offset center,
    Random rng,
  ) {
    final paint = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 80);

    for (var i = 0; i < colors.length; i++) {
      paint.color = colors[i].withValues(alpha: 0.35);

      // Scatter blobs around center with some spread.
      final dx = (rng.nextDouble() - 0.5) * size.width * 0.7;
      final dy = (rng.nextDouble() - 0.5) * size.height * 0.7;
      final blobCenter = center + Offset(dx, dy);

      // Vary blob size based on index.
      final radius = size.width * (0.25 + rng.nextDouble() * 0.2);

      canvas.drawCircle(blobCenter, radius, paint);
    }
  }

  void _paintContrastingBlobs(
    Canvas canvas,
    Size size,
    Offset center,
    Random rng,
  ) {
    final paint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40)
      ..blendMode = BlendMode.overlay;

    // Ellipse
    if (colors.isNotEmpty) {
      paint.color = colors[0].withValues(alpha: 0.45);
      final dx = (rng.nextDouble() - 0.3) * size.width * 0.6;
      final dy = (rng.nextDouble() - 0.5) * size.height * 0.5;
      final blobCenter = center + Offset(dx, dy);
      final rx = size.width * (0.2 + rng.nextDouble() * 0.15);
      final ry = size.height * (0.12 + rng.nextDouble() * 0.1);
      canvas.drawOval(
        Rect.fromCenter(center: blobCenter, width: rx * 2, height: ry * 2),
        paint,
      );
    }

    // Circle
    if (colors.length > 1) {
      paint.color = colors[1].withValues(alpha: 0.40);
      final dx = (rng.nextDouble() - 0.7) * size.width * 0.6;
      final dy = (rng.nextDouble() - 0.3) * size.height * 0.5;
      final blobCenter = center + Offset(dx, dy);
      final radius = size.width * (0.15 + rng.nextDouble() * 0.12);
      canvas.drawCircle(blobCenter, radius, paint);
    }

    // Triangle (via path)
    if (colors.length > 2) {
      paint.color = colors[2].withValues(alpha: 0.35);
      final dx = (rng.nextDouble() - 0.5) * size.width * 0.5;
      final dy = (rng.nextDouble() - 0.6) * size.height * 0.4;
      final blobCenter = center + Offset(dx, dy);
      final s = size.width * (0.12 + rng.nextDouble() * 0.08);
      final path = Path()
        ..moveTo(blobCenter.dx, blobCenter.dy - s)
        ..lineTo(blobCenter.dx - s, blobCenter.dy + s)
        ..lineTo(blobCenter.dx + s, blobCenter.dy + s)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_UltraGradientPainter old) =>
      old.seed != seed || old.colors != colors;
}
