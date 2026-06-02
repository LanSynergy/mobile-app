import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show AudioParams;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/audio/offline_cache_service.dart';
import '../../core/audio/player_settings_store.dart';
import '../../core/local/app_mode_store.dart';
import '../../build_id.dart';
import '../../design_tokens/tokens.dart';
import '../../state/lastfm_sync_provider.dart';
import '../../state/providers.dart';
import '../../widgets/af_dialog.dart';
import '../../widgets/af_scrollbar.dart';
import '../../widgets/press_scale.dart';
import 'settings_dialogs.dart';
import 'settings_sections.dart';

// ── Private iOS-style helper widgets ─────────────────────────────────────────

class _IconContainer extends StatelessWidget {
  const _IconContainer({required this.icon, this.color});
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: const BoxDecoration(
        color: AfColors.surfaceHigh,
        borderRadius: AfRadii.borderSm,
      ),
      child: Icon(icon, size: 16, color: color ?? AfColors.accentPrimary),
    );
  }
}

const _chevron = Icon(
  LucideIcons.chevronRight,
  size: 16,
  color: AfColors.textDisabled,
);

class _IosGroup extends StatelessWidget {
  const _IosGroup({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: AfColors.surfaceRaised,
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

class _IosTile extends StatelessWidget {
  const _IosTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      ensureHitTarget: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AfSpacing.minHitTarget),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AfSpacing.s16,
            vertical: AfSpacing.s12,
          ),
          child: Row(
            children: [
              _IconContainer(
                icon: icon,
                color: danger ? AfColors.semanticError : AfColors.accentPrimary,
              ),
              const SizedBox(width: AfSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: AfTypography.bodyMedium.copyWith(
                        color: danger
                            ? AfColors.semanticError
                            : AfColors.textPrimary,
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
              if (trailing != null) ...[
                const SizedBox(width: AfSpacing.s8),
                trailing!,
              ] else if (onTap != null) ...[
                const SizedBox(width: AfSpacing.s8),
                _chevron,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _IosSwitch extends StatelessWidget {
  const _IosSwitch({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: () => onChanged(!value),
      ensureHitTarget: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AfSpacing.minHitTarget),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AfSpacing.s16,
            vertical: AfSpacing.s12,
          ),
          child: Row(
            children: [
              _IconContainer(icon: icon),
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
                activeThumbColor: AfColors.textOnPrimary,
                activeTrackColor: AfColors.accentPrimary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Section header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: AfSpacing.s4, bottom: AfSpacing.s8),
      child: Text(
        label.toUpperCase(),
        style: AfTypography.label.copyWith(color: AfColors.textTertiary),
      ),
    );
  }
}

// ── Screen ───────────────────────────────────────────────────────────────────

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final svc = ref.read(playerServiceProvider);
    final mode = ref.watch(appModeProvider);
    final isLocal = mode == AppMode.local;

    return Scaffold(
      backgroundColor: AfColors.surfaceCanvas,
      body: SafeArea(
        child: AfScrollbar(
          child: ListView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
            children: [
              // ── Back button ──────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.only(top: AfSpacing.s8),
                child: GestureDetector(
                  onTap: () => context.pop(),
                  child: const SizedBox(
                    width: AfSpacing.minHitTarget,
                    height: AfSpacing.minHitTarget,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Icon(
                        LucideIcons.arrowLeft,
                        size: 24,
                        color: AfColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),

              // ── Page header ─────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.only(
                  bottom: AfSpacing.s24,
                  left: AfSpacing.s4,
                ),
                child: Text('Settings', style: AfTypography.titleLarge),
              ),

              // ── Server (server mode) ────────────────────────────────
              if (!isLocal) ...[
                _IosGroup(
                  children: [
                    _IosTile(
                      icon: LucideIcons.server,
                      title: auth?.server.name ?? 'Not connected',
                      subtitle: auth?.server.baseUrl,
                    ),
                    if (auth != null)
                      _IosTile(
                        icon: LucideIcons.user,
                        title: auth.userName,
                        subtitle:
                            auth.serverType.name[0].toUpperCase() +
                            auth.serverType.name.substring(1),
                      ),
                    _IosTile(
                      icon: LucideIcons.arrowLeftRight,
                      title: 'Switch server',
                      subtitle: 'Connect to a different server',
                      onTap: () => context.go('/onboarding/discover'),
                    ),
                    if (auth != null)
                      _IosTile(
                        icon: LucideIcons.logOut,
                        title: 'Sign out',
                        subtitle: 'Disconnect from ${auth.server.name}',
                        danger: true,
                        onTap: () async {
                          final confirmed = await showBlurDialog<bool>(
                            context: context,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Sign out?',
                                  style: AfTypography.titleMedium,
                                ),
                                const SizedBox(height: AfSpacing.s12),
                                Text(
                                  'You will be disconnected from ${auth.server.name}.',
                                  style: AfTypography.bodyMedium,
                                ),
                                const SizedBox(height: AfSpacing.s24),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: Text(
                                        'Sign out',
                                        style: AfTypography.bodyMedium.copyWith(
                                          color: AfColors.semanticError,
                                        ),
                                      ),
                                    ),
                                  ],
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

              // ── Music Folders (local mode only) ─────────────────────
              if (isLocal) ...[
                const _SectionHeader('Music folders'),
                const MusicFoldersCard(),
              ],

              const SizedBox(height: AfSpacing.s16),

              // ── Switch mode ─────────────────────────────────────────
              _IosGroup(
                children: [
                  _IosTile(
                    icon: LucideIcons.arrowLeftRight,
                    title: 'Switch mode',
                    subtitle: isLocal
                        ? 'Currently: Local files'
                        : 'Currently: Server',
                    onTap: () async {
                      final confirmed = await showBlurDialog<bool>(
                        context: context,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Switch mode?',
                              style: AfTypography.titleMedium,
                            ),
                            const SizedBox(height: AfSpacing.s12),
                            Text(
                              'This will return you to the mode selection screen.',
                              style: AfTypography.bodyMedium,
                            ),
                            const SizedBox(height: AfSpacing.s24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Switch'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true && context.mounted) {
                        // Clear auth FIRST so authSub fires before modeSub.
                        // This way the router redirect sees auth=null before
                        // the migration fallback kicks in when mode→null.
                        await ref.read(authProvider.notifier).clear();
                        await AppModeStore.clear();
                        ref.read(appModeProvider.notifier).state = null;
                        if (context.mounted) context.go('/');
                      }
                    },
                  ),
                ],
              ),

              const SizedBox(height: AfSpacing.s16),

              // ── Appearance ───────────────────────────────────────────
              const _SectionHeader('Appearance'),
              _IosGroup(
                children: [
                  _IosTile(
                    icon: LucideIcons.smartphone,
                    title: 'App icon',
                    subtitle: switch (ref.watch(appIconProvider)) {
                      'MidnightIcon' => 'Midnight',
                      'NordicIcon' => 'Nordic',
                      'SunsetIcon' => 'Sunset',
                      _ => 'Default',
                    },
                    onTap: () => showAppIconDialog(context, ref),
                  ),
                ],
              ),

              const SizedBox(height: AfSpacing.s16),

              // ── Audio output ─────────────────────────────────────────
              const _SectionHeader('Audio output'),
              _IosGroup(
                children: [
                  StreamBuilder<AudioParams>(
                    stream: ref
                        .read(playerServiceProvider)
                        .audioOutParamsStream,
                    initialData: ref.read(playerServiceProvider).audioOutParams,
                    builder: (context, snap) {
                      final params = snap.data;
                      final rate = params?.sampleRate;
                      final fmt = params?.format;
                      final ch = params?.channelCount;
                      final hasData = rate != null && rate > 0;
                      return _IosTile(
                        icon: LucideIcons.waves,
                        title: 'Current output',
                        subtitle: hasData
                            ? '$rate Hz · ${fmt?.name ?? "auto"} · ${ch}ch'
                            : 'Not active — start playback first',
                      );
                    },
                  ),
                  _IosTile(
                    icon: LucideIcons.gauge,
                    title: 'Sample rate',
                    subtitle: 'Force output sample rate for DAC',
                    onTap: () => showSampleRateDialog(context, ref),
                  ),
                  _IosTile(
                    icon: LucideIcons.cpu,
                    title: 'Bit depth',
                    subtitle: 'Force output format',
                    onTap: () => showFormatDialog(context, ref),
                  ),
                  StreamBuilder<bool>(
                    stream: svc.audioExclusiveStream,
                    initialData: svc.audioExclusive,
                    builder: (context, snap) {
                      final enabled = snap.data ?? false;
                      return _IosSwitch(
                        icon: LucideIcons.lock,
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

              // ── Network & cache ──────────────────────────────────────
              const _SectionHeader('Network & cache'),
              _IosGroup(
                children: [
                  _IosTile(
                    icon: LucideIcons.music,
                    title: 'Streaming quality',
                    subtitle: ref.watch(maxBitrateProvider) == 0
                        ? 'Original / Lossless'
                        : '${ref.watch(maxBitrateProvider)} kbps',
                    onTap: () => showStreamingQualityDialog(context, ref),
                  ),
                  _IosTile(
                    icon: LucideIcons.rotateCcw,
                    title: 'Cache duration',
                    subtitle: 'How far ahead to buffer',
                    onTap: () => showCacheDurationDialog(context, ref),
                  ),
                  _IosTile(
                    icon: LucideIcons.hardDrive,
                    title: 'Buffer size',
                    subtitle: 'Audio hardware buffer (latency vs stability)',
                    onTap: () => showAudioBufferDialog(context, ref),
                  ),
                  StreamBuilder<bool>(
                    stream: svc.audioStreamSilenceStream,
                    initialData: svc.audioStreamSilence,
                    builder: (context, snap) {
                      final enabled = snap.data ?? false;
                      return _IosSwitch(
                        icon: LucideIcons.volume2,
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

              // ── Offline cache (server mode only) ─────────────────────
              if (!isLocal) ...[
                const _SectionHeader('Offline cache'),
                _IosGroup(
                  children: [
                    Consumer(
                      builder: (context, ref2, _) {
                        final enabled = ref2.watch(offlineCacheEnabledProvider);
                        return _IosSwitch(
                          icon: LucideIcons.hardDrive,
                          title: 'Cache tracks offline',
                          subtitle: enabled
                              ? 'Save streamed tracks to device storage'
                              : 'Always stream from server',
                          value: enabled,
                          onChanged: (v) {
                            ref
                                    .read(offlineCacheEnabledProvider.notifier)
                                    .state =
                                v;
                            unawaited(
                              PlayerSettingsStore.saveOfflineCacheEnabled(v),
                            );
                          },
                        );
                      },
                    ),
                    _CacheUsageTile(),
                    _IosTile(
                      icon: LucideIcons.hardDrive,
                      title: 'Max cache size',
                      subtitle: OfflineCacheService.formatSize(
                        ref.watch(offlineCacheMaxSizeProvider),
                      ),
                      onTap: () => showOfflineCacheSizeDialog(context, ref),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: AfSpacing.s16),

              // ── Audio processing ─────────────────────────────────────
              const _SectionHeader('Audio processing'),
              _IosGroup(
                children: [
                  _IosTile(
                    icon: LucideIcons.slidersHorizontal,
                    title: 'ReplayGain',
                    subtitle: 'Volume normalization across tracks',
                    onTap: () => showReplayGainDialog(context, ref),
                  ),
                  _IosTile(
                    icon: LucideIcons.skipForward,
                    title: 'Gapless playback',
                    subtitle: 'Seamless transitions between tracks',
                    onTap: () => showGaplessDialog(context, ref),
                  ),
                  _IosSwitch(
                    icon: LucideIcons.download,
                    title: 'Prefetch next track',
                    subtitle: 'Pre-load next playlist entry in background',
                    value: svc.prefetchPlaylist,
                    onChanged: (v) {
                      unawaited(svc.setPrefetchPlaylist(v));
                      unawaited(PlayerSettingsStore.savePrefetchPlaylist(v));
                    },
                  ),
                  _IosSwitch(
                    icon: LucideIcons.lightbulb,
                    title: 'Smart queue',
                    subtitle:
                        'Learn from skips and plays for better suggestions',
                    value: ref.watch(smartQueueEnabledProvider),
                    onChanged: (v) {
                      ref.read(smartQueueEnabledProvider.notifier).state = v;
                    },
                  ),
                ],
              ),

              const SizedBox(height: AfSpacing.s16),

              // ── Last.fm Scrobbling ───────────────────────────────────
              const _LastFmSettingsSection(),

              const SizedBox(height: AfSpacing.s16),

              // ── Advanced ─────────────────────────────────────────────
              const _SectionHeader('Advanced'),
              _IosGroup(
                children: [
                  _IosTile(
                    icon: LucideIcons.trash2,
                    title: 'Clear app data',
                    subtitle: 'Reset app to initial state',
                    danger: true,
                    onTap: () async {
                      final confirmed = await showBlurDialog<bool>(
                        context: context,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Clear app data?',
                              style: AfTypography.titleMedium,
                            ),
                            const SizedBox(height: AfSpacing.s12),
                            Text(
                              'This will wipe all local data, settings, and downloaded metadata. You will need to set up the app again.',
                              style: AfTypography.bodyMedium,
                            ),
                            const SizedBox(height: AfSpacing.s24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: Text(
                                    'Clear data',
                                    style: AfTypography.bodyMedium.copyWith(
                                      color: AfColors.semanticError,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true && context.mounted) {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.clear();

                        const secureStorage = FlutterSecureStorage();
                        await secureStorage.deleteAll();

                        // Close the database connection before
                        // deleting the file!
                        final db = ref.read(appDatabaseProvider);
                        await db.close();

                        final dbFolder =
                            await getApplicationDocumentsDirectory();
                        final dbFile = File(
                          p.join(dbFolder.path, 'aetherfin_drift.db'),
                        );
                        if (dbFile.existsSync()) {
                          await dbFile.delete();
                        }

                        // Invalidate the provider so a fresh
                        // database is opened on next request.
                        ref.invalidate(appDatabaseProvider);

                        await AppModeStore.clear();
                        ref.read(appModeProvider.notifier).state = null;
                        ref
                                .read(localOnboardingCompletedProvider.notifier)
                                .state =
                            false;
                        await ref.read(authProvider.notifier).clear();
                        if (context.mounted) {
                          context.go('/');
                        }
                      }
                    },
                  ),
                ],
              ),

              const SizedBox(height: AfSpacing.s16),

              // ── About ────────────────────────────────────────────────
              const _SectionHeader('About'),
              _IosGroup(
                children: [
                  FutureBuilder<PackageInfo>(
                    future: PackageInfo.fromPlatform(),
                    builder: (context, snap) {
                      final version = snap.data != null
                          ? 'v${snap.data!.version}+${snap.data!.buildNumber} ($kBuildId)'
                          : '...';
                      return _IosTile(
                        icon: LucideIcons.info,
                        title: 'Aetherfin $version',
                        subtitle: 'Jellyfin-backed music player · FOSS',
                      );
                    },
                  ),
                  _IosTile(
                    icon: LucideIcons.code,
                    title: 'Source code',
                    subtitle: 'github.com/Aetherfin/mobile-app',
                    trailing: const Icon(
                      LucideIcons.externalLink,
                      color: AfColors.textTertiary,
                      size: 16,
                    ),
                    onTap: () => launchSettingsUrl(
                      'https://github.com/Aetherfin/mobile-app',
                    ),
                  ),
                  _IosTile(
                    icon: LucideIcons.fileText,
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

              // ── Footer caption ───────────────────────────────────────
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AfSpacing.s24),
                  child: FutureBuilder<PackageInfo>(
                    future: PackageInfo.fromPlatform(),
                    builder: (context, snap) {
                      final version = snap.data != null
                          ? 'v${snap.data!.version}+${snap.data!.buildNumber}'
                          : '...';
                      return Text(
                        'Aetherfin $version · Android',
                        style: AfTypography.overline.copyWith(
                          color: AfColors.textDisabled,
                        ),
                      );
                    },
                  ),
                ),
              ),

              const SizedBox(height: AfSpacing.s24),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Cache usage tile ─────────────────────────────────────────────────────────

class _CacheUsageTile extends ConsumerStatefulWidget {
  @override
  ConsumerState<_CacheUsageTile> createState() => _CacheUsageTileState();
}

class _CacheUsageTileState extends ConsumerState<_CacheUsageTile> {
  int _cacheSize = 0;
  int _cacheCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cache = ref.read(offlineCacheServiceProvider);
    final size = await cache.cacheSize();
    final count = await cache.cachedCount();
    if (mounted) {
      setState(() {
        _cacheSize = size;
        _cacheCount = count;
        _loading = false;
      });
    }
  }

  Future<void> _clearCache() async {
    final confirmed = await showOfflineCacheClearDialog(context, ref);
    if (confirmed && mounted) {
      await ref.read(offlineCacheServiceProvider).clearCache();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Cache cleared')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxSize = ref.watch(offlineCacheMaxSizeProvider);
    final usedLabel = OfflineCacheService.formatSize(_cacheSize);
    final maxLabel = OfflineCacheService.formatSize(maxSize);
    return _IosTile(
      icon: LucideIcons.database,
      title: _loading ? 'Cache usage…' : 'Cache usage',
      subtitle: _loading
          ? null
          : '$_cacheCount tracks · $usedLabel / $maxLabel',
      trailing: _loading
          ? null
          : TextButton(
              onPressed: _cacheSize > 0 ? _clearCache : null,
              child: const Text('Clear'),
            ),
    );
  }
}

// ── Last.fm section ──────────────────────────────────────────────────────────

class _LastFmSettingsSection extends ConsumerWidget {
  const _LastFmSettingsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apiKey = ref.watch(lastfmApiKeyProvider);
    final apiSecret = ref.watch(lastfmApiSecretProvider);
    final sessionKey = ref.watch(lastfmSessionKeyProvider);
    final username = ref.watch(lastfmUsernameProvider);
    final scrobbleEnabled = ref.watch(lastfmScrobbleEnabledProvider);
    final lastfmStatus = ref.watch(lastfmStatusProvider);

    final hasCredentials = apiKey.isNotEmpty && apiSecret.isNotEmpty;
    final isConnected = sessionKey.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _SectionHeader('Last.fm'),
        _IosGroup(
          children: [
            _IosTile(
              icon: LucideIcons.key,
              title: 'API Credentials',
              subtitle: hasCredentials
                  ? 'Key: ${apiKey.substring(0, apiKey.length > 8 ? 8 : apiKey.length)}…'
                  : 'Not configured — set to scrobble',
              onTap: () => showLastFmApiConfigDialog(context, ref),
            ),
            if (hasCredentials && !isConnected)
              _IosTile(
                icon: LucideIcons.link,
                title: 'Link Last.fm Account',
                subtitle: 'Log in with username and password',
                onTap: () => showLastFmLoginDialog(context, ref),
              ),
            if (isConnected) ...[
              _IosTile(
                icon: LucideIcons.user,
                title: 'Connected as $username',
                subtitle: 'Tap to disconnect / sign out',
                onTap: () => showLastFmSignOutDialog(context, ref),
              ),
              _IosTile(
                icon: LucideIcons.refreshCw,
                title: 'Sync Liked Tracks',
                subtitle: 'Sync favorites between library and Last.fm',
                onTap: () async {
                  unawaited(
                    showBlurDialog(
                      context: context,
                      barrierDismissible: false,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AfColors.accentPrimary,
                            ),
                          ),
                          const SizedBox(width: AfSpacing.s16),
                          Text(
                            'Syncing favorites...',
                            style: AfTypography.bodyMedium.copyWith(
                              color: AfColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );

                  try {
                    final syncFn = ref.read(lastFmSyncProvider);
                    final result = await syncFn();
                    if (context.mounted) {
                      Navigator.pop(context);
                    } // Close dialog

                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Synced! Added ${result.toApp} tracks locally, '
                            'loved ${result.toLastFm} on Last.fm.',
                          ),
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      Navigator.pop(context);
                    } // Close dialog
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Sync failed: $e')),
                      );
                    }
                  }
                },
              ),
              _IosSwitch(
                icon: LucideIcons.checkSquare,
                title: 'Scrobble tracks',
                subtitle: 'Submit played tracks to profile',
                value: scrobbleEnabled,
                onChanged: (v) {
                  ref.read(lastfmScrobbleEnabledProvider.notifier).state = v;
                  unawaited(PlayerSettingsStore.saveLastFmScrobbleEnabled(v));
                },
              ),
              if (lastfmStatus != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AfSpacing.s16,
                    AfSpacing.s4,
                    AfSpacing.s16,
                    AfSpacing.s4,
                  ),
                  child: Text(
                    lastfmStatus,
                    style: AfTypography.caption.copyWith(
                      color: lastfmStatus.startsWith('ERROR')
                          ? AfColors.semanticError
                          : AfColors.textTertiary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ],
        ),
      ],
    );
  }
}
