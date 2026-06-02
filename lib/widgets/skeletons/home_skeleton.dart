import 'package:flutter/material.dart';

import '../../design_tokens/tokens.dart';
import '../skeleton.dart';
import 'track_row_skeleton.dart';

/// Shimmer skeleton for the home screen hero album carousel.
class HomeCarouselSkeleton extends StatelessWidget {
  const HomeCarouselSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    return SizedBox(
      height: 192,
      child: PageView(
        children: List.generate(3, (_) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s8),
            child: SkeletonBlock(
              width: screenWidth * 0.92,
              height: 192,
              borderRadius: AfRadii.borderLg,
            ),
          );
        }),
      ),
    );
  }
}

/// Shimmer skeleton for the home screen recently played section.
class HomeRecentSkeleton extends StatelessWidget {
  const HomeRecentSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        TrackRowSkeleton(),
        SizedBox(height: AfSpacing.s4),
        TrackRowSkeleton(),
        SizedBox(height: AfSpacing.s4),
        TrackRowSkeleton(),
      ],
    );
  }
}

/// Shimmer skeleton for the home screen artists horizontal row.
class HomeArtistsSkeleton extends StatelessWidget {
  const HomeArtistsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 172,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
        itemCount: 6,
        itemBuilder: (_, _) {
          return const Padding(
            padding: EdgeInsets.only(right: AfSpacing.s12),
            child: Column(
              children: [
                SkeletonCircle(size: 120),
                SizedBox(height: AfSpacing.s8),
                SkeletonBar(width: 60, height: 12),
              ],
            ),
          );
        },
      ),
    );
  }
}
