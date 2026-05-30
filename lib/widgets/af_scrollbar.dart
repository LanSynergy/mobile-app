import 'package:flutter/material.dart';

/// Custom scrollbar that matches Aetherfin's dark design language.
///
/// Thin (3dp), pill-shaped, uses indigo accent on scroll and a muted
/// surface hint when idle.  Wrap any scrollable with this instead of
/// the raw [Scrollbar] widget.
class AfScrollbar extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: controller,
      thumbVisibility: thumbVisibility,
      scrollbarOrientation: scrollbarOrientation,
      interactive: true,
      notificationPredicate: defaultScrollNotificationPredicate,
      child: child,
    );
  }
}
