import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart'
    show ReplayGain, ReplayGainSettings;

import '../../../core/audio/player_settings_store.dart';
import '../../../design_tokens/tokens.dart';
import '../../../state/providers.dart';
import '../../../widgets/bottom_sheet.dart';
import '../settings_widgets.dart';

void showReplayGainDialog(BuildContext context, WidgetRef ref) {
  showBlurBottomSheet<void>(
    context: context,
    builder: (context, dismiss) => const ReplayGainDialogContent(),
  );
}

class ReplayGainDialogContent extends ConsumerStatefulWidget {
  const ReplayGainDialogContent({super.key});
  @override
  ConsumerState<ReplayGainDialogContent> createState() =>
      _ReplayGainDialogContentState();
}

class _ReplayGainDialogContentState
    extends ConsumerState<ReplayGainDialogContent> {
  late ReplayGain _mode;
  late double _preamp;
  late double _fallback;
  late bool _clip;

  @override
  void initState() {
    super.initState();
    final rg = ref.read(playerServiceProvider).replayGain;
    _mode = rg.mode;
    _preamp = rg.preamp.clamp(-15.0, 15.0);
    _fallback = rg.fallback.clamp(-15.0, 0.0);
    _clip = rg.clip;
  }

  void _apply() {
    final svc = ref.read(playerServiceProvider);
    final settings = ReplayGainSettings(
      mode: _mode,
      preamp: _preamp,
      fallback: _fallback,
      clip: _clip,
    );
    unawaited(svc.setReplayGain(settings));
    unawaited(PlayerSettingsStore.saveReplayGainFull(settings));
  }

  @override
  Widget build(BuildContext context) {
    final spectral = ref.watch(
      currentSpectralProvider.select((s) => s.primary),
    );
    const options = <(ReplayGain, String, String)>[
      (ReplayGain.no, 'Off', 'No volume normalization'),
      (ReplayGain.track, 'Track', 'Normalize each track independently'),
      (ReplayGain.album, 'Album', 'Normalize per album (preserves dynamics)'),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AfSpacing.gutterGenerous,
          ),
          child: Text('ReplayGain', style: AfTypography.titleSmall),
        ),
        const SizedBox(height: AfSpacing.s4),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AfSpacing.gutterGenerous,
          ),
          child: Text(
            'Normalize volume so all tracks play at a similar loudness.',
            style: AfTypography.bodySmall.copyWith(
              color: AfColors.textTertiary,
            ),
          ),
        ),
        const SizedBox(height: AfSpacing.s8),
        for (final (mode, label, subtitle) in options)
          OptionTile(
            label: label,
            subtitle: subtitle,
            isActive: mode == _mode,
            onTap: () {
              setState(() => _mode = mode);
              _apply();
            },
          ),
        if (_mode != ReplayGain.no) ...[
          const SizedBox(height: AfSpacing.s8),
          const Divider(height: 1, color: AfColors.surfaceHigh),
          const SizedBox(height: AfSpacing.s8),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AfSpacing.gutterGenerous,
            ),
            child: Row(
              children: [
                Text('Pre-amp', style: AfTypography.bodyMedium),
                const Spacer(),
                Text(
                  '${_preamp >= 0 ? "+" : ""}${_preamp.toStringAsFixed(1)} dB',
                  style: AfTypography.mono.copyWith(
                    color: AfColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AfSpacing.gutterGenerous,
            ),
            child: Slider(
              value: _preamp,
              min: -15,
              max: 15,
              divisions: 30,
              activeColor: spectral,
              onChanged: (v) => setState(() => _preamp = v),
              onChangeEnd: (_) => _apply(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AfSpacing.gutterGenerous,
            ),
            child: Row(
              children: [
                Text('Fallback gain', style: AfTypography.bodyMedium),
                const Spacer(),
                Text(
                  '${_fallback.toStringAsFixed(1)} dB',
                  style: AfTypography.mono.copyWith(
                    color: AfColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AfSpacing.gutterGenerous,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Slider(
                  value: _fallback,
                  min: -15,
                  max: 0,
                  divisions: 30,
                  activeColor: spectral,
                  onChanged: (v) => setState(() => _fallback = v),
                  onChangeEnd: (_) => _apply(),
                ),
                Text(
                  'Applied to files without ReplayGain tags',
                  style: AfTypography.caption.copyWith(
                    color: AfColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AfSpacing.gutterGenerous,
            ),
            child: SwitchListTile.adaptive(
              value: !_clip,
              onChanged: (v) {
                setState(() => _clip = !v);
                _apply();
              },
              title: Text('Prevent clipping', style: AfTypography.bodyMedium),
              subtitle: Text(
                'Peak-limit output to avoid distortion',
                style: AfTypography.bodySmall.copyWith(
                  color: AfColors.textTertiary,
                ),
              ),
              activeThumbColor: spectral,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ],
    );
  }
}
