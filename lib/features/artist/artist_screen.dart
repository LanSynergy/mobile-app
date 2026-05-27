import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/audio/play_actions.dart';
import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/artwork.dart';
import '../../widgets/async_error_view.dart';
import '../../widgets/section_header.dart';
import '../../widgets/tile.dart';
import '../../widgets/track_context_menu.dart';
import '../../widgets/track_row.dart';
import '../../widgets/skeletons/artist_skeleton.dart';

/// Mockup 08 — Artist detail.
class ArtistScreen extends ConsumerWidget {
  const ArtistScreen({super.key, required this.artistId});
  final String artistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artistAsync = ref.watch(artistDetailProvider(artistId));
    return Scaffold(
      body: artistAsync.when(
        loading: () => const ArtistSkeleton(),
        error: (e, _) => AsyncErrorView(
          label: 'Could not load artist',
          error: e,
          onRetry: () => ref.invalidate(artistDetailProvider(artistId)),
        ),
        data: (artist) {
          if (artist == null) return const Center(child: Text('Not found'));
          final albumsAsync = ref.watch(artistAlbumsProvider(artistId));
          final topTracksAsync = ref.watch(artistTopTracksProvider(artistId));
          final albums = albumsAsync.maybeWhen(
            data: (a) => a,
            orElse: () => const <AfAlbum>[],
          );
          final topTracks = topTracksAsync.maybeWhen(
            data: (t) => t,
            orElse: () => const <AfTrack>[],
          );
          return CustomScrollView(
            physics: const ClampingScrollPhysics(),
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: 280,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => context.pop(),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  collapseMode: CollapseMode.parallax,
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      Artwork(
                        url: artist.imageUrl,
                        size: double.infinity,
                        height: double.infinity,
                        radius: BorderRadius.zero,
                      ),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                // ignore: deprecated_member_use
                                AfColors.surfaceCanvas.withValues(alpha: 0.6),
                                AfColors.surfaceCanvas.withValues(alpha: 0.9),
                              ],
                              stops: const [0.3, 0.8, 1.0],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: AfSpacing.gutterGenerous,
                        right: AfSpacing.gutterGenerous,
                        bottom: AfSpacing.s16,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(artist.name, style: AfTypography.display),
                            const SizedBox(height: 2),
                            Text(
                              artist.statLine,
                              style: AfTypography.bodySmall.copyWith(
                                color: AfColors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AfSpacing.gutterGenerous,
                    AfSpacing.s16,
                    AfSpacing.gutterGenerous,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (artist.bio != null) ...[
                        Text(
                          artist.bio!,
                          style: AfTypography.bodyMedium.copyWith(
                            color: AfColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: AfSpacing.s24),
                      ],
                      const SectionHeader(title: 'Top songs', uppercase: true),
                      const SizedBox(height: AfSpacing.s12),
                    ],
                  ),
                ),
              ),
              if (topTracks.isNotEmpty)
                SliverList.separated(
                  itemCount: topTracks.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 4),
                  itemBuilder: (context, i) {
                    final t = topTracks[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AfSpacing.gutterGenerous,
                      ),
                      child: TrackRow(
                        track: t,
                        onTap: () => ref
                            .read(playActionsProvider)
                            .playQueue(topTracks, startIndex: i),
                        onLongPress: () =>
                            showTrackContextMenu(context, ref, t),
                      ),
                    );
                  },
                ),
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: AfSpacing.gutterGenerous,
                  ),
                  child: SectionHeader(title: 'Albums', uppercase: true),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: AfSpacing.s12)),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 200,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AfSpacing.gutterGenerous,
                    ),
                    itemCount: albums.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: AfSpacing.s12),
                    itemBuilder: (context, i) {
                      final a = albums[i];
                      return Tile(
                        title: a.name,
                        subtitle: '${a.year ?? ''}',
                        variant: TileVariant.album,
                        imageUrl: a.imageUrl,
                        size: 152,
                        onTap: () => context.push('/album/${a.id}'),
                        onLongPress: () =>
                            showAlbumContextMenu(context, ref, a),
                      );
                    },
                  ),
                ),
              ),
              const SliverToBoxAdapter(
                child: SizedBox(height: AfSpacing.bottomInsetWithMiniAndNav),
              ),
            ],
          );
        },
      ),
    );
  }
}
