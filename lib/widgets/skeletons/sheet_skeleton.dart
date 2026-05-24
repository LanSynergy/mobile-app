import 'package:flutter/material.dart';
import 'package:aetherfin/design_tokens/tokens.dart';

/// Static skeleton rows for bottom sheets (Tier 2).
///
/// No shimmer animation — static [Container] bars with [AfColors.surfaceBase]
/// fill. Suitable for constrained overlays where shimmer feels cramped.
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
          padding: EdgeInsets.symmetric(vertical: AfSpacing.s4),
          child: Row(
            children: [
              // Leading icon area
              SizedBox(
                width: 40,
                height: 40,
              ),
              SizedBox(width: AfSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 14),
                    SizedBox(height: AfSpacing.s4),
                    FractionallySizedBox(
                      widthFactor: 0.5,
                      child: SizedBox(height: 12),
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
