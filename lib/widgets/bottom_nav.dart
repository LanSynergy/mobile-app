import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_tokens/tokens.dart';
import 'press_scale.dart';

const _navBg = Color(0xB30B0B14);

/// Google-style bottom navigation bar.
///
/// Per §7.7:
///   - 4 destinations only.
///   - 72dp height (excluding gesture inset).
///   - Active tab shows a colored pill background behind icon + label.
///   - Pill slides between tabs with 240ms `easeStandard` animation.
///   - Inactive tabs show icon only; label appears only on the active tab.
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
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final topRadius = 24.0;

    return ClipRRect(
      borderRadius: BorderRadius.vertical(top: Radius.circular(topRadius)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: const BoxDecoration(
            color: _navBg,
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
                    // Sliding pill background for active tab.
                    AnimatedBuilder(
                      animation: _ctrl,
                      builder: (context, _) {
                        final pillWidth = 96.0; // Wider to fit label
                        final centerX = tabWidth * (_ctrl.value + 0.5);
                        return Positioned(
                          left: centerX - pillWidth / 2,
                          top: 12,
                          width: pillWidth,
                          height: 48,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AfColors.indigo900,
                              borderRadius: AfRadii.borderPill,
                            ),
                          ),
                        );
                      },
                    ),
                    // Tab buttons.
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        for (var i = 0; i < widget.items.length; i++)
                          Expanded(
                            child: _Tab(
                              item: widget.items[i],
                              isActive: i == widget.currentIndex,
                              onTap: () => widget.onSelect(i),
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final AfBottomNavItem item;
  final bool isActive;
  final VoidCallback onTap;

  const _Tab({
    required this.item,
    required this.isActive,
    required this.onTap,
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
            AnimatedSwitcher(
              duration: AfDurations.instant,
              child: Icon(
                isActive ? item.filledIcon : item.icon,
                key: ValueKey(isActive),
                size: 24,
                color: isActive ? AfColors.textPrimary : AfColors.textTertiary,
                semanticLabel: null,
              ),
            ),
            if (isActive) ...[
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
