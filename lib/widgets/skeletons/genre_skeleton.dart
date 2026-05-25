import 'package:flutter/material.dart';
import 'package:aetherfin/design_tokens/tokens.dart';
import 'package:aetherfin/widgets/skeleton.dart';
import 'package:aetherfin/widgets/skeletons/album_card_skeleton.dart';

/// Shimmer skeleton for the genre detail screen.
class GenreSkeleton extends StatelessWidget {
  const GenreSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: AfSpacing.pageHorizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
