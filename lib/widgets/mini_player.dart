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
import 'marquee_text.dart';
import 'circular_progress_ring.dart';
import 'press_scale.dart';

class MiniPlayer extends ConsumerStatefulWidget {
  const MiniPlayer({
    super.key,
    this.onTap,
    this.onPlayPause,
    this.onSkipNext,
    this.onSkipPrevious,
    this.onDismiss,
  });
  final VoidCallback? onTap;
  final VoidCallback? onPlayPause;
  final VoidCallback? onSkipNext;
  final VoidCallback? onSkipPrevious;
  final VoidCallback? onDismiss;

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer>
    with SingleTickerProviderStateMixin {
  static const double _swipeVelocityThreshold = 300;
  static const double _swipeDistanceThreshold = 50;
  static const double _maxDragDistance = 200;

  double _dragDistance = 0;
  late final AnimationController _snapCtrl;

  @override
  void initState() {
    super.initState();
    _snapCtrl = AnimationController(vsync: this, duration: AfDurations.quick)
      ..addListener(() {
        setState(() => _dragDistance = _snapCtrl.value * _maxDragDistance * 2);
      });
  }

  @override
  void dispose() {
    _snapCtrl.dispose();
    super.dispose();
  }

  void _snapBack() {
    _snapCtrl.duration = AfDurations.quick;
    _snapCtrl.value = _dragDistance / (_maxDragDistance * 2);
    _snapCtrl.reverse();
  }

  void _animateDismiss() {
    _snapCtrl.duration = AfDurations.expressive;
    _snapCtrl.value = _dragDistance / (_maxDragDistance * 2);
    _snapCtrl.forward().then((_) {
      if (mounted) widget.onDismiss?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final track = ref.watch(currentTrackProvider);
    if (track == null) return const SizedBox.shrink();
    final artworkUri = ref.watch(currentArtworkUriProvider);
    final isPlaying = ref
        .watch(playingStreamProvider)
        .maybeWhen(data: (v) => v, orElse: () => false);
    final isBuffering = ref.watch(isBufferingProvider);
    final spectral = ref.watch(currentSpectralProvider.select((s) => s.energy));

    final clampedDy = _dragDistance.clamp(0, _maxDragDistance * 2).toDouble();
    final dragOpacity = 1.0 - (clampedDy / _maxDragDistance).clamp(0, 1);

    return Material(
      type: MaterialType.transparency,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AfSpacing.miniPlayerSideMargin,
        ),
        child: Semantics(
          label:
              'Mini player. Now playing ${track.title} by ${track.artistName}.',
          button: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: (_) {
              if (_snapCtrl.isAnimating) _snapCtrl.stop();
              _dragDistance = 0;
            },
            onVerticalDragUpdate: (details) {
              setState(() {
                _dragDistance += details.primaryDelta ?? 0;
              });
            },
            onVerticalDragEnd: (details) {
              final vy = details.primaryVelocity ?? 0;
              final absVy = vy.abs();
              final absDist = _dragDistance.abs();

              final isFlick = absVy >= _swipeVelocityThreshold;
              final isSignificantDrag = absDist >= _swipeDistanceThreshold;

              if (isFlick || isSignificantDrag) {
                final bool isUpward = isFlick ? (vy < 0) : (_dragDistance < 0);
                unawaited(HapticFeedback.selectionClick());
                if (isUpward) {
                  setState(() => _dragDistance = 0);
                  widget.onTap?.call();
                } else {
                  _animateDismiss();
                }
              } else {
                _snapBack();
              }
            },
            child: Opacity(
              opacity: dragOpacity,
              child: Transform.translate(
                offset: Offset(0, clampedDy),
                child: PressScale(
                  ensureHitTarget: false,
                  onTap: widget.onTap,
                  child: RepaintBoundary(
                    child: ClipRRect(
                      borderRadius: AfRadii.borderPill,
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                        child: Container(
                          height: AfSpacing.miniPlayerHeight,
                          decoration: BoxDecoration(
                            color: AfColors.glassFillStrong,
                            borderRadius: AfRadii.borderPill,
                            border: Border.all(
                              color: AfColors.surfaceHigh.withValues(
                                alpha: 0.5,
                              ),
                              width: 1,
                            ),
                          ),
                          padding: const EdgeInsets.only(
                            left: AfSpacing.s4,
                            right: AfSpacing.s8,
                          ),
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
                                      borderRadius: AfRadii.borderMd,
                                      child: Artwork(
                                        url:
                                            artworkUri?.toString() ??
                                            track.imageUrl,
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
                                    MarqueeText(
                                      text: track.title,
                                      style: AfTypography.bodyMedium.copyWith(
                                        color: AfColors.textPrimary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      speedPxPerSec: 25.0,
                                      minDurationMs: 6000,
                                      maxDurationMs: 25000,
                                    ),
                                    MarqueeText(
                                      text: track.artistName,
                                      style: AfTypography.bodySmall.copyWith(
                                        color: AfColors.textSecondary,
                                      ),
                                      speedPxPerSec: 25.0,
                                      minDurationMs: 6000,
                                      maxDurationMs: 25000,
                                    ),
                                  ],
                                ),
                              ),
                              Semantics(
                                button: true,
                                label: 'Skip previous',
                                child: _MiniTransportButton(
                                  icon: const Icon(
                                    LucideIcons.skipBack,
                                    size: 24,
                                    color: AfColors.textPrimary,
                                  ),
                                  onTap: widget.onSkipPrevious,
                                ),
                              ),
                              PressScale(
                                ensureHitTarget: false,
                                onTap: widget.onPlayPause,
                                child: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: spectral,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: isBuffering
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.0,
                                              color: AfColors.surfaceCanvas,
                                            ),
                                          )
                                        : Icon(
                                            isPlaying
                                                ? LucideIcons.pause
                                                : LucideIcons.play,
                                            color: AfColors.surfaceCanvas,
                                            size: 24,
                                          ),
                                  ),
                                ),
                              ),
                              Semantics(
                                button: true,
                                label: 'Skip next',
                                child: _MiniTransportButton(
                                  icon: const Icon(
                                    LucideIcons.skipForward,
                                    size: 24,
                                    color: AfColors.textPrimary,
                                  ),
                                  onTap: widget.onSkipNext,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
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
    final positionMs = ref.watch(
      positionStreamProvider.select((d) => d.inMilliseconds),
    );
    final mpvDuration = ref.watch(durationStreamProvider);
    final isBuffering = ref.watch(isBufferingProvider);
    // Show metadata duration immediately, but freeze progress bar at 0
    // while buffering — mpv's position isn't meaningful until playback starts.
    final duration = mpvDuration > Duration.zero ? mpvDuration : track.duration;
    final effectivePositionMs = isBuffering ? 0 : positionMs;
    final ringProgress = duration.inMilliseconds == 0
        ? 0.0
        : (effectivePositionMs / duration.inMilliseconds).clamp(0.0, 1.0);
    final energyColor = ref.watch(
      currentSpectralProvider.select((s) => s.energy),
    );

    return CircularProgressRing(
      progress: ringProgress,
      progressColor: energyColor,
      size: 48,
      strokeWidth: 2,
      isIndeterminate: isBuffering,
      child: child,
    );
  }
}
