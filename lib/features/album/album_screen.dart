import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/audio/play_actions.dart';
import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/lastfm_metadata_providers.dart';
import '../../state/providers.dart';
import '../../utils/display_error.dart';
import '../../utils/log.dart';
import '../../widgets/album_more_sheet.dart';
import '../../widgets/artwork.dart';
import '../../widgets/async_error_view.dart';
import '../../widgets/press_scale.dart';
import '../../widgets/track_context_menu.dart';
import '../../widgets/opacity_app_bar.dart';
import '../../widgets/track_row.dart';
import '../../widgets/af_scrollbar.dart';
import '../../widgets/skeletons/album_skeleton.dart';
import '../../widgets/stagger_reveal.dart';

/// Mockup 07 — Album detail.
///
///   Full-bleed 1:1 hero artwork at the top with a bottom fade ShaderMask
///   to surface.canvas. Parallax: artwork translates up at 0.5× scroll
///   speed (ScrollController-driven, not AnimationController-driven).
///   Below: title, artist, metadata line, action row, track list.
class AlbumScreen extends ConsumerStatefulWidget {
  const AlbumScreen({super.key, required this.albumId});
  final String albumId;

  @override
  ConsumerState<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends ConsumerState<AlbumScreen> {
  final _scroll = ScrollController();
  late final ValueNotifier<double> _scrollOffset = ValueNotifier(0.0);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(
      () => _scrollOffset.value = _scroll.hasClients ? _scroll.offset : 0.0,
    );
  }

  @override
  void dispose() {
    _scrollOffset.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(albumDetailProvider(widget.albumId));
    final activeTrack = ref.watch(currentTrackProvider);
    final activeId = activeTrack?.id;
    final spectral = ref.watch(
      currentSpectralProvider.select((s) => s.primary),
    );

    final detail = detailAsync.valueOrNull;
    final wikiAsync = detail != null
        ? ref.watch(
            albumWikiProvider((
              artistName: detail.album.artistName,
              albumName: detail.album.name,
            )),
          )
        : const AsyncValue<
            ({String? wiki, String? listeners, String? playCount})?
          >.loading();

    return Scaffold(
      backgroundColor: AfColors.surfaceCanvas,
      body: detailAsync.when(
        loading: () => const AlbumSkeleton(),
        error: (e, _) => AsyncErrorView(
          label: 'Could not load album',
          error: e,
          onRetry: () => ref.invalidate(albumDetailProvider(widget.albumId)),
        ),
        data: (detail) {
          if (detail == null) {
            return const Center(child: Text('Album not found'));
          }
          final album = detail.album;
          final tracks = detail.tracks;
          final width = MediaQuery.of(context).size.width;
          final heroHeight = width; // 1:1

          return Stack(
            children: [
              // Hero artwork — parallax via Transform.translate + scale, scroll-linked.
              // Uses ValueListenableBuilder so only the artwork + app bar
              // rebuild on scroll, not the entire screen.
              ValueListenableBuilder<double>(
                valueListenable: _scrollOffset,
                builder: (context, offset, _) {
                  // Subtle scale: 1.0 at top → 0.92 as user scrolls past hero.
                  final scaleProgress = (offset / heroHeight).clamp(0.0, 1.0);
                  final scale = 1.0 - (scaleProgress * 0.08);

                  return Positioned(
                    top: -offset * 0.5,
                    left: 0,
                    right: 0,
                    child: SizedBox(
                      height: heroHeight,
                      child: Transform.scale(
                        scale: scale,
                        child: ShaderMask(
                          shaderCallback: (rect) {
                            return const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              stops: [0.6, 1.0],
                              colors: [Colors.white, Colors.transparent],
                            ).createShader(rect);
                          },
                          blendMode: BlendMode.dstIn,
                          child: Artwork(
                            url: album.imageUrl,
                            size: width,
                            height: heroHeight,
                            radius: BorderRadius.zero,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),

              AfScrollbar(
                child: CustomScrollView(
                  controller: _scroll,
                  physics: const ClampingScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(child: SizedBox(height: heroHeight)),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AfSpacing.gutterGenerous,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              album.name,
                              style: AfTypography.display.copyWith(
                                color: AfColors.textPrimary,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: AfSpacing.s4),
                            GestureDetector(
                              onTap: album.artistId != null
                                  ? () => context.push(
                                      '/artist/${album.artistId}',
                                    )
                                  : null,
                              child: Text(
                                album.artistName,
                                style: AfTypography.titleMedium.copyWith(
                                  color: spectral,
                                ),
                              ),
                            ),
                            const SizedBox(height: AfSpacing.s4),
                            Text(
                              album.metadataLine,
                              style: AfTypography.bodySmall.copyWith(
                                color: AfColors.textTertiary,
                              ),
                            ),
                            const SizedBox(height: AfSpacing.s16),
                            _ActionRow(
                              album: album,
                              tracks: tracks,
                              onPlay: () => ref
                                  .read(playActionsProvider)
                                  .playAlbum(tracks),
                              onMore: () => showAlbumMoreSheet(
                                context,
                                ref,
                                album,
                                tracks,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(
                      child: SizedBox(height: AfSpacing.s24),
                    ),
                    SliverToBoxAdapter(
                      child: StaggerReveal(
                        children: [
                          for (var i = 0; i < tracks.length; i++) ...[
                            if (i > 0) const SizedBox(height: AfSpacing.s4),
                            _TrackRowItem(
                              track: tracks[i],
                              index: i,
                              activeId: activeId,
                              tracks: tracks,
                            ),
                          ],
                        ],
                      ),
                    ),
                    wikiAsync.maybeWhen(
                      data: (wiki) {
                        if (wiki == null ||
                            wiki.wiki == null ||
                            wiki.wiki!.isEmpty) {
                          return const SliverToBoxAdapter(child: SizedBox());
                        }
                        return SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AfSpacing.gutterGenerous,
                              vertical: AfSpacing.s24,
                            ),
                            child: _AlbumWikiPanel(
                              wiki: wiki.wiki!,
                              listeners: wiki.listeners,
                              playCount: wiki.playCount,
                            ),
                          ),
                        );
                      },
                      orElse: () => const SliverToBoxAdapter(child: SizedBox()),
                    ),
                    const SliverToBoxAdapter(
                      child: SizedBox(
                        height: AfSpacing.bottomInsetWithMiniAndNav,
                      ),
                    ),
                  ],
                ),
              ),

              // App bar — rendered on top of scroll content.
              ValueListenableBuilder<double>(
                valueListenable: _scrollOffset,
                builder: (context, offset, _) => Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: OpacityAppBar(
                    scrollOffset: offset,
                    threshold: heroHeight - kToolbarHeight,
                    title: album.name,
                    onBack: () => context.pop(),
                    onMore: () =>
                        showAlbumMoreSheet(context, ref, album, tracks),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ActionRow extends ConsumerStatefulWidget {
  const _ActionRow({
    required this.onPlay,
    required this.onMore,
    required this.album,
    required this.tracks,
  });
  final VoidCallback onPlay;
  final VoidCallback onMore;
  final AfAlbum album;
  final List<AfTrack> tracks;

  @override
  ConsumerState<_ActionRow> createState() => _ActionRowState();
}

class _ActionRowState extends ConsumerState<_ActionRow> {
  late bool _isFavorite;
  bool _favoriteBusy = false;

  @override
  void initState() {
    super.initState();
    // Seed from the album's server-provided favorite state so the heart
    // reflects reality on first render instead of always showing empty.
    _isFavorite = widget.album.isFavorite;
  }

  @override
  void didUpdateWidget(covariant _ActionRow old) {
    super.didUpdateWidget(old);
    // If the parent re-fetches the album (e.g. after a favorite toggle
    // invalidates the provider), keep the local state in sync — but only
    // when we're not mid-toggle to avoid clobbering an in-flight optimistic
    // update.
    if (!_favoriteBusy && old.album.isFavorite != widget.album.isFavorite) {
      _isFavorite = widget.album.isFavorite;
    }
  }

  Future<void> _toggleFavorite() async {
    if (_favoriteBusy) return;
    final backend = ref.read(musicBackendProvider);
    if (backend == null) return;
    setState(() {
      _favoriteBusy = true;
      _isFavorite = !_isFavorite;
    });
    try {
      await backend.setFavorite(widget.album.id, _isFavorite);
      afLog(
        'data',
        'albumFavorite source=live '
            'id=${widget.album.id} isFavorite=$_isFavorite',
      );
      // Force the Home screen's "Favorite albums" row to re-fetch so it
      // reflects the toggle on the next frame instead of waiting for the
      // user to pull-to-refresh.
      ref.invalidate(favoriteAlbumsProvider);
      // Also invalidate the album detail so didUpdateWidget gets the
      // fresh isFavorite value if the user navigates away and back.
      ref.invalidate(albumDetailProvider(widget.album.id));
    } on Exception catch (e) {
      // Revert the optimistic flip on failure.
      setState(() => _isFavorite = !_isFavorite);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(displayError(e, prefix: 'Could not update favorite')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _favoriteBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Action icons row ──────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _IconCircle(
              icon: LucideIcons.heart,
              color: _isFavorite ? AfColors.semanticError : null,
              onTap: _toggleFavorite,
            ),
            const SizedBox(width: AfSpacing.s8),
            _IconCircle(
              icon: LucideIcons.download,
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Offline downloads coming soon'),
                  duration: AfDurations.snackBarInfo,
                ),
              ),
            ),
            const SizedBox(width: AfSpacing.s8),
            _IconCircle(icon: LucideIcons.ellipsis, onTap: widget.onMore),
          ],
        ),
        const SizedBox(height: AfSpacing.s12),
        // ── Play All + Shuffle ────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: widget.onPlay,
                icon: const Icon(
                  LucideIcons.play,
                  color: AfColors.textOnPrimary,
                  size: 22,
                ),
                label: const Text('Play All'),
              ),
            ),
            const SizedBox(width: AfSpacing.s12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  final shuffled = List<AfTrack>.from(widget.tracks)..shuffle();
                  ref.read(playActionsProvider).playQueue(shuffled);
                },
                style: AfTypography.outlinedAction,
                icon: const Icon(LucideIcons.shuffle, size: 20),
                label: const Text('Shuffle'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _IconCircle extends StatelessWidget {
  const _IconCircle({required this.icon, required this.onTap, this.color});
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      ensureHitTarget: false,
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: AfColors.surfaceRaised,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 22, color: color ?? AfColors.textPrimary),
      ),
    );
  }
}

/// Track row wrapper that watches playback state providers internally.
/// Prevents the entire AlbumScreen root from rebuilding on every
/// buffering/spectral change — only this leaf widget rebuilds.
class _TrackRowItem extends ConsumerWidget {
  const _TrackRowItem({
    required this.track,
    required this.index,
    required this.activeId,
    required this.tracks,
  });

  final AfTrack track;
  final int index;
  final String? activeId;
  final List<AfTrack> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isBuffering = ref.watch(isBufferingProvider);
    final activeAccent = ref.watch(
      currentSpectralProvider.select((s) => s.energy),
    );
    final isActive = track.id == activeId;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
      child: TrackRow(
        track: track,
        leadingNumber: index + 1,
        isActive: isActive,
        isBuffering: isActive && isBuffering,
        activeAccent: activeAccent,
        onTap: () =>
            ref.read(playActionsProvider).playQueue(tracks, startIndex: index),
        onLongPress: () => showTrackContextMenu(context, ref, track),
      ),
    );
  }
}

class _AlbumWikiPanel extends ConsumerStatefulWidget {
  const _AlbumWikiPanel({required this.wiki, this.listeners, this.playCount});
  final String wiki;
  final String? listeners;
  final String? playCount;

  @override
  ConsumerState<_AlbumWikiPanel> createState() => _AlbumWikiPanelState();
}

class _AlbumWikiPanelState extends ConsumerState<_AlbumWikiPanel> {
  bool _expanded = false;

  String _cleanHtml(String html) {
    return html.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }

  String _formatNumber(String? numStr) {
    if (numStr == null) return '';
    final n = int.tryParse(numStr);
    if (n == null) return numStr;
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    final cleanText = _cleanHtml(widget.wiki);
    if (cleanText.isEmpty) return const SizedBox();

    final spectral = ref.watch(
      currentSpectralProvider.select((s) => s.primary),
    );
    final stats = <String>[];
    if (widget.listeners != null) {
      stats.add('${_formatNumber(widget.listeners)} listeners');
    }
    if (widget.playCount != null) {
      stats.add('${_formatNumber(widget.playCount)} plays');
    }

    return Container(
      padding: const EdgeInsets.all(AfSpacing.s16),
      decoration: const BoxDecoration(
        color: AfColors.surfaceBase,
        borderRadius: AfRadii.borderMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('About this Album', style: AfTypography.titleSmall),
          if (stats.isNotEmpty) ...[
            const SizedBox(height: AfSpacing.s4),
            Text(
              stats.join(' · '),
              style: AfTypography.bodySmall.copyWith(
                color: AfColors.textTertiary,
              ),
            ),
          ],
          const SizedBox(height: AfSpacing.s12),
          Text(
            cleanText,
            maxLines: _expanded ? null : 4,
            overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            style: AfTypography.bodySmall.copyWith(
              color: AfColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AfSpacing.s8),
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Text(
              _expanded ? 'Show less' : 'Read more',
              style: AfTypography.bodySmall.copyWith(
                color: spectral,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
