import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_tokens/colors.dart';
import 'spectral_providers.dart';

/// Animated spectral value — updates every frame during transitions.
/// Read via [ValueListenableBuilder] in the widget tree.
final ValueNotifier<Spectral> animatedSpectral =
    ValueNotifier<Spectral>(Spectral.fallback);

/// Watches [currentSpectralProvider] and animates color transitions.
/// Wrap [MaterialApp] with this widget.
class AnimatedSpectralScope extends ConsumerStatefulWidget {
  const AnimatedSpectralScope({required this.child, super.key});
  final Widget child;

  @override
  ConsumerState<AnimatedSpectralScope> createState() =>
      _AnimatedSpectralScopeState();
}

class _AnimatedSpectralScopeState extends ConsumerState<AnimatedSpectralScope>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  Spectral _from = Spectral.fallback;
  Spectral _to = Spectral.fallback;
  Spectral _current = Spectral.fallback;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _ctrl.addListener(() {
      _current = _lerpSpectral(_from, _to, _ctrl.value);
      animatedSpectral.value = _current;
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final next = ref.watch(currentSpectralProvider);
    if (next != _to) {
      _from = _current;
      _to = next;
      _ctrl.forward(from: 0);
    }
    return widget.child;
  }
}

/// Linearly interpolates every color field in [Spectral].
Spectral _lerpSpectral(Spectral a, Spectral b, double t) {
  if (t == 0) return a;
  if (t == 1) return b;
  return Spectral(
    energy: Color.lerp(a.energy, b.energy, t)!,
    shadow: Color.lerp(a.shadow, b.shadow, t)!,
    glow: Color.lerp(a.glow, b.glow, t)!,
    primary: Color.lerp(a.primary, b.primary, t)!,
    secondary: Color.lerp(a.secondary, b.secondary, t)!,
    muted: Color.lerp(a.muted, b.muted, t)!,
    link: Color.lerp(a.link, b.link, t)!,
    warning: Color.lerp(a.warning, b.warning, t)!,
    surfaceCanvas: Color.lerp(a.surfaceCanvas, b.surfaceCanvas, t)!,
    surfaceLow: Color.lerp(a.surfaceLow, b.surfaceLow, t)!,
    surfaceBase: Color.lerp(a.surfaceBase, b.surfaceBase, t)!,
    surfaceRaised: Color.lerp(a.surfaceRaised, b.surfaceRaised, t)!,
    surfaceHigh: Color.lerp(a.surfaceHigh, b.surfaceHigh, t)!,
    surfaceMax: Color.lerp(a.surfaceMax, b.surfaceMax, t)!,
    textPrimary: Color.lerp(a.textPrimary, b.textPrimary, t)!,
    textSecondary: Color.lerp(a.textSecondary, b.textSecondary, t)!,
    textTertiary: Color.lerp(a.textTertiary, b.textTertiary, t)!,
    textDisabled: Color.lerp(a.textDisabled, b.textDisabled, t)!,
    textOnPrimary: Color.lerp(a.textOnPrimary, b.textOnPrimary, t)!,
  );
}
