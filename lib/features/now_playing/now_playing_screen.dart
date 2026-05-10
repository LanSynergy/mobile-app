import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/demo/demo_library.dart';
import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../utils/time_format.dart';
import '../../widgets/artwork.dart';
import '../../widgets/press_scale.dart';
import '../../widgets/quality_chip.dart';
import '../../widgets/waveform.dart';

/// Mockup 10 — Now Playing.
class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(currentTrackProvider);
    final spectral = ref.watch(currentSpectralProvider);

    if (track == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Nothing playing yet.')),
      );
    }

    final positionAsync = ref.watch(positionStreamProvider);
    final position = positionAsync.maybeWhen(
      data: (p) => p,
      orElse: () => Duration.zero,
    );
    final isPlaying = ref.watch(playingStreamProvider).maybeWhen(
          data: (v) => v,
          orElse: () => false,
        );
    final duration = track.duration;
    final progress = duration.inMilliseconds == 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
    final peaks = track.peaks ?? DemoLibrary.peaksFor(track.id);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AfColors.surfaceCanvas,
              spectral.shadow,
            ],
            stops: const [0.4, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _TopBar(spectral: spectral, track: track),
              Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AfSpacing.gutterGenerous,
                    ),
                    child: Column(
                      children: [
                        const SizedBox(height: AfSpacing.s24),
                        Hero(
                          tag: 'now-playing-artwork',
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: AfRadii.borderLg,
                              boxShadow: [
                                BoxShadow(
                                  // ignore: deprecated_member_use
                                  color: spectral.shadow.withOpacity(0.6),
                                  blurRadius: 48,
                                  offset: const Offset(0, 24),
                                ),
                              ],
                            ),
                            child: Artwork(
                              url: track.imageUrl,
                              size: 320,
                              radius: AfRadii.borderLg,
                            ),
                          ),
                        ),
                        const SizedBox(height: AfSpacing.s24),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    track.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: AfTypography.titleLarge,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    track.artistName,
                                    style: AfTypography.bodyMedium.copyWith(
                                      color: AfColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                track.isFavorite
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                color: track.isFavorite
                                    ? AfColors.semanticError
                                    : AfColors.textPrimary,
                              ),
                              onPressed: () {},
                            ),
                            if (track.quality != null)
                              QualityChip(quality: track.quality!),
                          ],
                        ),
                        const SizedBox(height: AfSpacing.s24),
                        Waveform(
                          peaks: peaks,
                          progress: progress,
                          playedColor: spectral.energy,
                          onScrub: (p) {
                            final newPos = Duration(
                              milliseconds:
                                  (p * duration.inMilliseconds).round(),
                            );
                            ref.read(playerServiceProvider).seek(newPos);
                          },
                        ),
                        const SizedBox(height: AfSpacing.s8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              formatTrackDuration(position),
                              style: AfTypography.mono.copyWith(
                                color: AfColors.textSecondary,
                              ),
                            ),
                            Text(
                              formatRemaining(
                                  duration - position < Duration.zero
                                      ? Duration.zero
                                      : duration - position),
                              style: AfTypography.mono.copyWith(
                                color: AfColors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AfSpacing.s24),
                        _TransportRow(
                          isPlaying: isPlaying,
                          spectral: spectral,
                          onPlayPause: () {
                            final svc =
                                ref.read(playerServiceProvider);
                            isPlaying ? svc.pause() : svc.play();
                          },
                          onPrev: () =>
                              ref.read(playerServiceProvider).skipToPrevious(),
                          onNext: () =>
                              ref.read(playerServiceProvider).skipToNext(),
                        ),
                        const SizedBox(height: AfSpacing.s32),
                        _UtilityRow(),
                        const SizedBox(height: AfSpacing.s24),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final Spectral spectral;
  final AfTrack track;
  const _TopBar({required this.spectral, required this.track});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AfSpacing.s8,
        vertical: 4,
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
            onPressed: () => Navigator.maybePop(context),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  'Playing from album',
                  style: AfTypography.caption.copyWith(
                    color: AfColors.textTertiary,
                  ),
                ),
                Text(
                  track.albumName,
                  style: AfTypography.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.more_horiz_rounded),
            onPressed: () {},
          ),
        ],
      ),
    );
  }
}

class _TransportRow extends StatelessWidget {
  final bool isPlaying;
  final Spectral spectral;
  final VoidCallback onPlayPause;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _TransportRow({
    required this.isPlaying,
    required this.spectral,
    required this.onPlayPause,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _TransportButton(
          icon: Icons.shuffle_rounded,
          size: 28,
          onTap: () {},
        ),
        _TransportButton(
          icon: Icons.skip_previous_rounded,
          size: 40,
          onTap: onPrev,
        ),
        _PlayButton(
          isPlaying: isPlaying,
          color: spectral.energy,
          onTap: onPlayPause,
        ),
        _TransportButton(
          icon: Icons.skip_next_rounded,
          size: 40,
          onTap: onNext,
        ),
        _TransportButton(
          icon: Icons.repeat_rounded,
          size: 28,
          onTap: () {},
        ),
      ],
    );
  }
}

class _TransportButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final VoidCallback onTap;
  const _TransportButton({
    required this.icon,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: SizedBox(
        width: AfSpacing.minHitTarget,
        height: AfSpacing.minHitTarget,
        child: Icon(icon, size: size, color: AfColors.textPrimary),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  final bool isPlaying;
  final Color color;
  final VoidCallback onTap;

  const _PlayButton({
    required this.isPlaying,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PressScale(
      ensureHitTarget: false,
      onTap: onTap,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              // ignore: deprecated_member_use
              color: color.withOpacity(0.4),
              blurRadius: 32,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Icon(
          isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          color: AfColors.textOnPrimary,
          size: 32,
        ),
      ),
    );
  }
}

class _UtilityRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final items = const [
      (Icons.bedtime_outlined, 'Sleep', '/sleep'),
      (Icons.lyrics_outlined, 'Lyrics', '/lyrics'),
      (Icons.speed_rounded, 'Speed', null),
      (Icons.cast_outlined, 'Output', '/cast'),
      (Icons.playlist_add_rounded, 'Save', null),
      (Icons.queue_music_rounded, 'Queue', '/queue'),
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final (icon, label, route) in items)
          _UtilityIcon(icon: icon, label: label, route: route),
      ],
    );
  }
}

class _UtilityIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? route;
  const _UtilityIcon({
    required this.icon,
    required this.label,
    required this.route,
  });

  @override
  Widget build(BuildContext context) {
    return PressScale(
      ensureHitTarget: false,
      onTap: route == null ? null : () => context.push(route!),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AfSpacing.s8),
        child: Column(
          children: [
            Icon(icon, size: 22, color: AfColors.textSecondary),
            const SizedBox(height: 4),
            Text(
              label,
              style: AfTypography.caption.copyWith(
                color: AfColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
