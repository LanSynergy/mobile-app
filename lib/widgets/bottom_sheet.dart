import 'dart:ui';
import 'package:flutter/material.dart';

/// A reusable function to show a blurred, transparent bottom sheet.
Future<T?> showBlurBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isDismissible = true,
  bool isScrollControlled = true,
  bool enableDrag = true,
  double topRadius = 24.0,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isDismissible: isDismissible,
    isScrollControlled: isScrollControlled,
    enableDrag: enableDrag,
    backgroundColor: Colors.transparent,
    builder: (BuildContext context) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: BlurBottomSheet(
          topRadius: topRadius,
          child: builder(context),
        ),
      );
    },
  );
}

/// The actual Blur Bottom Sheet widget.
class BlurBottomSheet extends StatelessWidget {
  final Widget child;
  final double topRadius;
  final double blurSigma;

  const BlurBottomSheet({
    super.key,
    required this.child,
    this.topRadius = 24.0,
    this.blurSigma = 15.0,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.vertical(top: Radius.circular(topRadius)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.vertical(top: Radius.circular(topRadius)),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.3), width: 1.5),
              left: BorderSide(color: Colors.white.withValues(alpha: 0.3), width: 1.5),
              right: BorderSide(color: Colors.white.withValues(alpha: 0.3), width: 1.5),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      ),
    );
  }
}
