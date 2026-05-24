import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../core/audio/play_actions.dart';
import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../utils/display_error.dart';
import '../../utils/log.dart';
import '../../widgets/album_more_sheet.dart';
import '../../widgets/artwork.dart';
import '../../widgets/async_error_view.dart';
import '../../widgets/press_scale.dart';
import '../../widgets/track_context_menu.dart';
import '../../widgets/track_row.dart';
import '../../widgets/skeletons/album_skeleton.dart';

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
    _scroll.addListener(() => _scrollOffset.value =
        _scroll.hasClients ? _scroll.offset : 0.0);
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
              // Hero artwork — parallax via Transform.translate, scroll-linked.
              // Uses ValueListenableBuilder so only the artwork + app bar
              // rebuild on scroll, not the entire screen.
              ValueListenableBuilder<double>(
                valueListenable: _scrollOffset,
                builder: (context, offset, _) => Positioned(
                  top: -offset * 0.5,
                  left: 0,
                  right: 0,
                  child: SizedBox(
                    height: heroHeight,
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
              ),

              CustomScrollView(
                controller: _scroll,
                physics: const ClampingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: SizedBox(height: heroHeight)),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AfSpacing.gutterGenerous),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            album.name,
                            style: AfTypography.display.copyWith(
                              color: AfColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: AfSpacing.s4),
                          GestureDetector(
                            onTap: album.artistId != null
                                ? () => context.push(
                                    '/artist/${album.artistId}')
                                : null,
                            child: Text(
                              album.artistName,
                              style: AfTypography.titleMedium.copyWith(
                                color: AfColors.indigo300,
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
                            onPlay: () => ref
                                .read(playActionsProvider)
                                .playAlbum(tracks),
                            onMore: () => showAlbumMoreSheet(
                                context, ref, album, tracks),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(
                      child: SizedBox(height: AfSpacing.s24)),
                  SliverList.separated(
                    itemCount: tracks.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: AfSpacing.s4),
                    itemBuilder: (context, i) => Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AfSpacing.s16),
                      child: TrackRow(
                        track: tracks[i],
                        leadingNumber: i + 1,
                        onTap: () => ref
                            .read(playActionsProvider)
                            .playQueue(tracks, startIndex: i),
                        onLongPress: () =>
                            showTrackContextMenu(context, ref, tracks[i]),
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: SizedBox(
                        height: AfSpacing.bottomInsetWithMiniAndNav),
                  ),
                ],
              ),

              // App bar — rendered on top of scroll content.
              ValueListenableBuilder<double>(
                valueListenable: _scrollOffset,
                builder: (context, offset, _) => Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _OpacityAppBar(
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

class _OpacityAppBar extends StatelessWidget {

  const _OpacityAppBar({
    required this.scrollOffset,
    required this.threshold,
    required this.title,
    required this.onBack,
    required this.onMore,
  });
  final double scrollOffset;
  final double threshold;
  final String title;
  final VoidCallback onBack;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final t = (scrollOffset / threshold).clamp(0.0, 1.0);
    final bg = Color.lerp(
      Colors.transparent,
      AfColors.surfaceCanvas.withValues(alpha: 0.75),
      t,
    )!;
    return t > 0.01
        ? ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                color: bg,
                padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
                child: SizedBox(
                  height: kToolbarHeight,
                  child: Row(
                    children: [
                      IconButton(
                        icon: const FaIcon(FontAwesomeIcons.arrowLeft, color: AfColors.textPrimary, size: 24),
                        onPressed: onBack,
                      ),
                      Expanded(
                        child: Opacity(
                          opacity: t,
                          child: Text(
                            title,
                            textAlign: TextAlign.center,
                            style: AfTypography.titleSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const FaIcon(FontAwesomeIcons.ellipsis, color: AfColors.textPrimary, size: 24),
                        onPressed: onMore,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
        : Container(
            color: bg,
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
            child: SizedBox(
              height: kToolbarHeight,
              child: Row(
                children: [
                  IconButton(
                    icon: const FaIcon(FontAwesomeIcons.arrowLeft, color: AfColors.textPrimary, size: 24),
                    onPressed: onBack,
                  ),
                  Expanded(
                    child: Opacity(
                      opacity: t,
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: AfTypography.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const FaIcon(FontAwesomeIcons.ellipsis, color: AfColors.textPrimary, size: 24),
                    onPressed: onMore,
                  ),
                ],
              ),
            ),
          );
  }
}

class _ActionRow extends ConsumerStatefulWidget {
  const _ActionRow({
    required this.onPlay,
    required this.onMore,
    required this.album,
  });
  final VoidCallback onPlay;
  final VoidCallback onMore;
  final AfAlbum album;

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
    } catch (e) {
      // Revert the optimistic flip on failure.
      setState(() => _isFavorite = !_isFavorite);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(displayError(e, prefix: 'Could not update favorite'))),
        );
      }
    } finally {
      if (mounted) setState(() => _favoriteBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: widget.onPlay,
            icon: const FaIcon(FontAwesomeIcons.play, color: AfColors.textOnPrimary, size: 22),
            label: const Text('Play'),
          ),
        ),
        const SizedBox(width: AfSpacing.s12),
        _IconCircle(
          icon: FontAwesomeIcons.heart,
          color: _isFavorite ? AfColors.semanticError : null,
          onTap: _toggleFavorite,
        ),
        const SizedBox(width: AfSpacing.s8),
        _IconCircle(
          icon: FontAwesomeIcons.download,
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Offline downloads coming soon'),
              duration: Duration(seconds: 2),
            ),
          ),
        ),
        const SizedBox(width: AfSpacing.s8),
        _IconCircle(
          icon: FontAwesomeIcons.ellipsis,
          onTap: widget.onMore,
        ),
      ],
    );
  }
}

class _IconCircle extends StatelessWidget {
  const _IconCircle({required this.icon, required this.onTap, this.color});
  final FaIconData icon;
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
          color: AfColors.surfaceBase,
          shape: BoxShape.circle,
        ),
        child: FaIcon(icon, size: 22, color: color ?? AfColors.textPrimary),
      ),
    );
  }
}
