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

/// Compact mini player bar — sits between tab content and bottom nav.
///
/// Frosted glass effect: [ClipRect] + [BackdropFilter] + semi-transparent fill.
/// Artwork is wrapped in a circular progress ring showing playback position.
/// Prev / play-pause / next transport buttons.
/// Tapping the bar (outside buttons) pushes the full Now Playing screen.
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
      currentSpectralProvider.select((s) => (primary: s.primary)),
    );

    return GestureDetector(
      onTap: () => context.push('/now-playing'),
      onVerticalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v < -200) {
          // Swipe up → maximize now playing.
          context.push('/now-playing');
        } else if (v > 200) {
          // Swipe down → stop playback + dismiss mini player.
          ref.read(playerServiceProvider).stopAndClear();
        }
      },
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            height: height,
            color: AfColors.glassFillHeavy,
            child: Column(
              children: [
                // ── Content row ──
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AfSpacing.s8,
                      vertical: AfSpacing.s4,
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: AfSpacing.s4),
                        // ── Artwork with progress ring ──
                        _ArtworkRing(track: track, accent: spectral.primary),
                        const SizedBox(width: AfSpacing.s8),
                        // ── Title + artist ──
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Artwork wrapped in a circular progress ring.
class _ArtworkRing extends ConsumerWidget {
  const _ArtworkRing({required this.track, required this.accent});
  final AfTrack track;
  final Color accent;

  static const double _artworkSize = 48;
  static const double _ringStroke = 2.5;
  static const double _totalSize =
      _artworkSize + _ringStroke * 2 + 2; // +2 padding

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(positionStreamProvider);
    final duration = ref.watch(durationStreamProvider);
    final progress = duration > Duration.zero
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return SizedBox(
      width: _totalSize,
      height: _totalSize,
      child: CustomPaint(
        painter: _RingPainter(
          progress: progress.toDouble(),
          backgroundColor: AfColors.surfaceHigh,
          activeColor: accent,
          strokeWidth: _ringStroke,
        ),
        child: Padding(
          padding: const EdgeInsets.all(_ringStroke + 1),
          child: Artwork(
            url: track.imageUrl,
            size: _artworkSize,
            radius: AfRadii.borderSm,
          ),
        ),
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
    required this.strokeWidth,
  });

  final double progress;
  final Color backgroundColor;
  final Color activeColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Background ring
    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bgPaint);

    // Active progress arc
    if (progress > 0) {
      final activePaint = Paint()
        ..color = activeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      // Start from top (−π/2), sweep clockwise.
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
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.backgroundColor != backgroundColor ||
      old.activeColor != activeColor ||
      old.strokeWidth != strokeWidth;
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
        // ── Previous ──
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
        // ── Play / pause ──
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
        // ── Next ──
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
