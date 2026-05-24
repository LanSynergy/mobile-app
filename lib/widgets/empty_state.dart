import 'package:flutter/material.dart';

import '../design_tokens/tokens.dart';

/// Soft empty illustration + copy + optional CTA.
///
/// Per spec §8.2: "Your library is quiet. Add music to your Jellyfin
/// server to see it here." This widget is the canonical layout.
class EmptyState extends StatelessWidget {

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.actionLabel,
    this.onAction,
  });
  final IconData icon;
  final String title;
  final String? body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AfSpacing.gutterGenerous,
        vertical: AfSpacing.s32,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: AfColors.indigo400),
          const SizedBox(height: AfSpacing.s16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AfTypography.titleMedium.copyWith(
              color: AfColors.textPrimary,
            ),
          ),
          if (body != null) ...[
            const SizedBox(height: AfSpacing.s8),
            Text(
              body!,
              textAlign: TextAlign.center,
              style: AfTypography.bodyMedium.copyWith(
                color: AfColors.textSecondary,
              ),
            ),
          ],
          if (actionLabel != null) ...[
            const SizedBox(height: AfSpacing.s24),
            ElevatedButton(
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}
