import 'package:flutter/material.dart';
import 'package:aetherfin/design_tokens/tokens.dart';
import 'package:aetherfin/widgets/skeleton.dart';

/// Shimmer skeleton for the lyrics screen.
class LyricsSkeleton extends StatelessWidget {
  const LyricsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: AfSpacing.pageHorizontalGenerous,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Lines 1-4
          FractionallySizedBox(
            widthFactor: 0.90,
            child: SkeletonBar(height: 16),
          ),
          SizedBox(height: AfSpacing.s12),
          FractionallySizedBox(
            widthFactor: 0.75,
            child: SkeletonBar(height: 16),
          ),
          SizedBox(height: AfSpacing.s12),
          FractionallySizedBox(
            widthFactor: 0.85,
            child: SkeletonBar(height: 16),
          ),
          SizedBox(height: AfSpacing.s12),
          FractionallySizedBox(
            widthFactor: 0.60,
            child: SkeletonBar(height: 16),
          ),
          SizedBox(height: AfSpacing.s24), // stanza break
          // Lines 5-8
          FractionallySizedBox(
            widthFactor: 0.95,
            child: SkeletonBar(height: 16),
          ),
          SizedBox(height: AfSpacing.s12),
          FractionallySizedBox(
            widthFactor: 0.70,
            child: SkeletonBar(height: 16),
          ),
          SizedBox(height: AfSpacing.s12),
          FractionallySizedBox(
            widthFactor: 0.80,
            child: SkeletonBar(height: 16),
          ),
          SizedBox(height: AfSpacing.s12),
          FractionallySizedBox(
            widthFactor: 0.65,
            child: SkeletonBar(height: 16),
          ),
        ],
      ),
    );
  }
}
