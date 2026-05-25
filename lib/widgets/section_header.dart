import 'package:flutter/material.dart';

import '../design_tokens/tokens.dart';

/// `Recently Played                    See More ›`
///
/// Section title + optional trailing action. 24dp top spacing,
/// 12dp bottom spacing (callers handle the spacing wrappers).
class SectionHeader extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final titleStyle = uppercase
        ? AfTypography.label.copyWith(color: AfColors.textTertiary)
        : AfTypography.titleSmall.copyWith(color: AfColors.textPrimary);

    return Row(
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
                style: AfTypography.bodySmall.copyWith(
                  color: AfColors.textTertiary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
