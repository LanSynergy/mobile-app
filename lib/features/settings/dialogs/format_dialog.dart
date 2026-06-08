import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show Format;

import '../../../core/audio/player_settings_store.dart';
import '../../../design_tokens/tokens.dart';
import '../../../state/providers.dart';
import '../../../widgets/bottom_sheet.dart';
import '../settings_widgets.dart';

void showFormatDialog(BuildContext context, WidgetRef ref) {
  final currentFormat = ref.read(playerServiceProvider).audioOutParams.format;
  final formatName = currentFormat?.name ?? 'auto';
  final activeFormat = currentFormat ?? Format.auto;

  final formats = <(Format, String)>[
    (
      Format.auto,
      currentFormat != null ? 'Auto (currently $formatName)' : 'Auto (default)',
    ),
    (Format.s16, '16-bit signed'),
    (Format.s32, '32-bit signed'),
    (Format.float32, '32-bit float'),
    (Format.float64, '64-bit float'),
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
          child: Text('Bit depth', style: AfTypography.titleSmall),
        ),
        const SizedBox(height: AfSpacing.s8),
        for (final (format, label) in formats)
          OptionTile(
            label: label,
            subtitle: format == Format.auto ? 'Matches the source file' : null,
            isActive: format == activeFormat,
            onTap: () {
              unawaited(ref.read(playerServiceProvider).setAudioFormat(format));
              unawaited(PlayerSettingsStore.saveFormat(format));
              dismiss();
            },
          ),
      ],
    ),
  );
}
