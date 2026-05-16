import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_tokens/tokens.dart';
import '../state/providers.dart';
import 'artwork.dart';
import 'circular_progress_ring.dart';
import 'press_scale.dart';

/// Floating mini-player (mockup 04+).
///
/// Per non-negotiable §4.1:
///   - This is a **floating card**, NOT a bottom bar. 12dp side margins,
///     16dp gap above the bottom nav.
///   - Progress is a **circular ring around the play glyph**, NOT a
///     linear bar.
///   - Mini-player is NEVER swipe-to-dismiss.
class MiniPlayer extends ConsumerWidget {
  final VoidCallback? onTap;
  final VoidCallback? onPlayPause;
  final VoidCallback? onSkipNext;

  const MiniPlayer({
    super.key,
    this.onTap,
    this.onPlayPause,
    this.onSkipNext,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(currentTrackProvider);
    if (track == null) return const SizedBox.shrink();
    final isPlaying = ref.watch(playingStreamProvider).maybeWhen(
          data: (v) => v,
          orElse: () => false,
        );
    final position = ref.watch(positionStreamProvider);
    final spectral = ref.watch(currentSpectralProvider);
    final mpvDuration = ref.watch(durationStreamProvider);
    final duration = mpvDuration > Duration.zero ? mpvDuration : track.duration;
    final ringProgress = duration.inMilliseconds == 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AfSpacing.miniPlayerSideMargin,
      ),
      child: Semantics(
        label: 'Mini player. Now playing ${track.title} by ${track.artistName}.',
        button: true,
        child: PressScale(
          ensureHitTarget: false,
          onTap: onTap,
          child: Container(
            height: AfSpacing.miniPlayerHeight,
            decoration: BoxDecoration(
              color: AfColors.surfaceRaised,
              borderRadius: AfRadii.borderMd,
              border: Border.all(color: AfColors.surfaceHigh, width: 1),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AfSpacing.s8,
              vertical: 4,
            ),
            child: Row(
              children: [
                Hero(
                  tag: 'now-playing-artwork',
                  child: Artwork(
                    url: track.imageUrl,
                    size: 40,
                    radius: AfRadii.borderSm,
                  ),
                ),
                const SizedBox(width: AfSpacing.s12),
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
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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
                const SizedBox(width: AfSpacing.s8),
                _RingButton(
                  isPlaying: isPlaying,
                  progress: ringProgress,
                  color: spectral.energy,
                  onTap: onPlayPause,
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next_rounded,
                      color: AfColors.textPrimary),
                  onPressed: onSkipNext,
                  tooltip: 'Skip next',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingButton extends StatelessWidget {
  final bool isPlaying;
  final double progress;
  final Color color;
  final VoidCallback? onTap;

  const _RingButton({
    required this.isPlaying,
    required this.progress,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PressScale(
      ensureHitTarget: false,
      onTap: onTap,
      child: SizedBox(
        width: AfSpacing.minHitTarget,
        height: AfSpacing.minHitTarget,
        child: Center(
          child: CircularProgressRing(
            progress: progress,
            progressColor: color,
            size: 36,
            strokeWidth: 2,
            child: Icon(
              isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              color: AfColors.textPrimary,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}
