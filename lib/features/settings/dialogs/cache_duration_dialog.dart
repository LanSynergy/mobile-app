import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show Cache;

import '../../../core/audio/player_settings_store.dart';
import '../../../design_tokens/tokens.dart';
import '../../../state/providers.dart';
import '../../../widgets/bottom_sheet.dart';
import '../settings_widgets.dart';

void showCacheDurationDialog(BuildContext context, WidgetRef ref) {
  const options = <(int, String)>[
    (10, '10 seconds'),
    (30, '30 seconds (default)'),
    (60, '1 minute'),
    (120, '2 minutes'),
    (300, '5 minutes'),
  ];

  final currentSecs = ref
      .read(playerServiceProvider)
      .cacheSettings
      .secs
      .inSeconds;
  final effectiveSecs = currentSecs > 0 ? currentSecs : 30;

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
          child: Text('Cache duration', style: AfTypography.titleSmall),
        ),
        const SizedBox(height: AfSpacing.s4),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AfSpacing.gutterGenerous,
          ),
          child: Text(
            'How far ahead to buffer audio from the server.',
            style: AfTypography.bodySmall.copyWith(
              color: AfColors.textTertiary,
            ),
          ),
        ),
        const SizedBox(height: AfSpacing.s8),
        for (final (secs, label) in options)
          OptionTile(
            label: label,
            isActive: secs == effectiveSecs,
            onTap: () {
              final svc = ref.read(playerServiceProvider);
              unawaited(
                svc.setCache(
                  svc.cacheSettings.copyWith(
                    mode: Cache.yes,
                    secs: Duration(seconds: secs),
                  ),
                ),
              );
              unawaited(PlayerSettingsStore.saveCacheSecs(secs));
              dismiss();
            },
          ),
      ],
    ),
  );
}
