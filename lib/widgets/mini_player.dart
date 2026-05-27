import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/jellyfin/models/items.dart';
import '../design_tokens/tokens.dart';
import '../state/providers.dart';
import 'artwork.dart';
import 'circular_progress_ring.dart';
import 'press_scale.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({
    super.key,
    this.onTap,
    this.onPlayPause,
    this.onSkipNext,
    this.onSkipPrevious,
  });
  final VoidCallback? onTap;
  final VoidCallback? onPlayPause;
  final VoidCallback? onSkipNext;
  final VoidCallback? onSkipPrevious;

  static const double _swipeVelocityThreshold = 600;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(currentTrackProvider);
    if (track == null) return const SizedBox.shrink();
    final artworkUri = ref.watch(currentArtworkUriProvider);
    final isPlaying = ref
        .watch(playingStreamProvider)
        .maybeWhen(data: (v) => v, orElse: () => false);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AfSpacing.miniPlayerSideMargin,
      ),
      child: Semantics(
        label:
            'Mini player. Now playing ${track.title} by ${track.artistName}.',
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragEnd: (details) {
            final vx = details.primaryVelocity ?? 0;
            if (vx.abs() < _swipeVelocityThreshold) return;
            unawaited(HapticFeedback.selectionClick());
            if (vx < 0) {
              onSkipNext?.call();
            } else {
              onSkipPrevious?.call();
            }
          },
          child: PressScale(
            ensureHitTarget: false,
            onTap: onTap,
            child: ClipRRect(
              borderRadius: AfRadii.borderPill,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  height: AfSpacing.miniPlayerHeight,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: AfRadii.borderPill,
                    border: Border.all(
                      color: AfColors.surfaceHigh.withValues(alpha: 0.5),
                      width: 1,
                    ),
                  ),
                  padding: const EdgeInsets.only(left: 4, right: AfSpacing.s8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: _ReactiveProgressRing(
                          track: track,
                          child: Hero(
                            tag: 'now-playing-artwork',
                            child: ClipRRect(
                              borderRadius: AfRadii.borderPill,
                              child: Artwork(
                                url: artworkUri?.toString() ?? track.imageUrl,
                                size: 44,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AfSpacing.s12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _MarqueeText(
                              text: track.title,
                              style: AfTypography.bodyMedium.copyWith(
                                color: AfColors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            _MarqueeText(
                              text: track.artistName,
                              style: AfTypography.bodySmall.copyWith(
                                color: AfColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _MiniTransportButton(
                        icon: const Icon(
                          LucideIcons.skipBack,
                          size: 24,
                          color: AfColors.textPrimary,
                        ),
                        onTap: onSkipPrevious,
                      ),
                      PressScale(
                        ensureHitTarget: false,
                        onTap: onPlayPause,
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Icon(
                              isPlaying ? LucideIcons.pause : LucideIcons.play,
                              color: Colors.black,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                      _MiniTransportButton(
                        icon: const Icon(
                          LucideIcons.skipForward,
                          size: 24,
                          color: AfColors.textPrimary,
                        ),
                        onTap: onSkipNext,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniTransportButton extends StatelessWidget {
  const _MiniTransportButton({required this.icon, required this.onTap});
  final Widget icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: SizedBox(width: 48, height: 48, child: Center(child: icon)),
    );
  }
}

class _ReactiveProgressRing extends ConsumerWidget {
  const _ReactiveProgressRing({required this.track, required this.child});

  final AfTrack track;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(positionStreamProvider);
    final mpvDuration = ref.watch(durationStreamProvider);
    final duration = mpvDuration > Duration.zero ? mpvDuration : track.duration;
    final ringProgress = duration.inMilliseconds == 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
    final energyColor = ref.watch(currentSpectralProvider).energy;

    return CircularProgressRing(
      progress: ringProgress,
      progressColor: energyColor,
      size: 48,
      strokeWidth: 2,
      child: child,
    );
  }
}

/// Scrolls [text] when it overflows. Fixed layout — uses [ClipRect] +
/// [SizedBox] + [Stack] so parent constraints are never broken.
class _MarqueeText extends StatefulWidget {
  const _MarqueeText({required this.text, required this.style});
  final String text;
  final TextStyle style;

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  double _offset = 0.0;
  bool _shouldScroll = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void didUpdateWidget(covariant _MarqueeText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _controller.stop();
      _controller.value = 0;
      _shouldScroll = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final tp = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout();

        if (tp.width <= maxWidth) {
          if (_shouldScroll) {
            _controller.stop();
            _controller.value = 0;
            _shouldScroll = false;
          }
          return SizedBox(
            width: maxWidth,
            child: Text(widget.text, maxLines: 1, style: widget.style),
          );
        }

        if (!_shouldScroll) {
          _shouldScroll = true;
          _offset = tp.width + 32.0;
          final durationMs = (_offset / 25.0 * 1000).round().clamp(6000, 25000);
          _controller.duration = Duration(milliseconds: durationMs);
          _controller.repeat();
        }

        return ClipRect(
          child: SizedBox(
            width: maxWidth,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    return Transform.translate(
                      offset: Offset(-_offset * _controller.value, 0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(widget.text, maxLines: 1, style: widget.style),
                          const SizedBox(width: 32),
                          Text(widget.text, maxLines: 1, style: widget.style),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
