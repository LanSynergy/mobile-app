import 'package:flutter/material.dart';

import '../../design_tokens/tokens.dart';
import '../skeleton.dart';
import 'album_card_skeleton.dart';

/// Shimmer skeleton for the genre detail screen.
///
/// Genre name bar and a grid of album cards.
class GenreSkeleton extends StatelessWidget {
  const GenreSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: AfSpacing.pageHorizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Genre title
          const SkeletonBar(width: 120, height: 20),
          const SizedBox(height: AfSpacing.s12),
          Expanded(
            child: GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: AfSpacing.s8,
              crossAxisSpacing: AfSpacing.s8,
              childAspectRatio: 0.9,
              children: const [
                AlbumCardSkeleton(),
                AlbumCardSkeleton(),
                AlbumCardSkeleton(),
                AlbumCardSkeleton(),
                AlbumCardSkeleton(),
                AlbumCardSkeleton(),
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
