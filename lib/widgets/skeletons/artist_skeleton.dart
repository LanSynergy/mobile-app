import 'package:flutter/material.dart';

import '../../design_tokens/tokens.dart';
import '../skeleton.dart';
import '../section_header.dart';
import 'album_card_skeleton.dart';
import 'track_row_skeleton.dart';

/// Shimmer skeleton for the artist detail screen.
///
/// Circle avatar, name bar, top songs section, albums grid.
class ArtistSkeleton extends StatelessWidget {
  const ArtistSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: AfSpacing.s32),
          const Center(child: SkeletonCircle(size: 120)),
          const SizedBox(height: AfSpacing.s16),
          const Center(
            child: FractionallySizedBox(
              widthFactor: 0.4,
              child: SkeletonBar(height: 20),
            ),
          ),
          const SizedBox(height: AfSpacing.s32),
          const Padding(
            padding: AfSpacing.pageHorizontal,
            child: Column(
              children: [
                SectionHeader(title: 'Top Songs'),
                SizedBox(height: AfSpacing.s8),
                TrackRowSkeleton(),
                SizedBox(height: AfSpacing.s4),
                TrackRowSkeleton(),
                SizedBox(height: AfSpacing.s4),
                TrackRowSkeleton(),
                SizedBox(height: AfSpacing.s24),
                SectionHeader(title: 'Albums'),
                SizedBox(height: AfSpacing.s12),
              ],
            ),
          ),
          Padding(
            padding: AfSpacing.pageHorizontal,
            child: GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 0.9,
              mainAxisSpacing: AfSpacing.s8,
              crossAxisSpacing: AfSpacing.s8,
              children: const [
                AlbumCardSkeleton(),
                AlbumCardSkeleton(),
                AlbumCardSkeleton(),
                AlbumCardSkeleton(),
                AlbumCardSkeleton(),
                AlbumCardSkeleton(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
