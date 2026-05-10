import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_tokens/tokens.dart';
import '../state/providers.dart';
import 'press_scale.dart';

/// Custom 4-tab bottom navigation.
///
/// Per §7.7:
///   - 4 destinations only.
///   - 72dp height (excluding gesture inset).
///   - 24dp glyph + 11dp label.
///   - Active indicator is a 32dp wide × 3dp tall capsule under the glyph
///     in `text.primary`; slides 240ms `easeStandard` between tabs.
class AfBottomNavItem {
  final IconData icon;
  final IconData filledIcon;
  final String label;
  const AfBottomNavItem({
    required this.icon,
    required this.filledIcon,
    required this.label,
  });
}

class AfBottomNav extends ConsumerStatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final List<AfBottomNavItem> items;

  const AfBottomNav({
    super.key,
    required this.currentIndex,
    required this.onSelect,
    required this.items,
  });

  @override
  ConsumerState<AfBottomNav> createState() => _AfBottomNavState();
}

class _AfBottomNavState extends ConsumerState<AfBottomNav>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: AfDurations.standard,
    value: widget.currentIndex.toDouble(),
    lowerBound: 0,
    upperBound: (widget.items.length - 1).toDouble(),
  );

  @override
  void didUpdateWidget(AfBottomNav old) {
    super.didUpdateWidget(old);
    if (old.currentIndex != widget.currentIndex) {
      final reduced = MediaQuery.of(context).disableAnimations;
      if (reduced) {
        _ctrl.value = widget.currentIndex.toDouble();
      } else {
        _ctrl.animateTo(
          widget.currentIndex.toDouble(),
          duration: AfDurations.standard,
          curve: AfCurves.easeStandard,
        );
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showLabels = ref.watch(showNavLabelsProvider);
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: AfColors.surfaceCanvas,
        border: Border(
          top: BorderSide(color: AfColors.surfaceLow, width: 1),
        ),
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SizedBox(
        height: AfSpacing.bottomNavHeight,
        child: LayoutBuilder(
          builder: (context, c) {
            final tabWidth = c.maxWidth / widget.items.length;
            return Stack(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    for (var i = 0; i < widget.items.length; i++)
                      Expanded(
                        child: _Tab(
                          item: widget.items[i],
                          isActive: i == widget.currentIndex,
                          onTap: () => widget.onSelect(i),
                          showLabel: showLabels,
                        ),
                      ),
                  ],
                ),
                AnimatedBuilder(
                  animation: _ctrl,
                  builder: (context, _) {
                    final indicatorWidth = 32.0;
                    final centerX = tabWidth * (_ctrl.value + 0.5);
                    return Positioned(
                      left: centerX - indicatorWidth / 2,
                      top: 12,
                      width: indicatorWidth,
                      child: Container(
                        height: 3,
                        decoration: BoxDecoration(
                          color: AfColors.textPrimary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final AfBottomNavItem item;
  final bool isActive;
  final bool showLabel;
  final VoidCallback onTap;

  const _Tab({
    required this.item,
    required this.isActive,
    required this.onTap,
    required this.showLabel,
  });

  @override
  Widget build(BuildContext context) {
    return PressScale(
      ensureHitTarget: false,
      onTap: onTap,
      child: SizedBox(
        height: AfSpacing.bottomNavHeight,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 8),
            AnimatedSwitcher(
              duration: AfDurations.instant,
              child: Icon(
                isActive ? item.filledIcon : item.icon,
                key: ValueKey(isActive),
                size: 24,
                color: isActive ? AfColors.textPrimary : AfColors.textTertiary,
                semanticLabel: showLabel ? null : item.label,
              ),
            ),
            if (showLabel) ...[
              const SizedBox(height: 4),
              Text(
                item.label,
                style: AfTypography.caption.copyWith(
                  color: isActive
                      ? AfColors.textPrimary
                      : AfColors.textTertiary,
                ),
              ),
            ] else
              const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}
