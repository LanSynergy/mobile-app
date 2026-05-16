import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart'
    show AudioParams, Cache, Format, Gapless, ReplayGain, ReplayGainSettings;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/audio/player_settings_store.dart';
import '../../core/audio/player_service.dart';
import '../../core/local/app_mode_store.dart';
import '../../build_id.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final showLabels = ref.watch(showNavLabelsProvider);
    final svc = ref.read(playerServiceProvider);
    final mode = ref.watch(appModeProvider);
    final isLocal = mode == AppMode.local;
    return Scaffold(
      backgroundColor: AfColors.surfaceCanvas,
      appBar: AppBar(
        backgroundColor: AfColors.surfaceCanvas,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: Text('Settings', style: AfTypography.display),
        centerTitle: false,
        titleSpacing: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
          children: [
            const SizedBox(height: AfSpacing.s8),

            // ── Server (server mode) / Music Folders (local mode) ──────
            if (!isLocal) ...[
            _SettingsGroup(
              children: [
                _SettingsTile(
                  icon: Icons.dns_outlined,
                  iconColor: AfColors.indigo400,
                  title: auth?.server.name ?? 'Not connected',
                  subtitle: auth?.server.baseUrl,
                ),
                if (auth != null)
                  _SettingsTile(
                    icon: Icons.person_outline_rounded,
                    iconColor: AfColors.semanticSuccess,
                    title: auth.userName,
                    subtitle: auth.serverType.name[0].toUpperCase() +
                        auth.serverType.name.substring(1),
                  ),
                _SettingsTile(
                  icon: Icons.swap_horiz_rounded,
                  iconColor: AfColors.semanticInfo,
                  title: 'Switch server',
                  subtitle: 'Connect to a different server',
                  onTap: () => context.go('/onboarding/discover'),
                ),
                if (auth != null)
                  _SettingsTile(
                    icon: Icons.logout_rounded,
                    iconColor: AfColors.semanticError,
                    title: 'Sign out',
                    subtitle: 'Disconnect from ${auth.server.name}',
                    onTap: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: AfColors.surfaceBase,
                          title: const Text('Sign out?'),
                          content: Text(
                            'You will be disconnected from ${auth.server.name}.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: Text(
                                'Sign out',
                                style: TextStyle(color: AfColors.semanticError),
                              ),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true && context.mounted) {
                        await ref.read(authProvider.notifier).clear();
                        await AppModeStore.clear();
                        ref.read(appModeProvider.notifier).state = null;
                        if (context.mounted) context.go('/');
                      }
                    },
                  ),
              ],
            ),
            ],

            // ── Music Folders (local mode only) ────────────────────────
            if (isLocal) ...[
            _SectionLabel('Music folders'),
            _MusicFoldersCard(),
            ],

            const SizedBox(height: AfSpacing.s16),

            // ── Switch mode ────────────────────────────────────────────
            _SettingsGroup(
              children: [
                _SettingsTile(
                  icon: Icons.swap_horiz_rounded,
                  iconColor: AfColors.semanticWarning,
                  title: 'Switch mode',
                  subtitle: isLocal ? 'Currently: Local files' : 'Currently: Server',
                  onTap: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: AfColors.surfaceBase,
                        title: const Text('Switch mode?'),
                        content: const Text(
                          'This will return you to the mode selection screen.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Switch'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true && context.mounted) {
                      await AppModeStore.clear();
                      ref.read(appModeProvider.notifier).state = null;
                      if (context.mounted) context.go('/onboarding/mode');
                    }
                  },
                ),
              ],
            ),

            const SizedBox(height: AfSpacing.s16),

            // ── Appearance ─────────────────────────────────────────────
            _SectionLabel('Appearance'),
            _SettingsGroup(
              children: [
                _SettingsSwitchTile(
                  icon: Icons.label_outline_rounded,
                  iconColor: AfColors.semanticInfo,
                  title: 'Always show tab labels',
                  subtitle: 'Icon-only with capsule indicator by default',
                  value: showLabels,
                  onChanged: (v) =>
                      ref.read(showNavLabelsProvider.notifier).state = v,
                ),
              ],
            ),

            const SizedBox(height: AfSpacing.s16),

            // ── Audio output ───────────────────────────────────────────
            _SectionLabel('Audio output'),
            _SettingsGroup(
              children: [
                StreamBuilder<AudioParams>(
                  stream: ref.read(playerServiceProvider).audioOutParamsStream,
                  initialData: ref.read(playerServiceProvider).audioOutParams,
                  builder: (context, snap) {
                    final params = snap.data;
                    final rate = params?.sampleRate;
                    final fmt = params?.format;
                    final ch = params?.channelCount;
                    final hasData = rate != null && rate > 0;
                    return _SettingsTile(
                      icon: Icons.graphic_eq_rounded,
                      iconColor: AfColors.semanticSuccess,
                      title: 'Current output',
                      subtitle: hasData
                          ? '$rate Hz · ${fmt?.name ?? "auto"} · ${ch}ch'
                          : 'Not active — start playback first',
                    );
                  },
                ),
                _SettingsTile(
                  icon: Icons.speed_rounded,
                  iconColor: AfColors.indigo300,
                  title: 'Sample rate',
                  subtitle: 'Force output sample rate for DAC',
                  onTap: () => _showSampleRateDialog(context, ref),
                ),
                _SettingsTile(
                  icon: Icons.memory_rounded,
                  iconColor: AfColors.indigo300,
                  title: 'Bit depth',
                  subtitle: 'Force output format',
                  onTap: () => _showFormatDialog(context, ref),
                ),
                StreamBuilder<bool>(
                  stream: svc.audioExclusiveStream,
                  initialData: svc.audioExclusive,
                  builder: (context, snap) {
                    final enabled = snap.data ?? false;
                    return _SettingsSwitchTile(
                      icon: Icons.lock_outline_rounded,
                      iconColor: AfColors.semanticWarning,
                      title: 'Exclusive mode',
                      subtitle: 'Bypass OS mixer for bit-perfect output',
                      value: enabled,
                      onChanged: (v) {
                        unawaited(svc.setAudioExclusive(v));
                        unawaited(PlayerSettingsStore.saveExclusive(v));
                      },
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: AfSpacing.s16),

            // ── Network & cache ────────────────────────────────────────
            _SectionLabel('Network & cache'),
            _SettingsGroup(
              children: [
                _SettingsTile(
                  icon: Icons.cached_rounded,
                  iconColor: AfColors.semanticInfo,
                  title: 'Cache duration',
                  subtitle: 'How far ahead to buffer',
                  onTap: () => _showCacheDurationDialog(context, ref),
                ),
                _SettingsTile(
                  icon: Icons.storage_rounded,
                  iconColor: AfColors.semanticInfo,
                  title: 'Buffer size',
                  subtitle: 'Audio hardware buffer (latency vs stability)',
                  onTap: () => _showAudioBufferDialog(context, ref),
                ),
                StreamBuilder<bool>(
                  stream: svc.audioStreamSilenceStream,
                  initialData: svc.audioStreamSilence,
                  builder: (context, snap) {
                    final enabled = snap.data ?? false;
                    return _SettingsSwitchTile(
                      icon: Icons.volume_up_rounded,
                      iconColor: AfColors.semanticWarning,
                      title: 'Keep audio active on pause',
                      subtitle: 'Eliminates click/pop on resume',
                      value: enabled,
                      onChanged: (v) {
                        unawaited(svc.setAudioStreamSilence(v));
                        unawaited(PlayerSettingsStore.saveStreamSilence(v));
                      },
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: AfSpacing.s16),

            // ── Audio processing ───────────────────────────────────────
            _SectionLabel('Audio processing'),
            _SettingsGroup(
              children: [
                _SettingsTile(
                  icon: Icons.equalizer_rounded,
                  iconColor: AfColors.indigo400,
                  title: 'ReplayGain',
                  subtitle: 'Volume normalization across tracks',
                  onTap: () => _showReplayGainDialog(context, ref),
                ),
                _SettingsTile(
                  icon: Icons.skip_next_rounded,
                  iconColor: AfColors.indigo400,
                  title: 'Gapless playback',
                  subtitle: 'Seamless transitions between tracks',
                  onTap: () => _showGaplessDialog(context, ref),
                ),
                _PrefetchToggle(svc: svc),
              ],
            ),

            const SizedBox(height: AfSpacing.s16),

            // ── About ──────────────────────────────────────────────────
            _SectionLabel('About'),
            _SettingsGroup(
              children: [
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snap) {
                    final version = snap.data != null
                        ? 'v${snap.data!.version}+${snap.data!.buildNumber} ($kBuildId)'
                        : '...';
                    return _SettingsTile(
                      icon: Icons.info_outline_rounded,
                      iconColor: AfColors.textTertiary,
                      title: 'Aetherfin $version',
                      subtitle: 'Jellyfin-backed music player · FOSS',
                    );
                  },
                ),
                _SettingsTile(
                  icon: Icons.code_rounded,
                  iconColor: AfColors.textTertiary,
                  title: 'Source code',
                  subtitle: 'github.com/Aetherfin/mobile-app',
                  trailing: const Icon(Icons.open_in_new_rounded,
                      color: AfColors.textTertiary, size: 16),
                  onTap: () =>
                      _launchUrl('https://github.com/Aetherfin/mobile-app'),
                ),
                _SettingsTile(
                  icon: Icons.description_outlined,
                  iconColor: AfColors.textTertiary,
                  title: 'Licenses',
                  subtitle: 'Open-source licenses',
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: 'Aetherfin',
                    applicationLegalese: '© 2025 Aetherfin contributors',
                  ),
                ),
              ],
            ),

            const SizedBox(height: AfSpacing.s24),
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
          AfSpacing.s16, 0, AfSpacing.s4, AfSpacing.s8),
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

/// Samsung One UI–style grouped card container.
class _SettingsGroup extends StatelessWidget {
  final List<Widget> children;
  const _SettingsGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
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

/// A single settings row with a colored circular icon.
class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

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

/// A settings row with a switch (Samsung style).
class _SettingsSwitchTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsSwitchTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

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
              activeTrackColor: AfColors.indigo500,
            ),
          ],
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

/// Shows the list of registered music folders with add/remove controls.
class _MusicFoldersCard extends ConsumerStatefulWidget {
  @override
  ConsumerState<_MusicFoldersCard> createState() => _MusicFoldersCardState();
}

class _MusicFoldersCardState extends ConsumerState<_MusicFoldersCard> {
  List<({String uri, String displayPath})> _folders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    final lib = ref.read(localLibraryProvider);
    final folders = await lib.getFolders();
    if (mounted) setState(() { _folders = folders; _loading = false; });
  }

  Future<void> _addFolder() async {
    final lib = ref.read(localLibraryProvider);
    final uri = await lib.pickAndAddFolder();
    if (uri != null) {
      await _loadFolders();
      // Trigger a scan of the new folder
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Scanning new folder...')),
        );
        await lib.scanFolder(uri);
        // Invalidate local providers to refresh the library
        ref.invalidate(localAlbumsProvider);
        ref.invalidate(localArtistsProvider);
        ref.invalidate(localTracksProvider);
        ref.invalidate(localGenresProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Scan complete')),
          );
        }
      }
    }
  }

  Future<void> _removeFolder(String uri) async {
    final lib = ref.read(localLibraryProvider);
    await lib.removeFolder(uri);
    await _loadFolders();
    ref.invalidate(localAlbumsProvider);
    ref.invalidate(localArtistsProvider);
    ref.invalidate(localTracksProvider);
    ref.invalidate(localGenresProvider);
  }

  Future<void> _rescan() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Scanning all folders...')),
    );
    final lib = ref.read(localLibraryProvider);
    final count = await lib.scanAll();
    ref.invalidate(localAlbumsProvider);
    ref.invalidate(localArtistsProvider);
    ref.invalidate(localTracksProvider);
    ref.invalidate(localGenresProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Scan complete — $count tracks updated')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsGroup(
      children: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(AfSpacing.s16),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          for (final folder in _folders)
            _SettingsTile(
              icon: Icons.folder_rounded,
              iconColor: AfColors.indigo400,
              title: folder.displayPath,
              trailing: IconButton(
                icon: const Icon(Icons.remove_circle_outline,
                    color: AfColors.semanticError, size: 20),
                onPressed: () => _removeFolder(folder.uri),
              ),
            ),
          _SettingsTile(
            icon: Icons.add_rounded,
            iconColor: AfColors.semanticSuccess,
            title: 'Add folder',
            subtitle: 'Pick another music folder',
            onTap: _addFolder,
          ),
          _SettingsTile(
            icon: Icons.refresh_rounded,
            iconColor: AfColors.semanticInfo,
            title: 'Re-scan library',
            subtitle: 'Check for new or changed files',
            onTap: _rescan,
          ),
        ],
      ],
    );
  }
}

class _PrefetchToggle extends StatefulWidget {
  final AfPlayerService svc;
  const _PrefetchToggle({required this.svc});

  @override
  State<_PrefetchToggle> createState() => _PrefetchToggleState();
}

class _PrefetchToggleState extends State<_PrefetchToggle> {
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    _enabled = widget.svc.prefetchPlaylist;
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsSwitchTile(
      icon: Icons.download_rounded,
      iconColor: AfColors.semanticSuccess,
      title: 'Prefetch next track',
      subtitle: 'Pre-load next playlist entry in background',
      value: _enabled,
      onChanged: (v) {
        setState(() => _enabled = v);
        unawaited(widget.svc.setPrefetchPlaylist(v));
        unawaited(PlayerSettingsStore.savePrefetchPlaylist(v));
      },
    );
  }
}

void _launchUrl(String url) {
  launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}
