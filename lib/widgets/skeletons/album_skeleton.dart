import 'package:flutter/material.dart';
import 'package:aetherfin/design_tokens/tokens.dart';
import 'package:aetherfin/widgets/skeleton.dart';
import 'package:aetherfin/widgets/skeletons/track_row_skeleton.dart';

/// Shimmer skeleton for the album detail screen.
class AlbumSkeleton extends StatelessWidget {
  const AlbumSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    return SingleChildScrollView(
      child: Column(
        children: [
          SkeletonBlock(width: screenWidth, height: screenWidth),
          const SizedBox(height: AfSpacing.s16),
          const Padding(
            padding: AfSpacing.pageHorizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FractionallySizedBox(
                  widthFactor: 0.6,
                  child: SkeletonBar(height: 20),
                ),
                SizedBox(height: AfSpacing.s8),
                FractionallySizedBox(
                  widthFactor: 0.4,
                  child: SkeletonBar(height: 16),
                ),
                SizedBox(height: AfSpacing.s16),
                Divider(),
                SizedBox(height: AfSpacing.s8),
                TrackRowSkeleton(),
                SizedBox(height: AfSpacing.s4),
                TrackRowSkeleton(),
                SizedBox(height: AfSpacing.s4),
                TrackRowSkeleton(),
                SizedBox(height: AfSpacing.s4),
                TrackRowSkeleton(),
                SizedBox(height: AfSpacing.s4),
                TrackRowSkeleton(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
