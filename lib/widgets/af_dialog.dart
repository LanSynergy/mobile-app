import 'dart:ui';

import 'package:flutter/material.dart';

import '../design_tokens/tokens.dart';

/// Shows a bottom-anchored dialog with frosted-glass backdrop.
///
/// Uses [showModalBottomSheet] under the hood so the sheet is properly
/// constrained to the bottom, respects safe areas, and scrolls if
/// content exceeds the viewport. The barrier is fully transparent —
/// the frosted effect comes from [BackdropFilter] inside the sheet.
Future<T?> showAfDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.transparent,
    isDismissible: barrierDismissible,
    enableDrag: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.zero),
    ),
    builder: (ctx) => SafeArea(
      top: false,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.85,
          ),
          decoration: BoxDecoration(
            color: AfColors.surfaceHigh.withValues(alpha: 0.85),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(28),
            ),
          ),
          child: builder(ctx),
        ),
      ),
    ),
  );
}
