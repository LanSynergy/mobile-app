import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/jellyfin/models/items.dart';
import '../design_tokens/tokens.dart';
import '../state/providers.dart';
import 'artwork.dart';
import 'press_scale.dart';

/// Compact mini player bar — floats above bottom nav.
///
/// Frosted glass pill: [ClipRRect] + [BackdropFilter] + spectral tint.
/// Artwork is static; only the progress ring ticks on position updates.
class MiniNowPlaying extends ConsumerWidget {
  const MiniNowPlaying({super.key});

  static const double height = AfSpacing.bottomNavHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(currentTrackProvider);
    if (track == null) return const SizedBox.shrink();

    final isPlaying = ref
        .watch(playingStreamProvider)
        .maybeWhen(data: (v) => v, orElse: () => false);
    final isBuffering = ref.watch(isBufferingProvider);
    final spectral = ref.watch(
      currentSpectralProvider.select(
        (s) => (primary: s.primary, shadow: s.shadow),
      ),
    );

    return GestureDetector(
      onTap: () => context.push('/now-playing'),
      onVerticalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v < -200) {
          context.push('/now-playing');
        } else if (v > 200) {
          ref.read(playerServiceProvider).stopAndClear();
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(height / 2),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              height: height,
              decoration: BoxDecoration(
                color: spectral.shadow.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(height / 2),
                border: Border.all(
                  color: spectral.primary.withValues(alpha: 0.2),
                  width: 0.5,
                ),
              ),
              child: Row(
                children: [
                  const SizedBox(width: AfSpacing.s4),
                  // ── Artwork with progress ring (ring only rebuilds) ──
                  _ArtworkRing(track: track, accent: spectral.primary),
                  const SizedBox(width: AfSpacing.s8),
                  // ── Title + artist (static, no position watch) ──
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AfTypography.bodyMedium.copyWith(
                            color: AfColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: AfSpacing.s2),
                        Text(
                          track.artistName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AfTypography.bodySmall.copyWith(
                            color: AfColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // ── Transport: prev / play-pause / next ──
                  _MiniTransport(
                    isPlaying: isPlaying,
                    isBuffering: isBuffering,
                    accent: spectral.primary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Artwork wrapped in a circular progress ring.
///
/// Architecture: the [Artwork] image is a **static child** that does NOT
/// watch positionStreamProvider. The progress ring is a [RepaintBoundary]
/// + [CustomPaint] that only calls [StatefulRepaint] on position ticks.
/// This avoids rebuilding the network image widget every ~200ms.
class _ArtworkRing extends ConsumerWidget {
  const _ArtworkRing({required this.track, required this.accent});
  final AfTrack track;
  final Color accent;

  static const double _artworkSize = 48;
  static const double _ringStroke = 2.5;
  static const double _totalSize = _artworkSize + _ringStroke * 2 + 2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: _totalSize,
      height: _totalSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Static artwork — never rebuilds on position ticks.
          Padding(
            padding: const EdgeInsets.all(_ringStroke + 1),
            child: Artwork(
              url: track.imageUrl,
              size: _artworkSize,
              radius: BorderRadius.circular(_artworkSize / 2),
            ),
          ),
          // Progress ring — only this repaints on position ticks.
          Positioned.fill(
            child: RepaintBoundary(child: _ProgressRing(accent: accent)),
          ),
        ],
      ),
    );
  }
}

/// Minimal progress ring that only rebuilds on position ticks.
///
/// Uses a [StatefulBuilder] to listen to position without triggering
/// a full widget rebuild of the parent tree.
class _ProgressRing extends ConsumerWidget {
  const _ProgressRing({required this.accent});
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only this small widget watches position — NOT the artwork.
    final position = ref.watch(positionStreamProvider);
    final duration = ref.watch(durationStreamProvider);
    final progress = duration > Duration.zero
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return CustomPaint(
      painter: _RingPainter(
        progress: progress.toDouble(),
        backgroundColor: AfColors.surfaceHigh,
        activeColor: accent,
      ),
    );
  }
}

/// Custom painter for the circular progress ring around artwork.
class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.backgroundColor,
    required this.activeColor,
  });

  static const double _strokeWidth = 2.5;

  final double progress;
  final Color backgroundColor;
  final Color activeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - _strokeWidth) / 2;

    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bgPaint);

    if (progress > 0) {
      final activePaint = Paint()
        ..color = activeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        activePaint,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}

/// Mini transport controls — prev / play-pause / next.
class _MiniTransport extends ConsumerWidget {
  const _MiniTransport({
    required this.isPlaying,
    required this.isBuffering,
    required this.accent,
  });
  final bool isPlaying;
  final bool isBuffering;
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PressScale(
          ensureHitTarget: false,
          onTap: () => ref.read(playerServiceProvider).skipToPrevious(),
          child: const SizedBox(
            width: AfSpacing.minHitTarget,
            height: AfSpacing.minHitTarget,
            child: Center(
              child: Icon(
                LucideIcons.skipBack,
                size: 20,
                color: AfColors.textPrimary,
              ),
            ),
          ),
        ),
        PressScale(
          ensureHitTarget: false,
          onTap: () {
            final svc = ref.read(playerServiceProvider);
            isPlaying ? svc.pause() : svc.play();
          },
          child: SizedBox(
            width: AfSpacing.minHitTarget,
            height: AfSpacing.minHitTarget,
            child: Center(
              child: isBuffering
                  ? const SizedBox(
                      width: AfSpacing.s20,
                      height: AfSpacing.s20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AfColors.textSecondary,
                      ),
                    )
                  : Icon(
                      isPlaying ? LucideIcons.pause : LucideIcons.play,
                      size: 22,
                      color: AfColors.textPrimary,
                    ),
            ),
          ),
        ),
        PressScale(
          ensureHitTarget: false,
          onTap: () => ref.read(playerServiceProvider).skipToNext(),
          child: const SizedBox(
            width: AfSpacing.minHitTarget,
            height: AfSpacing.minHitTarget,
            child: Center(
              child: Icon(
                LucideIcons.skipForward,
                size: 20,
                color: AfColors.textPrimary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
