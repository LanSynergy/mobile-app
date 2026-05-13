import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show AudioParams, Format;

import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final showLabels = ref.watch(showNavLabelsProvider);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: Text('Settings', style: AfTypography.titleMedium),
      ),
      body: SafeArea(
        child: ListView(
          padding:
              const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
          children: [
            _SectionLabel('Server'),
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: Text(auth?.server.name ?? 'Not connected'),
              subtitle: auth == null
                  ? null
                  : Text(
                      auth.server.baseUrl,
                      style: AfTypography.bodySmall.copyWith(
                        color: AfColors.textTertiary,
                      ),
                    ),
              trailing: const Icon(Icons.chevron_right_rounded),
              tileColor: AfColors.surfaceBase,
              shape: const RoundedRectangleBorder(
                  borderRadius: AfRadii.borderMd),
              onTap: () => context.go('/onboarding/discover'),
            ),
            const SizedBox(height: AfSpacing.s24),
            _SectionLabel('Appearance'),
            SwitchListTile.adaptive(
              value: showLabels,
              onChanged: (v) =>
                  ref.read(showNavLabelsProvider.notifier).state = v,
              title: const Text('Always show tab labels'),
              subtitle: Text(
                'Default is icon-only with the active capsule indicator.',
                style: AfTypography.bodySmall.copyWith(
                  color: AfColors.textTertiary,
                ),
              ),
              activeThumbColor: AfColors.indigo500,
              tileColor: AfColors.surfaceBase,
              shape: const RoundedRectangleBorder(
                  borderRadius: AfRadii.borderMd),
            ),
            const SizedBox(height: AfSpacing.s24),
            _SectionLabel('Audio output'),
            StreamBuilder<AudioParams>(
              stream: ref.read(playerServiceProvider).audioOutParamsStream,
              initialData: ref.read(playerServiceProvider).audioOutParams,
              builder: (context, snap) {
                final params = snap.data;
                return ListTile(
                  leading: const Icon(Icons.graphic_eq_rounded),
                  title: const Text('Current output'),
                  subtitle: Text(
                    params != null
                        ? '${params.sampleRate} Hz · ${params.format?.name ?? "auto"} · ${params.channelCount}ch'
                        : 'Not active',
                    style: AfTypography.bodySmall.copyWith(
                      color: AfColors.textTertiary,
                    ),
                  ),
                  tileColor: AfColors.surfaceBase,
                  shape: const RoundedRectangleBorder(
                      borderRadius: AfRadii.borderMd),
                );
              },
            ),
            const SizedBox(height: AfSpacing.s8),
            ListTile(
              leading: const Icon(Icons.speed_rounded),
              title: const Text('Sample rate'),
              subtitle: Text(
                'Force output sample rate for DAC',
                style: AfTypography.bodySmall.copyWith(
                  color: AfColors.textTertiary,
                ),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              tileColor: AfColors.surfaceBase,
              shape: const RoundedRectangleBorder(
                  borderRadius: AfRadii.borderMd),
              onTap: () => _showSampleRateDialog(context, ref),
            ),
            const SizedBox(height: AfSpacing.s8),
            ListTile(
              leading: const Icon(Icons.memory_rounded),
              title: const Text('Bit depth'),
              subtitle: Text(
                'Force output format',
                style: AfTypography.bodySmall.copyWith(
                  color: AfColors.textTertiary,
                ),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              tileColor: AfColors.surfaceBase,
              shape: const RoundedRectangleBorder(
                  borderRadius: AfRadii.borderMd),
              onTap: () => _showFormatDialog(context, ref),
            ),
            const SizedBox(height: AfSpacing.s8),
            SwitchListTile.adaptive(
              value: false, // Read from player state if needed
              onChanged: (v) {
                unawaited(ref.read(playerServiceProvider).setAudioExclusive(v));
              },
              title: const Text('Exclusive mode'),
              subtitle: Text(
                'Bypass OS mixer for bit-perfect output. May not work on all devices.',
                style: AfTypography.bodySmall.copyWith(
                  color: AfColors.textTertiary,
                ),
              ),
              activeThumbColor: AfColors.indigo500,
              tileColor: AfColors.surfaceBase,
              shape: const RoundedRectangleBorder(
                  borderRadius: AfRadii.borderMd),
            ),
            const SizedBox(height: AfSpacing.s24),
            _SectionLabel('About'),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('Aetherfin v0.1.0'),
              subtitle: Text(
                'Jellyfin-backed music player. FOSS.',
                style: AfTypography.bodySmall.copyWith(
                  color: AfColors.textTertiary,
                ),
              ),
              tileColor: AfColors.surfaceBase,
              shape: const RoundedRectangleBorder(
                  borderRadius: AfRadii.borderMd),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AfSpacing.s4, AfSpacing.s8, AfSpacing.s4, AfSpacing.s8),
      child: Text(
        label.toUpperCase(),
        style: AfTypography.label.copyWith(
          color: AfColors.textTertiary,
        ),
      ),
    );
  }
}

void _showSampleRateDialog(BuildContext context, WidgetRef ref) {
  const rates = <int>[0, 44100, 48000, 88200, 96000, 192000];
  const labels = <int, String>{
    0: 'Auto (default)',
    44100: '44.1 kHz (CD)',
    48000: '48 kHz (DVD)',
    88200: '88.2 kHz (Hi-Res)',
    96000: '96 kHz (Hi-Res)',
    192000: '192 kHz (Studio)',
  };

  showDialog<void>(
    context: context,
    builder: (dialogCtx) => Dialog(
      backgroundColor: AfColors.surfaceBase,
      shape: RoundedRectangleBorder(borderRadius: AfRadii.borderLg),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AfSpacing.s16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AfSpacing.gutterGenerous),
              child: Text('Sample rate', style: AfTypography.titleSmall),
            ),
            const SizedBox(height: AfSpacing.s8),
            for (final rate in rates)
              ListTile(
                title: Text(labels[rate]!, style: AfTypography.bodyMedium),
                onTap: () {
                  unawaited(
                      ref.read(playerServiceProvider).setAudioSampleRate(rate));
                  Navigator.of(dialogCtx).pop();
                },
              ),
          ],
        ),
      ),
    ),
  );
}

void _showFormatDialog(BuildContext context, WidgetRef ref) {
  const formats = <(Format, String)>[
    (Format.auto, 'Auto (default)'),
    (Format.s16, '16-bit signed'),
    (Format.s32, '32-bit signed'),
    (Format.float32, '32-bit float'),
    (Format.float64, '64-bit float'),
  ];

  showDialog<void>(
    context: context,
    builder: (dialogCtx) => Dialog(
      backgroundColor: AfColors.surfaceBase,
      shape: RoundedRectangleBorder(borderRadius: AfRadii.borderLg),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AfSpacing.s16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AfSpacing.gutterGenerous),
              child: Text('Bit depth', style: AfTypography.titleSmall),
            ),
            const SizedBox(height: AfSpacing.s8),
            for (final (format, label) in formats)
              ListTile(
                title: Text(label, style: AfTypography.bodyMedium),
                onTap: () {
                  unawaited(
                      ref.read(playerServiceProvider).setAudioFormat(format));
                  Navigator.of(dialogCtx).pop();
                },
              ),
          ],
        ),
      ),
    ),
  );
}
