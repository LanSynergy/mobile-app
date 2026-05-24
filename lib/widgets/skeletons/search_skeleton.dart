import 'package:flutter/material.dart';
import 'package:aetherfin/design_tokens/tokens.dart';
import 'package:aetherfin/widgets/skeleton.dart';

/// Shimmer-animated search results skeleton.
///
/// Replaces the private `_SearchLoadingSkeleton` in [search_screen.dart].
/// Layout: 5 alternating-width bars (200/140/200/140/200) at 14dp height.
class SearchSkeleton extends StatelessWidget {
  const SearchSkeleton({super.key});

  static const _widths = [200.0, 140.0, 200.0, 140.0, 200.0];

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
          for (final w in _widths) ...[
            SkeletonBar(width: w, height: 14),
            const SizedBox(height: AfSpacing.s12),
          ],
        ],
      ),
    );
  }
}
