import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/marquee_text.dart';
import '../../widgets/press_scale.dart';

/// Frosted-glass top bar with expandable lyrics panel.
///
/// Collapsed: chevron-down · "PLAYING FROM ALBUM" · album name · lyrics mic icon
/// Expanded: same bar + synced lyrics list below
class FrostedTopBar extends ConsumerStatefulWidget {
  const FrostedTopBar({
    super.key,
    required this.track,
    required this.lyricsExpanded,
    required this.onToggleLyrics,
  });
  final AfTrack track;
  final ValueNotifier<bool> lyricsExpanded;
  final VoidCallback onToggleLyrics;

  @override
  ConsumerState<FrostedTopBar> createState() => _FrostedTopBarState();
}

class _FrostedTopBarState extends ConsumerState<FrostedTopBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _expandCtrl;
  late final Animation<double> _expandAnim;
  final _scrollCtrl = ScrollController();

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
    widget.lyricsExpanded.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant FrostedTopBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id) {
      _scrollCtrl.jumpTo(0);
    }
  }

  void _onChanged() {
    if (widget.lyricsExpanded.value) {
      _expandCtrl.forward();
    } else {
      _expandCtrl.reverse();
    }
  }

  @override
  void dispose() {
    widget.lyricsExpanded.removeListener(_onChanged);
    _expandCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spectral = ref.watch(currentSpectralProvider);
    final track = widget.track;

    final lrcAsync = ref.watch(lyricsProvider(track.id));
    final lrc = lrcAsync.maybeWhen(data: (p) => p, orElse: () => null);
    final position = ref.watch(positionStreamProvider);
    final isSynced =
        lrc != null && lrc.lines.any((l) => l.start > Duration.zero);
    final active = isSynced ? lrc.activeIndex(position) : -1;

    return AnimatedBuilder(
      animation: _expandAnim,
      builder: (context, _) {
        final isExpanded = _expandAnim.value > 0.5;
        final radius = isExpanded ? AfRadii.borderLg : AfRadii.borderPill;

        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AfSpacing.s16,
            vertical: isExpanded ? 0 : AfSpacing.s8,
          ),
          child: GestureDetector(
            onVerticalDragEnd: (details) {
              if ((details.primaryVelocity ?? 0) > 200 &&
                  widget.lyricsExpanded.value) {
                widget.onToggleLyrics();
              }
            },
            child: GlassCard(
              borderRadius: radius,
              blurSigma: 20,
              color: AfColors.glassFillStrong,
              borderColor: AfColors.glassBorderEmphasis,
              padding: EdgeInsets.zero,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Collapsed bar: always visible ──
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AfSpacing.s8,
                      vertical: AfSpacing.s4,
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(
                            LucideIcons.chevronDown,
                            color: AfColors.textPrimary,
                            size: 22,
                          ),
                          onPressed: () => Navigator.maybePop(context),
                        ),
                        const SizedBox(width: AfSpacing.s8),
                        Expanded(
                          child: PressScale(
                            ensureHitTarget: false,
                            onTap: track.albumId == null
                                ? null
                                : () => context.push('/album/${track.albumId}'),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: AfSpacing.s4,
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    'PLAYING FROM ALBUM',
                                    style: AfTypography.overline.copyWith(
                                      color: AfColors.textTertiary,
                                    ),
                                  ),
                                  MarqueeText(
                                    text: track.albumName,
                                    style: AfTypography.titleSmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: AfSpacing.s8),
                        IconButton(
                          icon: Icon(
                            LucideIcons.mic2,
                            color: widget.lyricsExpanded.value
                                ? spectral.energy
                                : AfColors.textPrimary,
                            size: 20,
                          ),
                          tooltip: 'Lyrics',
                          onPressed: widget.onToggleLyrics,
                        ),
                      ],
                    ),
                  ),

                  // ── Expanded lyrics ──
                  if (lrc != null && lrc.lines.isNotEmpty && isExpanded)
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.35,
                      child: ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AfSpacing.s16,
                          vertical: AfSpacing.s4,
                        ),
                        itemCount: lrc.lines.length,
                        itemBuilder: (context, i) {
                          final isActive = i == active;
                          final line = lrc.lines[i];
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: AfSpacing.s4,
                            ),
                            child: AnimatedDefaultTextStyle(
                              duration: AfDurations.quick,
                              style: AfTypography.bodyMedium.copyWith(
                                color: isActive
                                    ? spectral.energy
                                    : AfColors.textTertiary,
                                fontWeight: isActive
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                              child: Text(line.text),
                            ),
                          );
                        },
                      ),
                    )
                  else if (lrcAsync.isLoading && isExpanded)
                    const Padding(
                      padding: EdgeInsets.all(AfSpacing.s24),
                      child: Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AfColors.textTertiary,
                        ),
                      ),
                    )
                  else if (isExpanded)
                    Padding(
                      padding: const EdgeInsets.all(AfSpacing.s24),
                      child: Text(
                        'No lyrics available',
                        style: AfTypography.bodyMedium.copyWith(
                          color: AfColors.textTertiary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
