import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../design_tokens/tokens.dart';

/// Shows a blurred bottom sheet that renders in the current route's overlay.
///
/// Unlike [showModalBottomSheet], this inserts an [OverlayEntry] into the
/// existing route's Navigator overlay, so [BackdropFilter] can actually
/// see and blur the content behind the sheet.
Future<T?> showBlurBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isDismissible = true,
  bool isScrollControlled = true,
  bool enableDrag = true,
  double topRadius = 24.0,
}) {
  final overlay = Navigator.of(context, rootNavigator: true).overlay;
  if (overlay == null) return Future.value(null);

  final completer = Completer<T?>();
  late OverlayEntry entry;

  entry = OverlayEntry(
    builder: (context) => _BlurBottomSheetOverlay<T>(
      builder: builder,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      topRadius: topRadius,
      onDismiss: (result) {
        entry.remove();
        if (!completer.isCompleted) completer.complete(result);
      },
    ),
  );

  overlay.insert(entry);
  return completer.future;
}

/// Overlay-based blur bottom sheet. Lives in the same overlay as the route
/// content so BackdropFilter can blur what's behind it.
class _BlurBottomSheetOverlay<T> extends StatefulWidget {
  const _BlurBottomSheetOverlay({
    required this.builder,
    required this.isDismissible,
    required this.enableDrag,
    required this.topRadius,
    required this.onDismiss,
  });

  final WidgetBuilder builder;
  final bool isDismissible;
  final bool enableDrag;
  final double topRadius;
  final void Function(T?) onDismiss;

  @override
  State<_BlurBottomSheetOverlay<T>> createState() =>
      _BlurBottomSheetOverlayState<T>();
}

class _BlurBottomSheetOverlayState<T> extends State<_BlurBottomSheetOverlay<T>>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _slideAnim;
  late final Animation<double> _fadeAnim;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: AfDurations.standard,
      reverseDuration: AfDurations.quick,
    );
    _slideAnim = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: AfCurves.easeEmphasized));
    _fadeAnim = CurvedAnimation(parent: _ctrl, curve: AfCurves.easeOut);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _dismiss([T? result]) {
    if (_dismissed) return;
    _dismissed = true;
    _ctrl.reverse().then((_) => widget.onDismiss(result));
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final slideOffset = _slideAnim.value;
        final opacity = _fadeAnim.value;

        return Material(
          type: MaterialType.transparency,
          child: GestureDetector(
            onTap: widget.isDismissible ? _dismiss : null,
            behavior: HitTestBehavior.opaque,
            child: Opacity(
              opacity: opacity,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Transform.translate(
                  offset: Offset(0, slideOffset * 400),
                  child: GestureDetector(
                    onVerticalDragEnd: widget.enableDrag
                        ? (details) {
                            final vy = details.primaryVelocity ?? 0;
                            if (vy > 300 || (vy > 0 && slideOffset > 0.3)) {
                              _dismiss();
                            }
                          }
                        : null,
                    child: Padding(
                      padding: EdgeInsets.only(bottom: viewInsets.bottom),
                      child: ClipRRect(
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(widget.topRadius),
                        ),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                          child: Container(
                            decoration: BoxDecoration(
                              color: AfColors.surfaceBase.withValues(
                                alpha: 0.70,
                              ),
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(widget.topRadius),
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
                                    color: AfColors.textTertiary.withValues(
                                      alpha: 0.4,
                                    ),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                widget.builder(context),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
