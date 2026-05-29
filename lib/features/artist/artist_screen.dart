import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/audio/play_actions.dart';
import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/artwork.dart';
import '../../widgets/async_error_view.dart';
import '../../widgets/press_scale.dart';
import '../../widgets/section_header.dart';
import '../../widgets/tile.dart';
import '../../widgets/track_context_menu.dart';
import '../../widgets/track_row.dart';
import '../../widgets/skeletons/artist_skeleton.dart';

class ArtistScreen extends ConsumerStatefulWidget {
  const ArtistScreen({super.key, required this.artistId});
  final String artistId;

  @override
  ConsumerState<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends ConsumerState<ArtistScreen> {
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
    final artistAsync = ref.watch(artistDetailProvider(widget.artistId));
    final albumsAsync = ref.watch(artistAlbumsProvider(widget.artistId));
    final topTracksAsync = ref.watch(artistTopTracksProvider(widget.artistId));
    final activeId = ref.watch(currentTrackProvider)?.id;
    final isBuffering = ref.watch(isBufferingProvider);
    final activeAccent = ref.watch(currentSpectralProvider).energy;

    return Scaffold(
      backgroundColor: AfColors.surfaceCanvas,
      body: artistAsync.when(
        loading: () => const ArtistSkeleton(),
        error: (e, _) => AsyncErrorView(
          label: 'Could not load artist',
          error: e,
          onRetry: () => ref.invalidate(artistDetailProvider(widget.artistId)),
        ),
        data: (artist) {
          if (artist == null) {
            return const Center(child: Text('Artist not found'));
          }

          final topTracks = topTracksAsync.valueOrNull ?? [];
          final albums = albumsAsync.valueOrNull ?? [];
          final width = MediaQuery.of(context).size.width;

          return Stack(
            children: [
              ValueListenableBuilder<double>(
                valueListenable: _scrollOffset,
                builder: (context, offset, _) => Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _OpacityAppBar(
                    scrollOffset: offset,
                    threshold: 240,
                    title: artist.name,
                    onBack: () => context.pop(),
                  ),
                ),
              ),

              CustomScrollView(
                controller: _scroll,
                physics: const ClampingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.only(
                        top:
                            MediaQuery.of(context).padding.top +
                            kToolbarHeight +
                            AfSpacing.s16,
                        left: AfSpacing.gutterGenerous,
                        right: AfSpacing.gutterGenerous,
                      ),
                      child: Column(
                        children: [
                          Center(
                            child: CircularArtwork(
                              url: artist.imageUrl,
                              size: width * 0.35,
                            ),
                          ),
                          const SizedBox(height: AfSpacing.s16),
                          Text(
                            artist.name,
                            style: AfTypography.display.copyWith(
                              color: AfColors.textPrimary,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (artist.bio != null && artist.bio!.isNotEmpty) ...[
                            const SizedBox(height: AfSpacing.s8),
                            Text(
                              artist.bio!,
                              style: AfTypography.bodyMedium.copyWith(
                                color: AfColors.textSecondary,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          const SizedBox(height: AfSpacing.s4),
                          Text(
                            artist.statLine,
                            style: AfTypography.bodySmall.copyWith(
                              color: AfColors.textTertiary,
                            ),
                          ),
                          const SizedBox(height: AfSpacing.s20),
                          _ActionRow(
                            onPlay: topTracks.isNotEmpty
                                ? () => ref
                                      .read(playActionsProvider)
                                      .playQueue(topTracks, startIndex: 0)
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (topTracks.isNotEmpty) ...[
                    const SliverToBoxAdapter(
                      child: SizedBox(height: AfSpacing.s32),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AfSpacing.gutterGenerous,
                        ),
                        child: SectionHeader(title: 'Top Songs'),
                      ),
                    ),
                    const SliverToBoxAdapter(
                      child: SizedBox(height: AfSpacing.s8),
                    ),
                    SliverList.separated(
                      itemCount: topTracks.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: AfSpacing.s4),
                      itemBuilder: (context, i) => Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AfSpacing.s16,
                        ),
                        child: TrackRow(
                          track: topTracks[i],
                          leadingNumber: i + 1,
                          isActive: topTracks[i].id == activeId,
                          isBuffering:
                              topTracks[i].id == activeId && isBuffering,
                          activeAccent: activeAccent,
                          onTap: () => ref
                              .read(playActionsProvider)
                              .playQueue(topTracks, startIndex: i),
                          onLongPress: () =>
                              showTrackContextMenu(context, ref, topTracks[i]),
                        ),
                      ),
                    ),
                  ],
                  if (albums.isNotEmpty) ...[
                    const SliverToBoxAdapter(
                      child: SizedBox(height: AfSpacing.s32),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AfSpacing.gutterGenerous,
                        ),
                        child: SectionHeader(title: 'Albums'),
                      ),
                    ),
                    const SliverToBoxAdapter(
                      child: SizedBox(height: AfSpacing.s12),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AfSpacing.s16,
                      ),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisExtent: 220,
                              crossAxisSpacing: AfSpacing.s16,
                              mainAxisSpacing: AfSpacing.s16,
                            ),
                        delegate: SliverChildBuilderDelegate((context, i) {
                          final a = albums[i];
                          return Tile(
                            title: a.name,
                            subtitle: a.metadataLine,
                            variant: TileVariant.album,
                            imageUrl: a.imageUrl,
                            size: double.infinity,
                            onTap: () => context.push('/album/${a.id}'),
                          );
                        }, childCount: albums.length),
                      ),
                    ),
                  ],
                  const SliverToBoxAdapter(
                    child: SizedBox(
                      height: AfSpacing.bottomInsetWithMiniAndNav,
                    ),
                  ),
                ],
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
  });
  final double scrollOffset;
  final double threshold;
  final String title;
  final VoidCallback onBack;

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
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top,
                ),
                child: SizedBox(
                  height: kToolbarHeight,
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(
                          LucideIcons.arrowLeft,
                          color: AfColors.textPrimary,
                          size: 24,
                        ),
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
                      const SizedBox(width: 48),
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
                    icon: const Icon(
                      LucideIcons.arrowLeft,
                      color: AfColors.textPrimary,
                      size: 24,
                    ),
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
                  const SizedBox(width: 48),
                ],
              ),
            ),
          );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.onPlay});
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: onPlay,
            icon: const Icon(
              LucideIcons.play,
              color: AfColors.textOnPrimary,
              size: 22,
            ),
            label: const Text('Play'),
          ),
        ),
      ],
    );
  }
}
