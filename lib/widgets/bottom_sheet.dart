import 'package:flutter/material.dart';

import '../design_tokens/tokens.dart';

/// A reusable function to show a blurred, transparent bottom sheet
/// with a smooth slide-up + fade transition.
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
    // Custom transition: slide up + fade with emphasized curve.
    sheetAnimationStyle: const AnimationStyle(
      duration: AfDurations.standard,
      reverseDuration: AfDurations.quick,
      curve: AfCurves.easeEmphasized,
      reverseCurve: AfCurves.easeIn,
    ),
    builder: (BuildContext context) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: BlurBottomSheet(topRadius: topRadius, child: builder(context)),
      );
    },
  );
}

/// The actual Blur Bottom Sheet widget.
class BlurBottomSheet extends StatelessWidget {
  const BlurBottomSheet({
    super.key,
    required this.child,
    this.topRadius = 24.0,
  });
  final Widget child;
  final double topRadius;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ClipRRect(
        borderRadius: BorderRadius.vertical(top: Radius.circular(topRadius)),
        child: Container(
          decoration: BoxDecoration(
            color: AfColors.surfaceBase.withValues(alpha: 0.92),
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(topRadius),
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
                  color: AfColors.textTertiary.withValues(alpha: 0.4),
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
