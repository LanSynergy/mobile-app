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

class _AfBottomNavState extends ConsumerState<AfBottomNav> {
  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final alignLeft =
                    widget.currentIndex < widget.items.length ~/ 2;
                final pillLeft = alignLeft ? AfSpacing.s12 : width - 120 - AfSpacing.s12;

                return Stack(
                  children: [
                    // Sliding pill background for active tab.
                    AnimatedPositioned(
                      duration: AfDurations.standard,
                      curve: AfCurves.easeStandard,
                      left: pillLeft,
                      top: 12,
                      width: 120,
                      height: 48,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AfColors.indigo900,
                          borderRadius: AfRadii.borderPill,
                        ),
                      ),
                    ),
                    // Tab buttons: active tab shifts to edge, others cluster.
                    _buildDynamicLayout(context),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDynamicLayout(BuildContext context) {
    final activeIdx = widget.currentIndex;
    final activeItem = widget.items[activeIdx];
    final inactiveItems = <(int, AfBottomNavItem)>[];
    for (var i = 0; i < widget.items.length; i++) {
      if (i != activeIdx) {
        inactiveItems.add((i, widget.items[i]));
      }
    }

    final alignLeft = activeIdx < widget.items.length ~/ 2;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s12),
      child: Row(
        mainAxisAlignment:
            alignLeft ? MainAxisAlignment.start : MainAxisAlignment.end,
        children: [
          if (!alignLeft)
            ...inactiveItems.map((e) => _buildInactiveTab(e.$1, e.$2)),
          _buildActiveTab(activeIdx, activeItem),
          if (alignLeft)
            ...inactiveItems.map((e) => _buildInactiveTab(e.$1, e.$2)),
        ],
      ),
    );
  }

  Widget _buildActiveTab(int index, AfBottomNavItem item) {
    return PressScale(
      ensureHitTarget: false,
      onTap: () => widget.onSelect(index),
      child: SizedBox(
        height: AfSpacing.bottomNavHeight,
        width: 120,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedSwitcher(
              duration: AfDurations.instant,
              child: Icon(
                item.filledIcon,
                key: const ValueKey('filled'),
                size: 24,
                color: AfColors.textPrimary,
                semanticLabel: null,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AfTypography.caption.copyWith(
                  color: AfColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInactiveTab(int index, AfBottomNavItem item) {
    return PressScale(
      ensureHitTarget: false,
      onTap: () => widget.onSelect(index),
      child: SizedBox(
        height: AfSpacing.bottomNavHeight,
        width: 72,
        child: Center(
          child: AnimatedSwitcher(
            duration: AfDurations.instant,
            child: Icon(
              item.icon,
              key: const ValueKey('outline'),
              size: 24,
              color: AfColors.textTertiary,
              semanticLabel: null,
            ),
          ),
        ),
      ),
    );
  }
}
