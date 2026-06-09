import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../design_tokens/tokens.dart';

/// A single item in an [AfBreadcrumb].
class BreadcrumbItem {
  const BreadcrumbItem({required this.label, this.onTap});

  /// Display label.
  final String label;

  /// Tap callback. If `null`, the item is rendered as non-interactive
  /// (typically the last / current item).
  final VoidCallback? onTap;
}

/// Aetherfin breadcrumb navigation widget.
///
/// Renders a horizontal row of tappable labels separated by chevrons.
/// The last item is styled as the current (non-interactive) page.
///
/// ```dart
/// AfBreadcrumb(
///   items: [
///     BreadcrumbItem(label: 'Home', onTap: () => context.go('/home')),
///     BreadcrumbItem(label: 'Artist: Foo', onTap: () => context.push('/artist/123')),
///     BreadcrumbItem(label: 'Album: Bar'),
///   ],
/// )
/// ```
class AfBreadcrumb extends StatelessWidget {
  const AfBreadcrumb({super.key, required this.items});

  /// Ordered list of breadcrumb items, first = root, last = current page.
  final List<BreadcrumbItem> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            _BreadcrumbChip(item: items[i]),
            if (i < items.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AfSpacing.s4),
                child: Icon(
                  LucideIcons.chevronRight,
                  size: 14,
                  color: AfColors.textTertiary,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _BreadcrumbChip extends StatelessWidget {
  const _BreadcrumbChip({required this.item});

  final BreadcrumbItem item;

  @override
  Widget build(BuildContext context) {
    final isCurrent = item.onTap == null;
    final color = isCurrent ? AfColors.textSecondary : AfColors.accentPrimary;
    final style = AfTypography.label.copyWith(color: color);

    if (isCurrent) {
      return Text(
        item.label,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    return GestureDetector(
      onTap: item.onTap,
      child: Text(
        item.label,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
