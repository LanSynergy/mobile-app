import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../design_tokens/tokens.dart';
import '../utils/display_error.dart';

/// Inline error card for failed `AsyncValue` fetches.
///
/// Two layouts:
///
/// - **Compact** (`compactHeight` provided): an inline horizontal row
///   sized to match the loading skeleton.
/// - **Centered** (`compactHeight == null`): a centered column suitable
///   for full-screen sections.
class AsyncErrorView extends StatelessWidget {
  const AsyncErrorView({
    super.key,
    required this.label,
    required this.error,
    required this.onRetry,
  }) : compactHeight = null;

  const AsyncErrorView.compact({
    super.key,
    required this.label,
    required this.error,
    required this.onRetry,
    required double height,
  }) : compactHeight = height;

  final String label;
  final Object error;
  final VoidCallback onRetry;

  /// When set, renders an inline row of exactly this height. When null,
  /// renders a centered column with vertical breathing room.
  final double? compactHeight;

  void _showFullError(BuildContext context) {
    final fullText = displayError(error);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: SingleChildScrollView(
          child: SelectableText(
            fullText,
            style: AfTypography.bodySmall.copyWith(
              color: AfColors.textSecondary,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final compactHeight = this.compactHeight;
    if (compactHeight != null) {
      return GestureDetector(
        onLongPress: () => _showFullError(context),
        child: SizedBox(
          height: compactHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
            child: Row(
              children: [
                const Icon(
                  LucideIcons.cloudOff,
                  color: AfColors.semanticError,
                  size: 20,
                ),
                const SizedBox(width: AfSpacing.s8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AfTypography.bodyMedium.copyWith(
                          color: AfColors.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        displayError(error),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AfTypography.caption.copyWith(
                          color: AfColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AfSpacing.s8),
                TextButton(onPressed: onRetry, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              LucideIcons.cloudOff,
              color: AfColors.semanticError,
              size: 40,
            ),
            const SizedBox(height: AfSpacing.s12),
            Text(
              label,
              textAlign: TextAlign.center,
              style: AfTypography.titleSmall.copyWith(
                color: AfColors.textPrimary,
              ),
            ),
            const SizedBox(height: AfSpacing.s4),
            GestureDetector(
              onLongPress: () => _showFullError(context),
              child: Text(
                displayError(error),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: AfTypography.bodySmall.copyWith(
                  color: AfColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: AfSpacing.s16),
            FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
