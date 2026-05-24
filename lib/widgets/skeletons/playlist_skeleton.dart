import 'package:flutter/material.dart';
import 'package:aetherfin/design_tokens/tokens.dart';
import 'package:aetherfin/widgets/skeleton.dart';
import 'package:aetherfin/widgets/skeletons/track_row_skeleton.dart';

/// Shimmer skeleton for the playlist detail screen.
class PlaylistSkeleton extends StatelessWidget {
  const PlaylistSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    return SingleChildScrollView(
      child: Column(
        children: [
          SkeletonBlock(width: screenWidth, height: 200),
          const SizedBox(height: AfSpacing.s16),
          const Padding(
            padding: AfSpacing.pageHorizontal,
            child: Column(
              children: [
                FractionallySizedBox(
                  widthFactor: 0.5,
                  child: SkeletonBar(height: 22),
                ),
                SizedBox(height: AfSpacing.s8),
                FractionallySizedBox(
                  widthFactor: 0.3,
                  child: SkeletonBar(height: 14),
                ),
                SizedBox(height: AfSpacing.s16),
                TrackRowSkeleton(),
                SizedBox(height: AfSpacing.s4),
                TrackRowSkeleton(),
                SizedBox(height: AfSpacing.s4),
                TrackRowSkeleton(),
                SizedBox(height: AfSpacing.s4),
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
