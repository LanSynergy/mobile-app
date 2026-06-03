import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/jellyfin/models/items.dart';
import '../../core/lyrics/lrc_parser.dart';
import '../../core/local/local_backend.dart';
import '../../core/local/saf_picker.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/marquee_text.dart';
import '../../widgets/press_scale.dart';

/// Frosted-glass top bar with expandable lyrics panel.
///
/// Collapsed: chevron-down · "PLAYING FROM ALBUM" · album name · lyrics mic icon
/// Expanded: same bar + synced lyrics list with auto-scroll, tap-to-seek,
///           user scroll pause, and LRC file import for local backends.
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

  /// Estimated height of a single lyric row in logical pixels.
  static const double _rowHeight = 36.0;

  /// Index of the active line on the previous build.
  int _lastScrolledIndex = -1;

  /// Whether the user has manually scrolled. Pauses auto-scroll.
  bool _userScrolled = false;
  Timer? _userScrollTimer;

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
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant FrostedTopBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id) {
      _scrollCtrl.jumpTo(0);
      _lastScrolledIndex = -1;
      _userScrolled = false;
      _userScrollTimer?.cancel();
    }
  }

  void _onChanged() {
    if (widget.lyricsExpanded.value) {
      _expandCtrl.forward();
    } else {
      _expandCtrl.reverse();
    }
  }

  void _onScroll() {
    if (_scrollControllerHasClients &&
        _scrollControllerUserScrollDirection != ScrollDirection.idle) {
      if (!_userScrolled) {
        setState(() {
          _userScrolled = true;
        });
      }
      _userScrollTimer?.cancel();
      _userScrollTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) {
          setState(() {
            _userScrolled = false;
            _lastScrolledIndex = -1;
          });
        }
      });
    }
  }

  bool get _scrollControllerHasClients => _scrollCtrl.hasClients;

  ScrollDirection get _scrollControllerUserScrollDirection =>
      _scrollCtrl.hasClients
      ? _scrollCtrl.position.userScrollDirection
      : ScrollDirection.idle;

  /// Scroll the list so the active line sits in the vertical centre.
  void _scrollToActive(int activeIndex, int lineCount) {
    if (!_scrollCtrl.hasClients) {
      _lastScrolledIndex = -1;
      return;
    }

    final viewportHeight = _scrollCtrl.position.viewportDimension;
    final minScroll = _scrollCtrl.position.minScrollExtent;
    final maxScroll = _scrollCtrl.position.maxScrollExtent;

    final expectedContentHeight = lineCount * _rowHeight;
    if (maxScroll == 0.0 && expectedContentHeight > viewportHeight) {
      _lastScrolledIndex = -1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      return;
    }

    const paddingTop = AfSpacing.s16;
    final target =
        paddingTop +
        (activeIndex * _rowHeight) -
        (viewportHeight / 2) +
        (_rowHeight / 2);
    final clamped = target.clamp(minScroll, maxScroll);

    _scrollCtrl.animateTo(
      clamped,
      duration: AfDurations.standard,
      curve: AfCurves.easeStandard,
    );
  }

  @override
  void dispose() {
    widget.lyricsExpanded.removeListener(_onChanged);
    _scrollCtrl.removeListener(_onScroll);
    _expandCtrl.dispose();
    _scrollCtrl.dispose();
    _userScrollTimer?.cancel();
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

    // Auto-scroll to active line.
    if (lrc != null &&
        lrc.lines.isNotEmpty &&
        active >= 0 &&
        active != _lastScrolledIndex &&
        !_userScrolled) {
      _lastScrolledIndex = active;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToActive(active, lrc.lines.length);
      });
    }

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
              tintOpacity: 0.15,
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
                          onPressed: () => context.pop(),
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
                    _LyricsList(
                      lrc: lrc,
                      active: active,
                      spectralEnergy: spectral.energy,
                      scrollController: _scrollCtrl,
                      isSynced: isSynced,
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
                    _EmptyLyrics(track: track),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Lyrics list — auto-scroll, tap-to-seek, user scroll pause
// ─────────────────────────────────────────────────────────────────────────────

class _LyricsList extends ConsumerWidget {
  const _LyricsList({
    required this.lrc,
    required this.active,
    required this.spectralEnergy,
    required this.scrollController,
    required this.isSynced,
  });

  final Lrc lrc;
  final int active;
  final Color spectralEnergy;
  final ScrollController scrollController;
  final bool isSynced;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.35,
      child: ListView.builder(
        controller: scrollController,
        padding: const EdgeInsets.symmetric(
          horizontal: AfSpacing.s16,
          vertical: AfSpacing.s4,
        ),
        itemCount: lrc.lines.length,
        itemBuilder: (context, i) {
          final isActive = i == active;
          final line = lrc.lines[i];
          return InkWell(
            borderRadius: AfRadii.borderSm,
            onTap: isSynced
                ? () {
                    unawaited(HapticFeedback.selectionClick());
                    ref.read(playerServiceProvider).seek(line.start);
                  }
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AfSpacing.s4),
              child: AnimatedDefaultTextStyle(
                duration: AfDurations.quick,
                style: AfTypography.bodyLarge.copyWith(
                  color: isActive
                      ? spectralEnergy
                      : AfColors.textPrimary.withValues(alpha: 0.7),
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  shadows: isActive
                      ? [
                          Shadow(
                            color: spectralEnergy.withValues(alpha: 0.5),
                            blurRadius: 8,
                          ),
                        ]
                      : null,
                ),
                child: Text(line.text),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty lyrics state — with LRC file import for local backends
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyLyrics extends ConsumerWidget {
  const _EmptyLyrics({required this.track});
  final AfTrack track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spectral = ref.watch(currentSpectralProvider);
    final backend = ref.watch(musicBackendProvider);
    final isLocal = backend is LocalBackend;

    return Padding(
      padding: const EdgeInsets.all(AfSpacing.s24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'No lyrics available',
            style: AfTypography.bodyMedium.copyWith(
              color: AfColors.textTertiary,
            ),
          ),
          if (isLocal) ...[
            const SizedBox(height: AfSpacing.s12),
            FilledButton.icon(
              onPressed: () async {
                final lyricsContent = await SafPicker.pickAndReadLrcFile();
                if (lyricsContent == null || lyricsContent.trim().isEmpty) {
                  return;
                }

                final success = await backend.saveSidecarLrc(
                  track.id,
                  lyricsContent,
                );
                if (success) {
                  ref.invalidate(lyricsProvider(track.id));
                } else {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Failed to save lyrics')),
                    );
                  }
                }
              },
              icon: const Icon(LucideIcons.upload, size: 18),
              label: const Text('Load LRC File'),
              style: FilledButton.styleFrom(backgroundColor: spectral.primary),
            ),
          ],
        ],
      ),
    );
  }
}
