import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart'
    show AudioParams, Cache, Format, Gapless, ReplayGain, ReplayGainSettings;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/audio/player_settings_store.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final showLabels = ref.watch(showNavLabelsProvider);
    final svc = ref.read(playerServiceProvider);
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
            StreamBuilder<bool>(
              stream: svc.audioExclusiveStream,
              initialData: svc.audioExclusive,
              builder: (context, snap) {
                final enabled = snap.data ?? false;
                return SwitchListTile.adaptive(
                  value: enabled,
                  onChanged: (v) {
                    unawaited(svc.setAudioExclusive(v));
                    unawaited(PlayerSettingsStore.saveExclusive(v));
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
                );
              },
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
            StreamBuilder<bool>(
              stream: svc.audioStreamSilenceStream,
              initialData: svc.audioStreamSilence,
              builder: (context, snap) {
                final enabled = snap.data ?? false;
                return SwitchListTile.adaptive(
                  value: enabled,
                  onChanged: (v) {
                    unawaited(svc.setAudioStreamSilence(v));
                    unawaited(PlayerSettingsStore.saveStreamSilence(v));
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
                );
              },
            ),
            const SizedBox(height: AfSpacing.s24),
            _SectionLabel('Audio processing'),
            ListTile(
              leading: const Icon(Icons.equalizer_rounded),
              title: const Text('ReplayGain'),
              subtitle: Text(
                'Volume normalization across tracks',
                style: AfTypography.bodySmall.copyWith(
                  color: AfColors.textTertiary,
                ),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              tileColor: AfColors.surfaceBase,
              shape: const RoundedRectangleBorder(
                  borderRadius: AfRadii.borderMd),
              onTap: () => _showReplayGainDialog(context, ref),
            ),
            const SizedBox(height: AfSpacing.s8),
            ListTile(
              leading: const Icon(Icons.skip_next_rounded),
              title: const Text('Gapless playback'),
              subtitle: Text(
                'Seamless transitions between tracks',
                style: AfTypography.bodySmall.copyWith(
                  color: AfColors.textTertiary,
                ),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              tileColor: AfColors.surfaceBase,
              shape: const RoundedRectangleBorder(
                  borderRadius: AfRadii.borderMd),
              onTap: () => _showGaplessDialog(context, ref),
            ),
            const SizedBox(height: AfSpacing.s8),
            StreamBuilder<bool>(
              stream: Stream<bool>.multi((controller) {
                controller.add(svc.prefetchPlaylist);
              }),
              initialData: svc.prefetchPlaylist,
              builder: (context, snap) {
                final enabled = snap.data ?? false;
                return SwitchListTile.adaptive(
                  value: enabled,
                  onChanged: (v) {
                    unawaited(svc.setPrefetchPlaylist(v));
                    unawaited(PlayerSettingsStore.savePrefetchPlaylist(v));
                  },
                  title: const Text('Prefetch next track'),
                  subtitle: Text(
                    'Pre-load next playlist entry in background',
                    style: AfTypography.bodySmall.copyWith(
                      color: AfColors.textTertiary,
                    ),
                  ),
                  activeThumbColor: AfColors.indigo500,
                  tileColor: AfColors.surfaceBase,
                  shape: const RoundedRectangleBorder(
                      borderRadius: AfRadii.borderMd),
                );
              },
            ),
            const SizedBox(height: AfSpacing.s24),
            _SectionLabel('About'),
            FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snap) {
                final version = snap.data != null
                    ? 'v${snap.data!.version} (${snap.data!.buildNumber})'
                    : '...';
                return ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: Text('Aetherfin $version'),
                  subtitle: Text(
                    'Jellyfin-backed music player. FOSS.',
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
              leading: const Icon(Icons.code_rounded),
              title: const Text('Source code'),
              subtitle: Text(
                'github.com/Aetherfin/mobile-app',
                style: AfTypography.bodySmall.copyWith(
                  color: AfColors.textTertiary,
                ),
              ),
              trailing: const Icon(Icons.open_in_new_rounded, size: 18),
              tileColor: AfColors.surfaceBase,
              shape: const RoundedRectangleBorder(
                  borderRadius: AfRadii.borderMd),
              onTap: () => _launchUrl('https://github.com/Aetherfin/mobile-app'),
            ),
            const SizedBox(height: AfSpacing.s8),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Licenses'),
              subtitle: Text(
                'Open-source licenses',
                style: AfTypography.bodySmall.copyWith(
                  color: AfColors.textTertiary,
                ),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              tileColor: AfColors.surfaceBase,
              shape: const RoundedRectangleBorder(
                  borderRadius: AfRadii.borderMd),
              onTap: () => showLicensePage(
                context: context,
                applicationName: 'Aetherfin',
                applicationLegalese: '© 2025 Aetherfin contributors',
              ),
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
                  unawaited(PlayerSettingsStore.saveSampleRate(rate));
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
                  unawaited(PlayerSettingsStore.saveFormat(format));
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
                  unawaited(PlayerSettingsStore.saveCacheSecs(secs));
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

  final currentMs = ref.read(playerServiceProvider).audioBuffer.inMilliseconds;
  // Default is 200ms if the player reports 0.
  final effectiveMs = currentMs > 0 ? currentMs : 200;

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
                isActive: ms == effectiveMs,
                onTap: () {
                  unawaited(ref.read(playerServiceProvider).setAudioBuffer(
                        Duration(milliseconds: ms),
                      ));
                  unawaited(PlayerSettingsStore.saveBufferMs(ms));
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
  final String? subtitle;
  final bool isActive;
  final VoidCallback onTap;

  const _OptionTile({
    required this.label,
    this.subtitle,
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
              height: subtitle != null ? 28 : 20,
              decoration: BoxDecoration(
                color: isActive ? AfColors.indigo400 : Colors.transparent,
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
                          ? AfColors.indigo300
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

void _showGaplessDialog(BuildContext context, WidgetRef ref) {
  final svc = ref.read(playerServiceProvider);
  final current = svc.gaplessMode;

  const options = <(Gapless, String, String)>[
    (Gapless.yes, 'Full', 'Re-uses decoder for seamless transitions'),
    (Gapless.weak, 'Weak', 'Gapless only on compatible formats (default)'),
    (Gapless.no, 'Off', 'Close and re-open audio output between tracks'),
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
              child:
                  Text('Gapless playback', style: AfTypography.titleSmall),
            ),
            const SizedBox(height: AfSpacing.s4),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AfSpacing.gutterGenerous),
              child: Text(
                'Controls how the player handles track transitions.',
                style: AfTypography.bodySmall
                    .copyWith(color: AfColors.textTertiary),
              ),
            ),
            const SizedBox(height: AfSpacing.s8),
            for (final (mode, label, subtitle) in options)
              _OptionTile(
                label: label,
                subtitle: subtitle,
                isActive: mode == current,
                onTap: () {
                  unawaited(svc.setGapless(mode));
                  unawaited(PlayerSettingsStore.saveGapless(mode));
                  Navigator.of(dialogCtx).pop();
                },
              ),
          ],
        ),
      ),
    ),
  );
}

void _showReplayGainDialog(BuildContext context, WidgetRef ref) {
  showDialog<void>(
    context: context,
    builder: (dialogCtx) => Dialog(
      backgroundColor: AfColors.surfaceBase,
      shape: RoundedRectangleBorder(borderRadius: AfRadii.borderLg),
      child: _ReplayGainDialogContent(),
    ),
  );
}

class _ReplayGainDialogContent extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ReplayGainDialogContent> createState() =>
      _ReplayGainDialogContentState();
}

class _ReplayGainDialogContentState
    extends ConsumerState<_ReplayGainDialogContent> {
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
    const options = <(ReplayGain, String, String)>[
      (ReplayGain.no, 'Off', 'No volume normalization'),
      (ReplayGain.track, 'Track', 'Normalize each track independently'),
      (ReplayGain.album, 'Album', 'Normalize per album (preserves dynamics)'),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AfSpacing.s16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AfSpacing.gutterGenerous),
            child: Text('ReplayGain', style: AfTypography.titleSmall),
          ),
          const SizedBox(height: AfSpacing.s4),
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AfSpacing.gutterGenerous),
            child: Text(
              'Normalize volume so all tracks play at a similar loudness.',
              style: AfTypography.bodySmall
                  .copyWith(color: AfColors.textTertiary),
            ),
          ),
          const SizedBox(height: AfSpacing.s8),
          for (final (mode, label, subtitle) in options)
            _OptionTile(
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
            // Preamp slider.
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AfSpacing.gutterGenerous),
              child: Row(
                children: [
                  Text('Pre-amp', style: AfTypography.bodyMedium),
                  const Spacer(),
                  Text(
                    '${_preamp >= 0 ? "+" : ""}${_preamp.toStringAsFixed(1)} dB',
                    style: AfTypography.mono
                        .copyWith(color: AfColors.textTertiary),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AfSpacing.gutterGenerous),
              child: Slider(
                value: _preamp,
                min: -15,
                max: 15,
                divisions: 30,
                activeColor: AfColors.indigo400,
                onChanged: (v) => setState(() => _preamp = v),
                onChangeEnd: (_) => _apply(),
              ),
            ),
            // Fallback gain slider.
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AfSpacing.gutterGenerous),
              child: Row(
                children: [
                  Text('Fallback gain', style: AfTypography.bodyMedium),
                  const Spacer(),
                  Text(
                    '${_fallback.toStringAsFixed(1)} dB',
                    style: AfTypography.mono
                        .copyWith(color: AfColors.textTertiary),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AfSpacing.gutterGenerous),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Slider(
                    value: _fallback,
                    min: -15,
                    max: 0,
                    divisions: 30,
                    activeColor: AfColors.indigo400,
                    onChanged: (v) => setState(() => _fallback = v),
                    onChangeEnd: (_) => _apply(),
                  ),
                  Text(
                    'Applied to files without ReplayGain tags',
                    style: AfTypography.caption
                        .copyWith(color: AfColors.textTertiary),
                  ),
                ],
              ),
            ),
            // Clip prevention toggle.
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AfSpacing.gutterGenerous),
              child: SwitchListTile.adaptive(
                value: !_clip,
                onChanged: (v) {
                  setState(() => _clip = !v);
                  _apply();
                },
                title: Text('Prevent clipping',
                    style: AfTypography.bodyMedium),
                subtitle: Text(
                  'Peak-limit output to avoid distortion',
                  style: AfTypography.bodySmall
                      .copyWith(color: AfColors.textTertiary),
                ),
                activeThumbColor: AfColors.indigo500,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

void _launchUrl(String url) {
  launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}
