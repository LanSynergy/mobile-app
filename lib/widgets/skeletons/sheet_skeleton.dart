import 'package:flutter/material.dart';

import '../../design_tokens/tokens.dart';
import '../skeleton.dart';

/// Shimmer skeleton for bottom sheet content.
///
/// Uses [SkeletonBar] and [SkeletonBlock] with shimmer animation,
/// suitable for track lists, action menus, and other sheet overlays.
class SheetSkeleton extends StatelessWidget {
  const SheetSkeleton({super.key, this.rowCount = 4});

  /// Number of skeleton rows to show.
  final int rowCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(rowCount, (_) {
        return const Padding(
          padding: EdgeInsets.symmetric(
            vertical: AfSpacing.s4,
            horizontal: AfSpacing.s16,
          ),
          child: Row(
            children: [
              // Leading icon area
              SkeletonBlock(width: 40, height: 40),
              SizedBox(width: AfSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBar(height: 14),
                    SizedBox(height: AfSpacing.s4),
                    FractionallySizedBox(
                      widthFactor: 0.5,
                      child: SkeletonBar(height: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
