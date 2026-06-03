import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../design_tokens/tokens.dart';

/// Shows a blurred dialog that renders in the current route's overlay.
///
/// Unlike [showDialog], this inserts an [OverlayEntry] into the existing
/// route's Navigator overlay, so [BackdropFilter] can actually see and
/// blur the content behind the dialog — no new route, no opaque barrier.
///
/// Pass [child] for simple content, or [builder] when the child needs to
/// dismiss the dialog programmatically (e.g. a Close button).
Future<T?> showBlurDialog<T>({
  required BuildContext context,
  Widget? child,
  Widget Function(BuildContext context, void Function([T? result]) dismiss)?
  builder,
  bool barrierDismissible = true,
}) {
  assert(child != null || builder != null, 'Provide child or builder');
  final overlay = Navigator.of(context, rootNavigator: true).overlay;
  if (overlay == null) return Future.value(null);

  final completer = Completer<T?>();
  late OverlayEntry entry;

  entry = OverlayEntry(
    builder: (context) => _BlurDialogOverlay<T>(
      barrierDismissible: barrierDismissible,
      onDismiss: (result) {
        entry.remove();
        if (!completer.isCompleted) completer.complete(result);
      },
      child: builder != null
          ? builder(context, ([T? result]) {
              entry.remove();
              if (!completer.isCompleted) completer.complete(result);
            })
          : child!,
    ),
  );

  overlay.insert(entry);
  return completer.future;
}

class _BlurDialogOverlay<T> extends StatefulWidget {
  const _BlurDialogOverlay({
    required this.child,
    required this.barrierDismissible,
    required this.onDismiss,
  });

  final Widget child;
  final bool barrierDismissible;
  final void Function(T?) onDismiss;

  @override
  State<_BlurDialogOverlay<T>> createState() => _BlurDialogOverlayState<T>();
}

class _BlurDialogOverlayState<T> extends State<_BlurDialogOverlay<T>>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;
  bool _dismissed = false;
  bool _ready = false;

  static const _borderRadius = AfRadii.lg;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: AfDurations.standard,
      reverseDuration: AfDurations.quick,
    );
    _fadeAnim = CurvedAnimation(parent: _ctrl, curve: AfCurves.easeOut);
    _scaleAnim = Tween<double>(
      begin: 0.92,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: AfCurves.easeEmphasized));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _ready = true);
    });
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
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final opacity = _fadeAnim.value;
        final scale = _scaleAnim.value;

        return Material(
          type: MaterialType.transparency,
          child: GestureDetector(
            onTap: widget.barrierDismissible ? _dismiss : null,
            behavior: HitTestBehavior.opaque,
            child: Opacity(
              opacity: _ready ? opacity : 0.0,
              child: Stack(
                children: [
                  // ── Full-screen blur behind everything ──
                  Positioned.fill(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.25),
                      ),
                    ),
                  ),
                  // ── Dialog content (solid, no extra blur) ──
                  Center(
                    child: Transform.scale(
                      scale: scale,
                      child: GestureDetector(
                        onTap: () {},
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AfSpacing.s24,
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(AfSpacing.s16),
                            decoration: BoxDecoration(
                              color: AfColors.surfaceRaised.withValues(
                                alpha: 0.85,
                              ),
                              borderRadius: BorderRadius.circular(
                                _borderRadius,
                              ),
                              border: Border.all(
                                color: AfColors.glassBorderEmphasis,
                                width: 0.5,
                              ),
                            ),
                            child: ListTileTheme(
                              tileColor: Colors.transparent,
                              child: widget.child,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
