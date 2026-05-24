import 'package:flutter/material.dart';
import 'package:aetherfin/design_tokens/tokens.dart';
import 'package:aetherfin/widgets/skeleton.dart';

/// A shimmer skeleton matching a single [TrackRow] layout.
///
/// 48dp tall, circle leading + two text bars.
class TrackRowSkeleton extends StatelessWidget {
  const TrackRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 48,
      child: Row(
        children: [
          SkeletonCircle(size: 40),
          SizedBox(width: AfSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FractionallySizedBox(
                  widthFactor: 0.6,
                  child: SkeletonBar(height: 14),
                ),
                SizedBox(height: AfSpacing.s4),
                FractionallySizedBox(
                  widthFactor: 0.4,
                  child: SkeletonBar(height: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
