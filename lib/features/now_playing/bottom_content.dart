import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/favorite_heart_button.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/marquee_text.dart';
import '../../widgets/press_scale.dart';
import 'more_menu.dart';
import 'reactive_progress.dart';
import 'transport_widgets.dart';

/// Bottom content zone — metadata, scrubber, transport, expandable queue.
///
/// Swipe up on non-scrubber area to reveal the up-next queue panel.
class BottomContent extends ConsumerStatefulWidget {
  const BottomContent({
    super.key,
    required this.track,
    required this.expandedNotifier,
  });
  final AfTrack track;
  final ValueNotifier<bool> expandedNotifier;

  @override
  ConsumerState<BottomContent> createState() => _BottomContentState();
}

class _BottomContentState extends ConsumerState<BottomContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _expandCtrl;
  late final Animation<double> _expandAnim;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _expandCtrl = AnimationController(
      vsync: this,
      duration: AfDurations.standard,
      reverseDuration: AfDurations.quick,
    );
    _expandAnim = CurvedAnimation(
      parent: _expandCtrl,
      curve: AfCurves.easeEmphasized,
    );
    widget.expandedNotifier.addListener(_onExpandChanged);
  }

  void _onExpandChanged() {
    final target = widget.expandedNotifier.value;
    if (target != _expanded) {
      setState(() => _expanded = target);
      if (_expanded) {
        _expandCtrl.forward();
      } else {
        _expandCtrl.reverse();
      }
    }
  }

  @override
  void didUpdateWidget(covariant BottomContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id && _expanded) {
      _toggleExpand();
    }
  }

  @override
  void dispose() {
    widget.expandedNotifier.removeListener(_onExpandChanged);
    _expandCtrl.dispose();
    super.dispose();
  }

  void _toggleExpand() {
    widget.expandedNotifier.value = !widget.expandedNotifier.value;
  }

  @override
  Widget build(BuildContext context) {
    final queue = ref.watch(playerServiceProvider).currentQueue;
    final currentIndex = ref.watch(playerServiceProvider).currentIndex;

    // Up-next queue: items after the current track
    final upNext = queue.length > 1
        ? queue.sublist(currentIndex + 1).take(20).toList()
        : <AfTrack>[];

    return AnimatedBuilder(
      animation: _expandAnim,
      builder: (context, _) {
        // Interpolate max height: compact ~36% → expanded ~70% (below top bar)
        final screenH = MediaQuery.of(context).size.height;
        final compactH = screenH * 0.36;
        final expandedH = screenH - kToolbarHeight - 80; // below top bar
        final currentH = compactH + (expandedH - compactH) * _expandAnim.value;

        return SizedBox(
          height: currentH,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragEnd: (details) {
              final vy = details.primaryVelocity ?? 0;
              if (vy < -200 || (vy < 0 && !_expanded)) {
                if (!_expanded) _toggleExpand();
              } else if (vy > 200 || (vy > 0 && _expanded)) {
                if (_expanded) _toggleExpand();
              }
            },
            child: GlassCard(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AfRadii.lg),
              ),
              padding: EdgeInsets.zero,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AfSpacing.s16,
                      AfSpacing.s12,
                      AfSpacing.s16,
                      AfSpacing.s8,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ── Metadata overlay (title + artist) ──
                        MetadataOverlay(track: widget.track),
                        const SizedBox(height: AfSpacing.s12),
                        // ── Visualizer scrubber ──
                        ReactiveProgress(track: widget.track),
                        const SizedBox(height: AfSpacing.s12),
                        // ── Transport controls ──
                        ReactiveTransport(track: widget.track),
                      ],
                    ),
                  ),

                  // ── Expandable queue section ──
                  if (_expanded && upNext.isNotEmpty) ...[
                    const Divider(height: 1, color: AfColors.surfaceHigh),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AfSpacing.s16,
                        vertical: AfSpacing.s8,
                      ),
                      child: Row(
                        children: [
                          Text(
                            'Up Next',
                            style: AfTypography.titleSmall.copyWith(
                              color: AfColors.textSecondary,
                            ),
                          ),
                          const SizedBox(width: AfSpacing.s8),
                          Text(
                            '${upNext.length} tracks',
                            style: AfTypography.caption.copyWith(
                              color: AfColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: ListView.builder(
                        padding: const EdgeInsets.only(bottom: AfSpacing.s8),
                        itemCount: upNext.length,
                        itemBuilder: (context, index) {
                          final t = upNext[index];
                          return PressScale(
                            onTap: () {
                              ref
                                  .read(playerServiceProvider)
                                  .skipToQueueItem(queue.indexOf(t));
                            },
                            child: ListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              leading: Text(
                                '${index + 1}',
                                style: AfTypography.caption.copyWith(
                                  color: AfColors.textTertiary,
                                ),
                              ),
                              title: Text(
                                t.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AfTypography.bodyMedium,
                              ),
                              subtitle: Text(
                                t.artistName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AfTypography.caption.copyWith(
                                  color: AfColors.textTertiary,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Title + artist row with heart toggle, quality badge, and more menu.
class MetadataOverlay extends ConsumerWidget {
  const MetadataOverlay({super.key, required this.track});
  final AfTrack track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spectral = ref.watch(currentSpectralProvider);
    return Row(
      children: [
        // Title + artist
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              MarqueeText(text: track.title, style: AfTypography.titleMedium),
              const SizedBox(height: AfSpacing.s4),
              PressScale(
                ensureHitTarget: false,
                onTap: track.artistId == null
                    ? null
                    : () => context.push('/artist/${track.artistId}'),
                child: Semantics(
                  label: track.artistId == null
                      ? null
                      : 'Go to artist ${track.artistName}',
                  button: track.artistId != null,
                  child: Text(
                    track.artistName,
                    style: AfTypography.bodySmall.copyWith(
                      color: track.artistId == null
                          ? AfColors.textSecondary
                          : spectral.link,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AfSpacing.s12),
        // Heart toggle
        FavoriteHeartButton(track: track, size: 22),
        // Quality badge
        if (track.quality != null) ...[
          const SizedBox(width: AfSpacing.s4),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AfSpacing.s8,
              vertical: AfSpacing.s4,
            ),
            decoration: BoxDecoration(
              color: spectral.muted.withValues(alpha: 0.2),
              borderRadius: AfRadii.borderPill,
            ),
            child: Text(
              track.quality!.chipLabel,
              style: AfTypography.caption.copyWith(color: AfColors.textPrimary),
            ),
          ),
        ],
        // More menu (vertical dots)
        IconButton(
          icon: const Icon(
            LucideIcons.ellipsisVertical,
            size: 22,
            color: AfColors.textSecondary,
          ),
          tooltip: 'More options',
          onPressed: () => showMoreSheet(context, ref),
        ),
      ],
    );
  }
}
