import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_tokens/tokens.dart';
import '../../../state/providers.dart';
import '../../../widgets/bottom_sheet.dart';
import '../settings_widgets.dart';

void showAppIconDialog(BuildContext context, WidgetRef ref) {
  final currentIcon = ref.read(appIconProvider);

  final options = <(String, String, String)>[
    ('DefaultIcon', 'Default', 'Standard Aurora Purple themed icon'),
    ('MidnightIcon', 'Midnight', 'Sleek dark themed icon'),
    ('NordicIcon', 'Nordic', 'Cool ocean blue themed icon'),
    ('SunsetIcon', 'Sunset', 'Warm sunset red/amber themed icon'),
  ];

  showBlurBottomSheet<void>(
    context: context,
    builder: (context, dismiss) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AfSpacing.gutterGenerous,
          ),
          child: Text('App icon', style: AfTypography.titleSmall),
        ),
        const SizedBox(height: AfSpacing.s4),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AfSpacing.gutterGenerous,
          ),
          child: Text(
            "Choose a custom theme for Aetherfin's launcher icon.",
            style: AfTypography.bodySmall.copyWith(
              color: AfColors.textTertiary,
            ),
          ),
        ),
        const SizedBox(height: AfSpacing.s8),
        for (final (iconName, label, description) in options)
          OptionTile(
            label: label,
            subtitle: description,
            isActive: iconName == currentIcon,
            onTap: () {
              unawaited(ref.read(appIconProvider.notifier).setIcon(iconName));
              dismiss();
            },
          ),
      ],
    ),
  );
}
