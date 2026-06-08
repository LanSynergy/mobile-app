import 'dart:ui' show ImageFilter;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:go_router/go_router.dart';

import '../../../core/audio/play_actions.dart';
import '../../../core/jellyfin/models/items.dart';
import '../../../core/youtube/innertube_client.dart';
import '../../../design_tokens/tokens.dart';
import '../../../state/youtube_music_providers.dart';
import '../../../widgets/artwork.dart';
import '../../../widgets/press_scale.dart';
import '../../../widgets/track_context_menu.dart';

/// Full YouTube Music home view — header, chips, dynamic sections.
///
/// Composed as a standalone widget so [HomeScreen] stays compact.
class YouTubeHomeView extends ConsumerWidget {
  const YouTubeHomeView({super.key, required this.scrollController});
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final homeAsync = ref.watch(youtubeHomeProvider);
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(youtubeHomeProvider);
          await ref.read(youtubeHomeProvider.future);
        },
        color: AfColors.indigo300,
        backgroundColor: AfColors.surfaceBase,
        child: CustomScrollView(
          controller: scrollController,
          physics: const AlwaysScrollableScrollPhysics(
            parent: ClampingScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AfSpacing.s16,
                  AfSpacing.s8,
                  AfSpacing.s16,
                  AfSpacing.s16,
                ),
                child: Row(
                  children: [
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [Color(0xFFFF0000), Color(0xFFFF4444)],
                      ).createShader(bounds),
                      child: Text(
                        'YouTube Music',
                        style: AfTypography.display.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const Spacer(),
                    GlassSearchButton(onTap: () => context.push('/search')),
                  ],
                ),
              ),
            ),

            // Chips Row
            homeAsync.when(
              data: (home) {
                if (home.chips.isEmpty) {
                  return const SliverToBoxAdapter(child: SizedBox.shrink());
                }
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AfSpacing.s16),
                    child: YouTubeChipsRow(chips: home.chips),
                  ),
                );
              },
              loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
              error: (_, _) =>
                  const SliverToBoxAdapter(child: SizedBox.shrink()),
            ),

            // Dynamic Home Sections
            homeAsync.when(
              data: (home) {
                if (home.sections.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(AfSpacing.s16),
                      child: Text(
                        'No sections found',
                        style: AfTypography.bodyMedium.copyWith(
                          color: AfColors.textTertiary,
                        ),
                      ),
                    ),
                  );
                }
                return SliverList(
                  delegate: SliverChildListDelegate([
                    for (final section in home.sections) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AfSpacing.s16,
                          AfSpacing.s16,
                          AfSpacing.s16,
                          AfSpacing.s12,
                        ),
                        child: Text(
                          section.title,
                          style: AfTypography.titleMedium,
                        ),
                      ),
                      // Determine if it's a song-only section.
                      if (section.items.isNotEmpty &&
                          section.items.every(
                            (item) => item.type == InnerTubeItemType.song,
                          ))
                        YouTubeSongGrid(items: section.items)
                      else
                        YouTubeHomeTileList(items: section.items),
                      const SizedBox(height: AfSpacing.s16),
                    ],
                  ]),
                );
              },
              loading: () => const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(AfSpacing.s32),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (e, _) => SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(AfSpacing.s16),
                  child: Text(
                    'Couldn\u2019t load recommendations',
                    style: AfTypography.bodyMedium.copyWith(
                      color: AfColors.textTertiary,
                    ),
                  ),
                ),
              ),
            ),

            const SliverToBoxAdapter(
              child: SizedBox(height: AfSpacing.bottomInsetWithMiniAndNav),
            ),
          ],
        ),
      ),
    );
  }
}

/// Glass pill button for the search icon in the YouTube Music header.
class GlassSearchButton extends StatelessWidget {
  const GlassSearchButton({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      ensureHitTarget: false,
      onTap: onTap,
      child: ClipRRect(
        borderRadius: AfRadii.borderPill,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.all(AfSpacing.s12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: AfRadii.borderPill,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
                width: 1,
              ),
            ),
            child: const Icon(
              LucideIcons.search,
              size: 18,
              color: AfColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Horizontal chip selector for YouTube Music home categories.
class YouTubeChipsRow extends ConsumerWidget {
  const YouTubeChipsRow({super.key, required this.chips});
  final List<InnerTubeChip> chips;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedChip = ref.watch(youtubeSelectedChipProvider);
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final chip = chips[index];
          final isSelected = selectedChip?.title == chip.title;
          return ChoiceChip(
            label: Text(
              chip.title,
              style: AfTypography.bodySmall.copyWith(
                color: isSelected ? Colors.black : AfColors.textPrimary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            selected: isSelected,
            selectedColor: Colors.white,
            backgroundColor: AfColors.surfaceRaised,
            onSelected: (_) {
              if (isSelected) {
                ref.read(youtubeSelectedChipProvider.notifier).state = null;
                ref.read(youtubeHomeParamsProvider.notifier).state = null;
              } else {
                ref.read(youtubeSelectedChipProvider.notifier).state = chip;
                ref.read(youtubeHomeParamsProvider.notifier).state =
                    chip.params;
              }
            },
          );
        },
      ),
    );
  }
}

/// Grid layout for YouTube song-only sections.
class YouTubeSongGrid extends ConsumerWidget {
  const YouTubeSongGrid({super.key, required this.items});
  final List<InnerTubeItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const double rowHeight = 72.0;
    final rows = math.min(4, items.length);
    if (rows == 0) return const SizedBox.shrink();
    final double gridHeight =
        rowHeight * rows + (rows > 1 ? (rows - 1) * 8.0 : 0.0);
    return SizedBox(
      height: gridHeight,
      child: GridView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: rows,
          mainAxisSpacing: 16,
          crossAxisSpacing: 8,
          childAspectRatio: rowHeight / 310.0,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          final track = AfTrack(
            id: item.id,
            title: item.title,
            artistName: item.subtitle,
            albumName: '',
            imageUrl: item.thumbnailUrl,
          );
          return PressScale(
            ensureHitTarget: true,
            onTap: () => ref.read(playActionsProvider).playSingle(track),
            onLongPress: () => showTrackContextMenu(context, ref, track),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: AfRadii.borderMd,
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: item.thumbnailUrl.isNotEmpty
                        ? Artwork(
                            url: item.thumbnailUrl,
                            size: 56,
                            radius: AfRadii.borderMd,
                          )
                        : Container(
                            color: AfColors.surfaceHigh,
                            child: const Icon(LucideIcons.music, size: 24),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AfTypography.bodyMedium.copyWith(
                          fontWeight: FontWeight.w500,
                          color: AfColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AfTypography.bodySmall.copyWith(
                          color: AfColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    LucideIcons.moreVertical,
                    size: 18,
                    color: AfColors.textSecondary,
                  ),
                  onPressed: () => showTrackContextMenu(context, ref, track),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Horizontal list of YouTube home tiles (albums, artists, playlists).
class YouTubeHomeTileList extends ConsumerWidget {
  const YouTubeHomeTileList({super.key, required this.items});
  final List<InnerTubeItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 220,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: AfSpacing.s12),
        itemBuilder: (context, index) {
          final item = items[index];
          return _YouTubeHomeTile(
            item: item,
            onTap: () {
              switch (item.type) {
                case InnerTubeItemType.song:
                  final track = AfTrack(
                    id: item.id,
                    title: item.title,
                    artistName: item.subtitle,
                    albumName: '',
                    imageUrl: item.thumbnailUrl,
                  );
                  ref.read(playActionsProvider).playSingle(track);
                  break;
                case InnerTubeItemType.album:
                  context.push('/album/${item.id}');
                  break;
                case InnerTubeItemType.artist:
                  context.push('/artist/${item.id}');
                  break;
                case InnerTubeItemType.playlist:
                  context.push('/playlist/${item.id}');
                  break;
              }
            },
            onLongPress: () {
              if (item.type == InnerTubeItemType.song) {
                final track = AfTrack(
                  id: item.id,
                  title: item.title,
                  artistName: item.subtitle,
                  albumName: '',
                  imageUrl: item.thumbnailUrl,
                );
                showTrackContextMenu(context, ref, track);
              }
            },
          );
        },
      ),
    );
  }
}

class _YouTubeHomeTile extends StatelessWidget {
  const _YouTubeHomeTile({
    required this.item,
    required this.onTap,
    required this.onLongPress,
  });
  final InnerTubeItem item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final isArtist = item.type == InnerTubeItemType.artist;
    return PressScale(
      ensureHitTarget: false,
      onTap: onTap,
      onLongPress: onLongPress,
      child: SizedBox(
        width: 140,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: isArtist
                    ? BorderRadius.circular(70)
                    : AfRadii.borderMd,
                child: item.thumbnailUrl.isNotEmpty
                    ? Artwork(
                        url: item.thumbnailUrl,
                        size: 140,
                        radius: isArtist
                            ? BorderRadius.circular(70)
                            : AfRadii.borderMd,
                      )
                    : Container(
                        color: AfColors.surfaceHigh,
                        child: Icon(
                          isArtist ? LucideIcons.user : LucideIcons.music,
                          color: AfColors.textTertiary,
                          size: 32,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: AfSpacing.s8),
            Text(
              item.title,
              style: AfTypography.bodySmall.copyWith(
                color: AfColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AfSpacing.s2),
            if (item.subtitle.isNotEmpty)
              Text(
                item.subtitle,
                style: AfTypography.bodySmall.copyWith(
                  color: AfColors.textTertiary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }
}
