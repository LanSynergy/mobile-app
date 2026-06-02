import 'package:flutter/material.dart';

import '../../design_tokens/tokens.dart';

class SettingsLabel extends StatelessWidget {
  const SettingsLabel(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AfSpacing.s16,
        0,
        AfSpacing.s4,
        AfSpacing.s8,
      ),
      child: Text(
        label,
        style: AfTypography.bodySmall.copyWith(
          color: AfColors.textTertiary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class SettingsGroup extends StatelessWidget {
  const SettingsGroup({required this.children, super.key});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: AfColors.surfaceBase,
        borderRadius: AfRadii.borderLg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              const Divider(
                height: 0,
                thickness: 0.5,
                indent: 64,
                color: AfColors.surfaceHigh,
              ),
          ],
        ],
      ),
    );
  }
}

class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AfSpacing.s16,
          vertical: AfSpacing.s12,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                // ignore: deprecated_member_use
                color: iconColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: iconColor),
            ),
            const SizedBox(width: AfSpacing.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: AfTypography.bodyMedium),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle!,
                        style: AfTypography.bodySmall.copyWith(
                          color: AfColors.textTertiary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: AfSpacing.s8),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

class SettingsSwitchTile extends StatelessWidget {
  const SettingsSwitchTile({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AfSpacing.s16,
          vertical: AfSpacing.s12,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                // ignore: deprecated_member_use
                color: iconColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: iconColor),
            ),
            const SizedBox(width: AfSpacing.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: AfTypography.bodyMedium),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle!,
                        style: AfTypography.bodySmall.copyWith(
                          color: AfColors.textTertiary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AfSpacing.s8),
            Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeTrackColor: AfColors.accentPrimary,
            ),
          ],
        ),
      ),
    );
  }
}

class OptionTile extends StatelessWidget {
  const OptionTile({
    super.key,
    required this.label,
    this.subtitle,
    required this.isActive,
    required this.onTap,
  });
  final String label;
  final String? subtitle;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AfSpacing.gutterGenerous,
          vertical: AfSpacing.s12,
        ),
        child: Row(
          children: [
            Container(
              width: 3,
              height: subtitle != null ? 28 : 20,
              decoration: BoxDecoration(
                color: isActive ? AfColors.accentPrimary : Colors.transparent,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
            const SizedBox(width: AfSpacing.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: AfTypography.bodyMedium.copyWith(
                      color: isActive
                          ? AfColors.accentPrimary
                          : AfColors.textPrimary,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle!,
                        style: AfTypography.bodySmall.copyWith(
                          color: AfColors.textTertiary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
