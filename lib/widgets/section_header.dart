import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_tokens/tokens.dart';
import '../state/providers.dart';

/// Section title with optional "See all" action.
///
/// `Recently Played                    See More ›`
///
/// 24dp top spacing, 12dp bottom spacing (callers handle the spacing wrappers).
class SectionHeader extends ConsumerWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onActionTap,
    this.uppercase = false,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onActionTap;

  /// When true, the title is uppercased and rendered in `label` style
  /// (used for sub-section headers like `PUBLIC PLAYLISTS`).
  final bool uppercase;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spectral = ref.watch(
      currentSpectralProvider.select((s) => s.primary),
    );
    final titleStyle = uppercase
        ? AfTypography.label.copyWith(color: AfColors.textSecondary)
        : AfTypography.titleMedium.copyWith(color: AfColors.textPrimary);

    return Padding(
      padding: const EdgeInsets.only(bottom: AfSpacing.s12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              uppercase ? title.toUpperCase() : title,
              style: titleStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (actionLabel != null)
            GestureDetector(
              onTap: onActionTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AfSpacing.s8,
                  vertical: AfSpacing.s4,
                ),
                child: Text(
                  '$actionLabel ›',
                  style: AfTypography.bodySmall.copyWith(color: spectral),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
