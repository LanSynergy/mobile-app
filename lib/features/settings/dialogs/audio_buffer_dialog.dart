import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/player_settings_store.dart';
import '../../../design_tokens/tokens.dart';
import '../../../state/providers.dart';
import '../../../widgets/bottom_sheet.dart';
import '../settings_widgets.dart';

void showAudioBufferDialog(BuildContext context, WidgetRef ref) {
  const options = <(int, String)>[
    (50, '50 ms (low latency)'),
    (100, '100 ms'),
    (200, '200 ms (default)'),
    (500, '500 ms (stable)'),
    (1000, '1000 ms (very stable)'),
  ];

  final currentMs = ref.read(playerServiceProvider).audioBuffer.inMilliseconds;
  final effectiveMs = currentMs > 0 ? currentMs : 200;

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
          child: Text('Audio buffer', style: AfTypography.titleSmall),
        ),
        const SizedBox(height: AfSpacing.s4),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AfSpacing.gutterGenerous,
          ),
          child: Text(
            'Lower = less latency. Higher = more stable on slow networks.',
            style: AfTypography.bodySmall.copyWith(
              color: AfColors.textTertiary,
            ),
          ),
        ),
        const SizedBox(height: AfSpacing.s8),
        for (final (ms, label) in options)
          OptionTile(
            label: label,
            isActive: ms == effectiveMs,
            onTap: () {
              unawaited(
                ref
                    .read(playerServiceProvider)
                    .setAudioBuffer(Duration(milliseconds: ms)),
              );
              unawaited(PlayerSettingsStore.saveBufferMs(ms));
              dismiss();
            },
          ),
      ],
    ),
  );
}
