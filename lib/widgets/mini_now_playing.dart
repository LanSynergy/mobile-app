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
/// Shows current track artwork, title, artist, and play/pause.
/// Tapping the bar pushes the full Now Playing screen.
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
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            height: height,
            color: AfColors.glassFillMedium,
            child: Column(
              children: [
                // ── Progress indicator ──
                _MiniProgressTrack(track: track, accent: spectral.primary),
                // ── Content row ──
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AfSpacing.s12,
                      vertical: AfSpacing.s4,
                    ),
                    child: Row(
                      children: [
                        // ── Artwork ──
                        Artwork(
                          url: track.imageUrl,
                          size: 48,
                          radius: AfRadii.borderSm,
                        ),
                        const SizedBox(width: AfSpacing.s12),
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
                                      isPlaying
                                          ? LucideIcons.pause
                                          : LucideIcons.play,
                                      size: 22,
                                      color: AfColors.textPrimary,
                                    ),
                            ),
                          ),
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

/// Thin progress line at the top of the mini player.
class _MiniProgressTrack extends ConsumerWidget {
  const _MiniProgressTrack({required this.track, required this.accent});
  final AfTrack track;
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(positionStreamProvider);
    final duration = ref.watch(durationStreamProvider);
    final progress = duration > Duration.zero
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return LinearProgressIndicator(
      value: progress.toDouble(),
      minHeight: 2,
      backgroundColor: AfColors.surfaceHigh,
      valueColor: AlwaysStoppedAnimation<Color>(accent),
    );
  }
}
