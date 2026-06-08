import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/player_settings_store.dart';
import '../../../design_tokens/tokens.dart';
import '../../../state/providers.dart';
import '../../../widgets/bottom_sheet.dart';
import '../settings_widgets.dart';

void showSampleRateDialog(BuildContext context, WidgetRef ref) {
  const rates = <int>[0, 44100, 48000, 88200, 96000, 192000];

  final svc = ref.read(playerServiceProvider);
  final actualRate = svc.audioOutParams.sampleRate ?? 0;

  final labels = <int, String>{
    0: actualRate > 0
        ? 'Auto (currently ${(actualRate / 1000).toStringAsFixed(1)} kHz)'
        : 'Auto (default)',
    44100: '44.1 kHz (CD)',
    48000: '48 kHz (DVD)',
    88200: '88.2 kHz (Hi-Res)',
    96000: '96 kHz (Hi-Res)',
    192000: '192 kHz (Studio)',
  };

  final isForced = rates.contains(actualRate) && actualRate != 0;
  final activeRate = isForced ? actualRate : 0;

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
          child: Text('Sample rate', style: AfTypography.titleSmall),
        ),
        const SizedBox(height: AfSpacing.s8),
        for (final rate in rates)
          OptionTile(
            label: labels[rate]!,
            subtitle: rate == 0 ? 'Matches the source file' : null,
            isActive: rate == activeRate,
            onTap: () {
              unawaited(
                ref.read(playerServiceProvider).setAudioSampleRate(rate),
              );
              unawaited(PlayerSettingsStore.saveSampleRate(rate));
              dismiss();
            },
          ),
      ],
    ),
  );
}
