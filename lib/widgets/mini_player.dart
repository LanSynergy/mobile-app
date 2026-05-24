import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
///   - Mini-player is NEVER swipe-to-dismiss. Horizontal swipes are
///     instead repurposed as skip-next / skip-previous shortcuts —
///     matching Spotify / Apple Music / YouTube Music conventions —
///     while vertical drags are ignored entirely.
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

  /// Velocity threshold (logical px/s) above which a horizontal drag
  /// commits to a skip. Below this, the gesture is treated as a stray
  /// slide and ignored so the tap-to-open behaviour stays crisp.
  static const double _swipeVelocityThreshold = 600;

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
        child: GestureDetector(
          // Horizontal-only drag detector. Vertical drags propagate to
          // the surrounding scroll views; horizontal drags are caught
          // here so the swipe-to-skip gesture wins over any ambient
          // horizontal page scroll.
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
            borderRadius: AfRadii.borderMd,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
              height: AfSpacing.miniPlayerHeight,
              decoration: BoxDecoration(
                color: AfColors.surfaceRaised.withValues(alpha: 0.70),
                borderRadius: AfRadii.borderMd,
                border: Border.all(color: AfColors.surfaceHigh.withValues(alpha: 0.5), width: 1),
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
          ),
        ),
      ),
    );
  }
}

class _RingButton extends StatelessWidget {

  const _RingButton({
    required this.isPlaying,
    required this.progress,
    required this.color,
    this.onTap,
  });
  final bool isPlaying;
  final double progress;
  final Color color;
  final VoidCallback? onTap;

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

/// Scrolls [text] from right to left when it exceeds the available width.
/// Falls back to a static [Text] when the content fits.
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
          return Text(widget.text, maxLines: 1, style: widget.style);
        }

        if (!_shouldScroll) {
          _shouldScroll = true;
          _offset = tp.width + 32.0;
          final durationMs = (_offset / 40.0 * 1000).round().clamp(4000, 16000);
          _controller.duration = Duration(milliseconds: durationMs);
          _controller.repeat();
        }

        return ClipRect(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
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
        );
      },
    );
  }
}
