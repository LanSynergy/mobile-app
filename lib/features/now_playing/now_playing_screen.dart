import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show Loop;

import '../../core/audio/af_loop_mode.dart';
import '../../core/audio/shuffle_mode.dart';
import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../utils/oklch.dart';
import '../../utils/time_format.dart';
import '../../widgets/audio_visual_scrubber.dart';
import '../../widgets/af_dialog.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/marquee_text.dart';
import '../../widgets/press_scale.dart';
import '../../widgets/empty_state.dart';
import 'reactive_artwork.dart';
import 'more_menu.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NowPlayingScreen — "Dark Moody" immersive rebuild
//
// Design system: Deep blacks (#0A0A0A), warm amber accents (#D4A574),
//   Playfair Display headlines, Inter body.
//
// Rebuild topology (reactive islands):
//   NowPlayingScreen    watches: currentTrackProvider (changes on skip only)
//   _ReactiveBackground watches: currentSpectralProvider (gradient color)
//   ReactiveArtwork     watches: currentArtworkUriProvider
//   _ReactiveProgress   watches: positionStreamProvider (high-frequency)
//   _ReactiveTransport  watches: playingStreamProvider, shuffle, loop
//
// High-frequency streams (position, FFT) are isolated to leaf widgets
// so they never trigger rebuilds of the artwork, gradient, or metadata.
//
// Layout: Full-bleed immersive Stack.
//   Stack(fit: StackFit.expand)
//   ├── _ReactiveBackground (spectral-derived color fill)
//   ├── Artwork (Positioned.fill, Hero)
//   ├── Gradient scrim (bottom 65%: transparent → surfaceCanvas)
//   ├── Vignette overlay (depth + edge darkening)
//   ├── _FrostedTopBar (top, minimal)
//   ├── _MetadataOverlay (bottom-left, over artwork)
//   ├── _ReactiveProgress (AudioVisualScrubber)
//   ├── _ReactiveTransport (play/pause/skip/shuffle/repeat)
//   └── More menu (vertical dots)
// ─────────────────────────────────────────────────────────────────────────────

class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> {
  final _expandedNotifier = ValueNotifier<bool>(false);
  final _lyricsExpandedNotifier = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _expandedNotifier.dispose();
    _lyricsExpandedNotifier.dispose();
    super.dispose();
  }

  /// Collapse queue, then expand lyrics (or toggle if already expanded).
  void _toggleLyrics() {
    if (_expandedNotifier.value) {
      _expandedNotifier.value = false;
    }
    _lyricsExpandedNotifier.value = !_lyricsExpandedNotifier.value;
  }

  @override
  Widget build(BuildContext context) {
    final track = ref.watch(currentTrackProvider);

    if (track == null) {
      return _EmptyState();
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      body: _ReactiveBackground(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Full-bleed artwork (swipe up to expand queue) ──
            Positioned.fill(
              child: GestureDetector(
                onVerticalDragEnd: (details) {
                  if ((details.primaryVelocity ?? 0) < -200) {
                    _expandedNotifier.value = true;
                  }
                },
                child: ReactiveArtwork(track: track),
              ),
            ),

            // ── Top bar ──
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: _FrostedTopBar(
                  track: track,
                  lyricsExpanded: _lyricsExpandedNotifier,
                  onToggleLyrics: _toggleLyrics,
                ),
              ),
            ),

            // ── Bottom content zone ──
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: _BottomContent(
                  track: track,
                  expandedNotifier: _expandedNotifier,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AfColors.surfaceCanvas,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronDown),
          onPressed: () => Navigator.maybePop(context),
        ),
      ),
      body: const EmptyState(
        icon: LucideIcons.music,
        title: 'Nothing playing yet',
        body: 'Start playing to see your music here',
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reactive islands
// ─────────────────────────────────────────────────────────────────────────────

/// Watches spectral for the background gradient only.
/// Rebuilds when artwork color changes — not on position ticks.
class _ReactiveBackground extends ConsumerWidget {
  const _ReactiveBackground({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spectral = ref.watch(currentSpectralProvider);
    final oklch = srgbToOklch(spectral.energy);
    final background = OklchColor(0.35, 0.12, oklch.h).toColor();
    final luminance = background.computeLuminance();
    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: luminance > 0.5
          ? Brightness.dark
          : Brightness.light,
      statusBarBrightness: luminance > 0.5 ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: luminance > 0.5
          ? Brightness.dark
          : Brightness.light,
      systemNavigationBarDividerColor: Colors.transparent,
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: AnimatedContainer(
        duration: AfDurations.expressive,
        curve: AfCurves.easeStandard,
        color: background,
        child: child,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Vignette overlay — radial gradient from transparent center to dark edges
// ─────────────────────────────────────────────────────────────────────────────



// ─────────────────────────────────────────────────────────────────────────────
// Frosted top bar — minimal, transparent backdrop
// ─────────────────────────────────────────────────────────────────────────────

class _FrostedTopBar extends ConsumerStatefulWidget {
  const _FrostedTopBar({
    required this.track,
    required this.lyricsExpanded,
    required this.onToggleLyrics,
  });
  final AfTrack track;
  final ValueNotifier<bool> lyricsExpanded;
  final VoidCallback onToggleLyrics;

  @override
  ConsumerState<_FrostedTopBar> createState() => _FrostedTopBarState();
}

class _FrostedTopBarState extends ConsumerState<_FrostedTopBar>
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
  void didUpdateWidget(covariant _FrostedTopBar oldWidget) {
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
    final isSynced = lrc != null && lrc.lines.any((l) => l.start > Duration.zero);
    final active = isSynced ? lrc.activeIndex(position) : -1;

    return AnimatedBuilder(
      animation: _expandAnim,
      builder: (context, _) {
        final isExpanded = _expandAnim.value > 0.5;
        final radius = isExpanded
            ? AfRadii.borderLg
            : AfRadii.borderPill;

        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AfSpacing.s16,
            vertical: isExpanded ? 0 : AfSpacing.s8,
          ),
          child: GestureDetector(
            onVerticalDragEnd: (details) {
              if ((details.primaryVelocity ?? 0) > 200 && widget.lyricsExpanded.value) {
                widget.onToggleLyrics();
              }
            },
            child: GlassCard(
              borderRadius: radius,
              blurSigma: 20,
              color: Colors.white.withValues(alpha: 0.08),
              borderColor: Colors.white.withValues(alpha: 0.1),
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
                          child: InkWell(
                            borderRadius: AfRadii.borderSm,
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
                            padding: const EdgeInsets.symmetric(vertical: 4),
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

// ─────────────────────────────────────────────────────────────────────────────
// Bottom content zone — metadata + controls + expandable queue
// ─────────────────────────────────────────────────────────────────────────────

/// Houses all bottom-aligned content: metadata, scrubber, transport controls,
/// and an expandable queue panel. Swipe up on non-scrubber area to reveal queue.
class _BottomContent extends ConsumerStatefulWidget {
  const _BottomContent({required this.track, required this.expandedNotifier});
  final AfTrack track;
  final ValueNotifier<bool> expandedNotifier;

  @override
  ConsumerState<_BottomContent> createState() => _BottomContentState();
}

class _BottomContentState extends ConsumerState<_BottomContent>
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
  void didUpdateWidget(covariant _BottomContent oldWidget) {
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
        // Interpolate max height: compact ~30% → expanded ~70% (below top bar)
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
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AfRadii.lg),
                topRight: Radius.circular(AfRadii.lg),
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
                        _MetadataOverlay(track: widget.track),
                        const SizedBox(height: AfSpacing.s12),
                        // ── Visualizer scrubber ──
                        _ReactiveProgress(track: widget.track),
                        const SizedBox(height: AfSpacing.s12),
                        // ── Transport controls ──
                        _ReactiveTransport(track: widget.track),
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
                        return ListTile(
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
                          onTap: () {
                            ref.read(playerServiceProvider).skipToQueueItem(
                              queue.indexOf(t),
                            );
                          },
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

// ─────────────────────────────────────────────────────────────────────────────
// Metadata overlay — title + artist, bottom-left over artwork
// ─────────────────────────────────────────────────────────────────────────────

class _MetadataOverlay extends ConsumerWidget {
  const _MetadataOverlay({required this.track});
  final AfTrack track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFav = ref.watch(isFavoriteProvider(track.id));
    return Row(
      children: [
        // Title + artist
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              MarqueeText(
                text: track.title,
                style: AfTypography.titleMedium,
              ),
              const SizedBox(height: AfSpacing.s4),
              InkWell(
                borderRadius: AfRadii.borderSm,
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
                        color: AfColors.textSecondary,
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
          IconButton(
            icon: Icon(
              isFav ? LucideIcons.heart : LucideIcons.heart,
              color: isFav ? AfColors.semanticError : AfColors.textSecondary,
              size: 22,
            ),
            tooltip: isFav ? 'Remove from favorites' : 'Add to favorites',
            onPressed: () async {
              try {
                await ref.read(favoriteToggleProvider)(track);
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Could not update favorite'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              }
            },
          ),
          // Quality badge
          if (track.quality != null)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AfSpacing.s8,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                color: AfColors.accentMuted.withValues(alpha: 0.2),
                borderRadius: AfRadii.borderPill,
              ),
              child: Text(
                track.quality!.chipLabel,
                style: AfTypography.caption.copyWith(
                  color: AfColors.textPrimary,
                ),
              ),
            ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Reactive progress — AudioVisualScrubber integration
// ─────────────────────────────────────────────────────────────────────────────

/// Watches positionStreamProvider — the only widget that does.
/// Rebuilds at position tick rate; everything above is unaffected.
///
/// Scrub architecture:
///   onScrub    → local preview only (no seek, no audio pipeline churn)
///   onScrubEnd → single committed seek
class _ReactiveProgress extends ConsumerStatefulWidget {
  const _ReactiveProgress({required this.track});
  final AfTrack track;

  @override
  ConsumerState<_ReactiveProgress> createState() => _ReactiveProgressState();
}

class _ReactiveProgressState extends ConsumerState<_ReactiveProgress> {
  double? _scrubPreview;
  bool _isDragging = false;

  @override
  void didUpdateWidget(covariant _ReactiveProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id) {
      _isDragging = false;
      _scrubPreview = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final position = ref.watch(positionStreamProvider);
    final spectral = ref.watch(currentSpectralProvider);
    final mpvDuration = ref.watch(durationStreamProvider);
    final isBuffering = ref.watch(isBufferingProvider);
    final duration = mpvDuration > Duration.zero
        ? mpvDuration
        : widget.track.duration;

    final effectivePosition = isBuffering ? Duration.zero : position;

    final engineProgress = duration.inMilliseconds == 0
        ? 0.0
        : (effectivePosition.inMilliseconds / duration.inMilliseconds).clamp(
            0.0,
            1.0,
          );
    final displayProgress = _isDragging
        ? (_scrubPreview ?? engineProgress)
        : engineProgress;

    final displayPosition = _isDragging && _scrubPreview != null
        ? Duration(
            milliseconds: (_scrubPreview! * duration.inMilliseconds).round(),
          )
        : effectivePosition;
    final remaining = duration > displayPosition
        ? duration - displayPosition
        : Duration.zero;

    return Column(
      children: [
        AudioVisualScrubber(
            progress: displayProgress,
            playedColor: spectral.energy,
            height: 100.0,
            onScrub: (p) => setState(() {
              _isDragging = true;
              _scrubPreview = p;
            }),
            onScrubEnd: (p) async {
              final newPos = Duration(
                milliseconds: (p * duration.inMilliseconds).round(),
              );
              final svc = ref.read(playerServiceProvider);
              final wasCompletedAtEnd = svc.isCompleted && svc.isUserPaused;
              try {
                await svc.seek(newPos).timeout(const Duration(seconds: 2));
                if (wasCompletedAtEnd && mounted) {
                  await svc.play().timeout(const Duration(seconds: 2));
                }
              } catch (_) {
                // Timeout or seek error — still release the drag lock.
              }
              if (mounted) {
                setState(() {
                  _isDragging = false;
                  _scrubPreview = null;
                });
              }
            },
          ),
          const SizedBox(height: AfSpacing.s4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  formatTrackDuration(displayPosition),
                  style: AfTypography.mono.copyWith(
                    color: AfColors.textSecondary,
                  ),
                ),
                Text(
                  formatRemaining(remaining),
                  style: AfTypography.mono.copyWith(
                    color: AfColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reactive transport — play/pause/skip/shuffle/repeat
// ─────────────────────────────────────────────────────────────────────────────

/// Watches playing/shuffle/loop — rebuilds on transport state changes only.
class _ReactiveTransport extends ConsumerWidget {
  const _ReactiveTransport({required this.track});
  final AfTrack track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPlaying = ref
        .watch(playingStreamProvider)
        .maybeWhen(data: (v) => v, orElse: () => false);
    final shuffleMode = ref
        .watch(shuffleModeProvider)
        .maybeWhen(data: (v) => v, orElse: () => ShuffleMode.off);
    final loopMode = ref
        .watch(loopModeProvider)
        .maybeWhen(data: (v) => v, orElse: () => AfLoopMode.off);
    final spectral = ref.watch(currentSpectralProvider);

    return _TransportRow(
      isPlaying: isPlaying,
      shuffleOn: shuffleMode != ShuffleMode.off,
      shuffleMode: shuffleMode,
      loopMode: loopMode,
      repeatCount: ref.watch(repeatCountProvider),
      accent: spectral.energy,
      onShuffle: () {
        final svc = ref.read(playerServiceProvider);
        unawaited(
          svc.setAfShuffleMode(!svc.isShuffleEnabled).catchError((_) {}),
        );
      },
      onShuffleLongPress: () => _showShuffleOptions(context, ref),
      onRepeat: () {
        final svc = ref.read(playerServiceProvider);
        final currentMode = ref
            .read(loopModeProvider)
            .maybeWhen(data: (v) => v, orElse: () => AfLoopMode.off);
        switch (currentMode) {
          case AfLoopMode.off:
            unawaited(svc.setAfLoopMode(Loop.playlist).catchError((_) {}));
            break;
          case AfLoopMode.playlist:
            unawaited(svc.setAfLoopMode(Loop.file).catchError((_) {}));
            break;
          case AfLoopMode.file:
            ref.read(forNtimesModeProvider.notifier).state = true;
            unawaited(svc.setAfForNtimes(true).catchError((_) {}));
            break;
          case AfLoopMode.forNtimes:
            ref.read(forNtimesModeProvider.notifier).state = false;
            svc.setLoopModeOffSync();
            unawaited(svc.setAfForNtimes(false).catchError((_) {}));
            break;
        }
      },
      onPlayPause: () {
        final svc = ref.read(playerServiceProvider);
        isPlaying ? svc.pause() : svc.play();
      },
      onPrev: () => ref.read(playerServiceProvider).skipToPrevious(),
      onNext: () => ref.read(playerServiceProvider).skipToNext(),
    );
  }

  void _showShuffleOptions(BuildContext context, WidgetRef ref) {
    showBlurDialog(
      context: context,
      builder: (context, dismiss) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Shuffle options', style: AfTypography.titleMedium),
          const SizedBox(height: AfSpacing.s16),
          ListTile(
            leading: const Icon(LucideIcons.shuffle),
            title: const Text('Shuffle all'),
            onTap: () {
              dismiss();
              ref.read(playerServiceProvider).setAfShuffleMode(true);
            },
          ),
          ListTile(
            leading: const Icon(LucideIcons.arrowDownWideNarrow),
            title: const Text('Shuffle next'),
            subtitle: const Text('Only upcoming tracks'),
            onTap: () {
              dismiss();
              ref.read(playerServiceProvider).setAfShuffleTail();
            },
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Transport row
// ─────────────────────────────────────────────────────────────────────────────

class _TransportRow extends StatelessWidget {
  const _TransportRow({
    required this.isPlaying,
    required this.shuffleOn,
    required this.shuffleMode,
    required this.loopMode,
    required this.repeatCount,
    required this.accent,
    required this.onPlayPause,
    required this.onPrev,
    required this.onNext,
    required this.onShuffle,
    required this.onShuffleLongPress,
    required this.onRepeat,
  });
  final bool isPlaying;
  final bool shuffleOn;
  final ShuffleMode shuffleMode;
  final AfLoopMode loopMode;
  final int repeatCount;
  final Color accent;
  final VoidCallback onPlayPause;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onShuffle;
  final VoidCallback onShuffleLongPress;
  final VoidCallback onRepeat;

  static IconData _loopIcon(AfLoopMode mode) {
    return switch (mode) {
      AfLoopMode.file => LucideIcons.repeat1,
      AfLoopMode.playlist => LucideIcons.repeat,
      AfLoopMode.off => LucideIcons.repeat,
      AfLoopMode.forNtimes => LucideIcons.repeat,
    };
  }

  static Color _loopColor(AfLoopMode mode, Color accent) {
    return mode == AfLoopMode.off ? AfColors.textTertiary : accent;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Shuffle
          GestureDetector(
            onLongPress: onShuffleLongPress,
            child: _TransportButton(
              icon: Icon(
                shuffleMode == ShuffleMode.tail
                    ? LucideIcons.arrowDownWideNarrow
                    : LucideIcons.shuffle,
                size: 20,
                color: shuffleOn ? accent : AfColors.textTertiary,
              ),
              onTap: onShuffle,
            ),
          ),
          const SizedBox(width: AfSpacing.s12),
          // Previous
          _TransportButton(
            icon: const Icon(
              LucideIcons.skipBack,
              size: 26,
              color: AfColors.textPrimary,
            ),
            onTap: onPrev,
          ),
          const SizedBox(width: AfSpacing.s16),
          // Play / Pause — spectral glow
          _PlayButton(isPlaying: isPlaying, accent: accent, onTap: onPlayPause),
          const SizedBox(width: AfSpacing.s16),
          // Next
          _TransportButton(
            icon: const Icon(
              LucideIcons.skipForward,
              size: 26,
              color: AfColors.textPrimary,
            ),
            onTap: onNext,
          ),
          const SizedBox(width: AfSpacing.s12),
          // Repeat
          _TransportButton(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  _loopIcon(loopMode),
                  size: 20,
                  color: _loopColor(loopMode, accent),
                ),
                if (loopMode == AfLoopMode.forNtimes)
                  Positioned(
                    right: -6,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: AfColors.indigo400,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$repeatCount',
                        style: AfTypography.caption.copyWith(
                          color: AfColors.textOnPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            onTap: onRepeat,
          ),
        ],
      );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared transport widgets
// ─────────────────────────────────────────────────────────────────────────────

class _TransportButton extends StatelessWidget {
  const _TransportButton({required this.icon, required this.onTap});
  final Widget icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: SizedBox(
        width: AfSpacing.minHitTarget,
        height: AfSpacing.minHitTarget,
        child: Center(child: icon),
      ),
    );
  }
}

/// Play/pause button with spectral ambient glow.
/// 60dp circle with [accent] background and a pulsing outer glow shadow
/// driven by the spectral energy color.
class _PlayButton extends ConsumerWidget {
  const _PlayButton({
    required this.isPlaying,
    required this.accent,
    required this.onTap,
  });
  final bool isPlaying;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isBuffering = ref.watch(isBufferingProvider);
    return PressScale(
      ensureHitTarget: false,
      onTap: onTap,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: accent,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.40),
              blurRadius: 24,
              spreadRadius: 2,
            ),
            BoxShadow(
              color: accent.withValues(alpha: 0.15),
              blurRadius: 48,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Center(
          child: isBuffering
              ? SizedBox(
                  width: AfSpacing.s24,
                  height: AfSpacing.s24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: _contrastColor(accent),
                  ),
                )
              : Icon(
                  isPlaying ? LucideIcons.pause : LucideIcons.play,
                  color: _contrastColor(accent),
                  size: 28,
                ),
        ),
      ),
    );
  }

  /// Returns black or white depending on the accent color luminance
  /// for maximum contrast on the spectral background.
  static Color _contrastColor(Color accent) {
    return accent.computeLuminance() > 0.45
        ? AfColors.surfaceCanvas
        : AfColors.textOnPrimary;
  }
}
