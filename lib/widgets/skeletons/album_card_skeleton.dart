import 'package:flutter/material.dart';
import 'package:aetherfin/design_tokens/tokens.dart';
import 'package:aetherfin/widgets/skeleton.dart';

/// A shimmer skeleton matching an album card tile layout.
///
/// Artwork block + title bar + subtitle bar.
class AlbumCardSkeleton extends StatelessWidget {
  const AlbumCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SkeletonBlock(width: double.infinity, height: double.infinity),
        ),
        SizedBox(height: AfSpacing.s8),
        FractionallySizedBox(widthFactor: 0.7, child: SkeletonBar(height: 14)),
        SizedBox(height: AfSpacing.s4),
        FractionallySizedBox(widthFactor: 0.5, child: SkeletonBar(height: 12)),
      ],
    );
  }
}
