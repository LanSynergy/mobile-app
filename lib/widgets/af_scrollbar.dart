import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_tokens/tokens.dart';
import '../state/providers.dart';

/// Styled scrollbar that matches the Dark Moody design language.
///
/// Thin (3dp), pill-shaped, uses warm amber accent on scroll and a muted
/// surface hint when idle. Wrap any scrollable with this instead of
/// the raw [Scrollbar] widget.
class AfScrollbar extends ConsumerWidget {
  const AfScrollbar({
    super.key,
    required this.child,
    this.controller,
    this.thumbVisibility,
    this.scrollbarOrientation,
  });

  final Widget child;
  final ScrollController? controller;
  final bool? thumbVisibility;
  final ScrollbarOrientation? scrollbarOrientation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spectral = ref.watch(currentSpectralProvider);
    return ScrollbarTheme(
      data: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.dragged) ||
              states.contains(WidgetState.hovered)) {
            return spectral.primary.withValues(alpha: 0.6);
          }
          return AfColors.surfaceMax.withValues(alpha: 0.5);
        }),
        trackColor: WidgetStateProperty.all(
          AfColors.surfaceHigh.withValues(alpha: 0.2),
        ),
        radius: const Radius.circular(AfRadii.pill),
        thumbVisibility: WidgetStateProperty.all(thumbVisibility ?? false),
        thickness: WidgetStateProperty.all(3),
      ),
      child: Scrollbar(
        controller: controller,
        thumbVisibility: thumbVisibility,
        scrollbarOrientation: scrollbarOrientation,
        interactive: true,
        notificationPredicate: defaultScrollNotificationPredicate,
        child: child,
      ),
    );
  }
}
