import 'dart:ui';

import 'package:flutter/material.dart';

/// Shows a dialog with a glass-blur background effect.
///
/// Wraps the dialog in a [BackdropFilter] so content behind it is blurred,
/// matching the app's glass aesthetic. Use this instead of [showDialog]
/// for all modal dialogs.
Future<T?> showAfDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (ctx) => BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
      child: builder(ctx),
    ),
  );
}
