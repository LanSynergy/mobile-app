import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design_tokens/tokens.dart';

class NowPlayingMetaChip extends ConsumerWidget {
  const NowPlayingMetaChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AfSpacing.s8,
        vertical: AfSpacing.s2,
      ),
      decoration: const BoxDecoration(
        color: AfColors.surfaceHigh,
        borderRadius: AfRadii.borderPill,
      ),
      child: Text(
        label,
        style: AfTypography.caption.copyWith(color: AfColors.textSecondary),
      ),
    );
  }
}
