import 'dart:ui';

import 'package:flutter/material.dart';

import '../design_tokens/tokens.dart';

Future<T?> showAfDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierColor: Colors.transparent,
    barrierDismissible: barrierDismissible,
    builder: (ctx) => BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
      child: Center(
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: AfSpacing.gutter),
            constraints: const BoxConstraints(maxWidth: 360),
            decoration: BoxDecoration(
              color: AfColors.surfaceHigh.withValues(alpha: 0.7),
              borderRadius: AfRadii.borderXl,
            ),
            child: builder(ctx),
          ),
        ),
      ),
    ),
  );
}
