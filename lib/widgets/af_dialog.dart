import 'dart:ui';
import 'package:flutter/material.dart';

import '../design_tokens/tokens.dart';

/// A reusable function to show a blurred, transparent dialog.
Future<T?> showBlurDialog<T>({
  required BuildContext context,
  required Widget child,
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: AfColors.surfaceScrim,
    builder: (BuildContext context) {
      return _BlurDialog(child: child);
    },
  );
}

/// The actual Blur Dialog widget.
class _BlurDialog extends StatelessWidget {

  const _BlurDialog({required this.child});
  final Widget child;

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
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: AfColors.surfaceRaised.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(borderRadius),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
