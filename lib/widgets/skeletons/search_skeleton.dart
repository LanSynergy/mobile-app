import 'package:flutter/material.dart';

import '../../design_tokens/tokens.dart';
import '../skeleton.dart';

/// Shimmer-animated search results skeleton.
///
/// Alternating-width bars representing typical search result rows:
/// section headers, titles, artist lines.
class SearchSkeleton extends StatelessWidget {
  const SearchSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AfSpacing.s16,
        vertical: AfSpacing.s24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header bar
          const SkeletonBar(width: 120, height: 14),
          const SizedBox(height: AfSpacing.s16),
          // Result rows — album-style: artwork + title + artist
          ...List.generate(5, (i) {
            final isWide = i.isEven;
            return Padding(
              padding: const EdgeInsets.only(bottom: AfSpacing.s12),
              child: Row(
                children: [
                  const SkeletonBlock(width: 48, height: 48),
                  const SizedBox(width: AfSpacing.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBar(width: isWide ? 200 : 140, height: 14),
                        const SizedBox(height: AfSpacing.s4),
                        SkeletonBar(width: isWide ? 120 : 90, height: 12),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
