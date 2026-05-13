import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show AudioParams, Cache, Format;

import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _exclusiveMode = false;
  bool _audioStreamSilence = false;
  int _audioBufferMs = 200; // default

  void _setAudioBuffer(int ms) => setState(() => _audioBufferMs = ms);

  @override
  Widget build(BuildContext context) {
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
                final rate = params?.sampleRate;
                final fmt = params?.format;
                final ch = params?.channelCount;
                final hasData = rate != null && rate > 0;
                return ListTile(
                  leading: const Icon(Icons.graphic_eq_rounded),
                  title: const Text('Current output'),
                  subtitle: Text(
                    hasData
                        ? '$rate Hz · ${fmt?.name ?? "auto"} · ${ch}ch'
                        : 'Not active — start playback first',
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
              value: _exclusiveMode,
              onChanged: (v) {
                setState(() => _exclusiveMode = v);
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
            _SectionLabel('Network & cache'),
            ListTile(
              leading: const Icon(Icons.cached_rounded),
              title: const Text('Cache duration'),
              subtitle: Text(
                'How far ahead to buffer',
                style: AfTypography.bodySmall.copyWith(
                  color: AfColors.textTertiary,
                ),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              tileColor: AfColors.surfaceBase,
              shape: const RoundedRectangleBorder(
                  borderRadius: AfRadii.borderMd),
              onTap: () => _showCacheDurationDialog(context, ref),
            ),
            const SizedBox(height: AfSpacing.s8),
            ListTile(
              leading: const Icon(Icons.storage_rounded),
              title: const Text('Buffer size'),
              subtitle: Text(
                'Audio hardware buffer (latency vs stability)',
                style: AfTypography.bodySmall.copyWith(
                  color: AfColors.textTertiary,
                ),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              tileColor: AfColors.surfaceBase,
              shape: const RoundedRectangleBorder(
                  borderRadius: AfRadii.borderMd),
              onTap: () => _showAudioBufferDialog(context, ref),
            ),
            const SizedBox(height: AfSpacing.s8),
            SwitchListTile.adaptive(
              value: _audioStreamSilence,
              onChanged: (v) {
                setState(() => _audioStreamSilence = v);
                unawaited(
                    ref.read(playerServiceProvider).setAudioStreamSilence(v));
              },
              title: const Text('Keep audio active on pause'),
              subtitle: Text(
                'Eliminates click/pop on resume. Uses more battery.',
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

  final currentRate = ref.read(playerServiceProvider).audioOutParams.sampleRate ?? 0;

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
              _OptionTile(
                label: labels[rate]!,
                isActive: rate == currentRate || (rate == 0 && currentRate == 0),
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

  final currentFormat = ref.read(playerServiceProvider).audioOutParams.format;

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
              _OptionTile(
                label: label,
                isActive: format == currentFormat ||
                    (format == Format.auto && currentFormat == null),
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

void _showCacheDurationDialog(BuildContext context, WidgetRef ref) {
  const options = <(int, String)>[
    (10, '10 seconds'),
    (30, '30 seconds (default)'),
    (60, '1 minute'),
    (120, '2 minutes'),
    (300, '5 minutes'),
  ];

  final currentSecs = ref.read(playerServiceProvider).cacheSettings.secs.inSeconds;
  // If the player hasn't been configured yet, default highlights "30 seconds".
  final effectiveSecs = currentSecs > 0 ? currentSecs : 30;

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
              child: Text('Cache duration', style: AfTypography.titleSmall),
            ),
            const SizedBox(height: AfSpacing.s4),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AfSpacing.gutterGenerous),
              child: Text(
                'How far ahead to buffer audio from the server.',
                style: AfTypography.bodySmall
                    .copyWith(color: AfColors.textTertiary),
              ),
            ),
            const SizedBox(height: AfSpacing.s8),
            for (final (secs, label) in options)
              _OptionTile(
                label: label,
                isActive: secs == effectiveSecs,
                onTap: () {
                  final svc = ref.read(playerServiceProvider);
                  unawaited(svc.setCache(
                    svc.cacheSettings.copyWith(
                      mode: Cache.yes,
                      secs: Duration(seconds: secs),
                    ),
                  ));
                  Navigator.of(dialogCtx).pop();
                },
              ),
          ],
        ),
      ),
    ),
  );
}

void _showAudioBufferDialog(BuildContext context, WidgetRef ref) {
  const options = <(int, String)>[
    (50, '50 ms (low latency)'),
    (100, '100 ms'),
    (200, '200 ms (default)'),
    (500, '500 ms (stable)'),
    (1000, '1000 ms (very stable)'),
  ];

  // Read from the enclosing state.
  final state = context.findAncestorStateOfType<_SettingsScreenState>();
  final currentMs = state?._audioBufferMs ?? 200;

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
              child: Text('Audio buffer', style: AfTypography.titleSmall),
            ),
            const SizedBox(height: AfSpacing.s4),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AfSpacing.gutterGenerous),
              child: Text(
                'Lower = less latency. Higher = more stable on slow networks.',
                style: AfTypography.bodySmall
                    .copyWith(color: AfColors.textTertiary),
              ),
            ),
            const SizedBox(height: AfSpacing.s8),
            for (final (ms, label) in options)
              _OptionTile(
                label: label,
                isActive: ms == currentMs,
                onTap: () {
                  state?._setAudioBuffer(ms);
                  unawaited(ref.read(playerServiceProvider).setAudioBuffer(
                        Duration(milliseconds: ms),
                      ));
                  Navigator.of(dialogCtx).pop();
                },
              ),
          ],
        ),
      ),
    ),
  );
}

/// A dialog option row with an accented vertical line on the left when active.
class _OptionTile extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _OptionTile({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

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
            // Accented vertical line indicator.
            Container(
              width: 3,
              height: 20,
              decoration: BoxDecoration(
                color: isActive ? AfColors.indigo400 : Colors.transparent,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
            const SizedBox(width: AfSpacing.s12),
            Expanded(
              child: Text(
                label,
                style: AfTypography.bodyMedium.copyWith(
                  color: isActive ? AfColors.indigo300 : AfColors.textPrimary,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
