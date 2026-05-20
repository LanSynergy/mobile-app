import 'dart:ui';
import 'package:flutter/material.dart';

/// A reusable function to show a blurred, transparent dialog.
Future<T?> showBlurDialog<T>({
  required BuildContext context,
  required Widget child,
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: Colors.black.withValues(alpha: 0.2),
    builder: (BuildContext context) {
      return _BlurDialog(child: child);
    },
  );
}

/// The actual Blur Dialog widget.
class _BlurDialog extends StatelessWidget {
  final Widget child;

  const _BlurDialog({required this.child});

  @override
  Widget build(BuildContext context) {
    const borderRadius = 20.0;
    const blurSigma = 15.0;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Container(
            padding: const EdgeInsets.all(24.0),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Backward-compatible alias for [showBlurDialog].
Future<T?> showAfDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showBlurDialog<T>(
    context: context,
    child: Builder(builder: builder),
    barrierDismissible: barrierDismissible,
  );
}
