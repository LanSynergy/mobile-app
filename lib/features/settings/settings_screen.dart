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
import '../../state/providers.dart';
import '../../widgets/af_dialog.dart';
import 'settings_dialogs.dart';
import 'settings_sections.dart';
import 'settings_widgets.dart';

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
      appBar: AppBar(
        backgroundColor: AfColors.surfaceCanvas,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(
            LucideIcons.arrowLeft,
            color: AfColors.textPrimary,
            size: 24,
          ),
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
              SettingsGroup(
                children: [
                  SettingsTile(
                    icon: LucideIcons.server,
                    iconColor: AfColors.textSecondary,
                    title: auth?.server.name ?? 'Not connected',
                    subtitle: auth?.server.baseUrl,
                  ),
                  if (auth != null)
                    SettingsTile(
                      icon: LucideIcons.user,
                      iconColor: AfColors.textSecondary,
                      title: auth.userName,
                      subtitle:
                          auth.serverType.name[0].toUpperCase() +
                          auth.serverType.name.substring(1),
                    ),
                  SettingsTile(
                    icon: LucideIcons.arrowLeftRight,
                    iconColor: AfColors.textSecondary,
                    title: 'Switch server',
                    subtitle: 'Connect to a different server',
                    onTap: () => context.go('/onboarding/discover'),
                  ),
                  if (auth != null)
                    SettingsTile(
                      icon: LucideIcons.logOut,
                      iconColor: AfColors.textSecondary,
                      title: 'Sign out',
                      subtitle: 'Disconnect from ${auth.server.name}',
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
                                    child: const Text(
                                      'Sign out',
                                      style: TextStyle(
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

            // ── Music Folders (local mode only) ────────────────────────
            if (isLocal) ...[
              const SettingsLabel('Music folders'),
              const MusicFoldersCard(),
            ],

            const SizedBox(height: AfSpacing.s16),

            // ── Switch mode ────────────────────────────────────────────
            SettingsGroup(
              children: [
                SettingsTile(
                  icon: LucideIcons.arrowLeftRight,
                  iconColor: AfColors.textSecondary,
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
                          Text('Switch mode?', style: AfTypography.titleMedium),
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
                                onPressed: () => Navigator.pop(context, false),
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

            // ── Appearance ─────────────────────────────────────────────
            const SettingsLabel('Appearance'),
            const SettingsGroup(children: [ArtworkPulseSwitch()]),

            const SizedBox(height: AfSpacing.s16),

            // ── Audio output ───────────────────────────────────────────
            const SettingsLabel('Audio output'),
            SettingsGroup(
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
                    return SettingsTile(
                      icon: LucideIcons.waves,
                      iconColor: AfColors.textSecondary,
                      title: 'Current output',
                      subtitle: hasData
                          ? '$rate Hz · ${fmt?.name ?? "auto"} · ${ch}ch'
                          : 'Not active — start playback first',
                    );
                  },
                ),
                SettingsTile(
                  icon: LucideIcons.gauge,
                  iconColor: AfColors.textSecondary,
                  title: 'Sample rate',
                  subtitle: 'Force output sample rate for DAC',
                  onTap: () => showSampleRateDialog(context, ref),
                ),
                SettingsTile(
                  icon: LucideIcons.cpu,
                  iconColor: AfColors.textSecondary,
                  title: 'Bit depth',
                  subtitle: 'Force output format',
                  onTap: () => showFormatDialog(context, ref),
                ),
                StreamBuilder<bool>(
                  stream: svc.audioExclusiveStream,
                  initialData: svc.audioExclusive,
                  builder: (context, snap) {
                    final enabled = snap.data ?? false;
                    return SettingsSwitchTile(
                      icon: LucideIcons.lock,
                      iconColor: AfColors.textSecondary,
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
            const SettingsLabel('Network & cache'),
            SettingsGroup(
              children: [
                SettingsTile(
                  icon: LucideIcons.music,
                  iconColor: AfColors.textSecondary,
                  title: 'Streaming quality',
                  subtitle: ref.watch(maxBitrateProvider) == 0
                      ? 'Original / Lossless'
                      : '${ref.watch(maxBitrateProvider)} kbps',
                  onTap: () => showStreamingQualityDialog(context, ref),
                ),
                SettingsTile(
                  icon: LucideIcons.rotateCcw,
                  iconColor: AfColors.textSecondary,
                  title: 'Cache duration',
                  subtitle: 'How far ahead to buffer',
                  onTap: () => showCacheDurationDialog(context, ref),
                ),
                SettingsTile(
                  icon: LucideIcons.hardDrive,
                  iconColor: AfColors.textSecondary,
                  title: 'Buffer size',
                  subtitle: 'Audio hardware buffer (latency vs stability)',
                  onTap: () => showAudioBufferDialog(context, ref),
                ),
                StreamBuilder<bool>(
                  stream: svc.audioStreamSilenceStream,
                  initialData: svc.audioStreamSilence,
                  builder: (context, snap) {
                    final enabled = snap.data ?? false;
                    return SettingsSwitchTile(
                      icon: LucideIcons.volume2,
                      iconColor: AfColors.textSecondary,
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

            // ── Offline cache (server mode only) ───────────────────────
            if (!isLocal) ...[
              const SettingsLabel('Offline cache'),
              SettingsGroup(
                children: [
                  Consumer(
                    builder: (context, ref2, _) {
                      final enabled = ref2.watch(offlineCacheEnabledProvider);
                      return SettingsSwitchTile(
                        icon: LucideIcons.hardDrive,
                        iconColor: AfColors.textSecondary,
                        title: 'Cache tracks offline',
                        subtitle: enabled
                            ? 'Save streamed tracks to device storage'
                            : 'Always stream from server',
                        value: enabled,
                        onChanged: (v) {
                          ref.read(offlineCacheEnabledProvider.notifier).state =
                              v;
                          unawaited(
                            PlayerSettingsStore.saveOfflineCacheEnabled(v),
                          );
                        },
                      );
                    },
                  ),
                  _CacheUsageTile(),
                  SettingsTile(
                    icon: LucideIcons.hardDrive,
                    iconColor: AfColors.textSecondary,
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

            // ── Audio processing ───────────────────────────────────────
            const SettingsLabel('Audio processing'),
            SettingsGroup(
              children: [
                SettingsTile(
                  icon: LucideIcons.slidersHorizontal,
                  iconColor: AfColors.textSecondary,
                  title: 'ReplayGain',
                  subtitle: 'Volume normalization across tracks',
                  onTap: () => showReplayGainDialog(context, ref),
                ),
                SettingsTile(
                  icon: LucideIcons.skipForward,
                  iconColor: AfColors.textSecondary,
                  title: 'Gapless playback',
                  subtitle: 'Seamless transitions between tracks',
                  onTap: () => showGaplessDialog(context, ref),
                ),
                PrefetchToggle(svc: svc),
              ],
            ),

            const SizedBox(height: AfSpacing.s16),

            // ── Advanced ───────────────────────────────────────────────
            const SettingsLabel('Advanced'),
            SettingsGroup(
              children: [
                SettingsTile(
                  icon: LucideIcons.trash2,
                  iconColor: AfColors.textSecondary,
                  title: 'Clear app data',
                  subtitle: 'Reset app to initial state',
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
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text(
                                  'Clear data',
                                  style: TextStyle(
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

                      // Close the database connection before deleting the file!
                      final db = ref.read(appDatabaseProvider);
                      await db.close();

                      final dbFolder = await getApplicationDocumentsDirectory();
                      final dbFile = File(
                        p.join(dbFolder.path, 'aetherfin_drift.db'),
                      );
                      if (dbFile.existsSync()) {
                        await dbFile.delete();
                      }

                      // Invalidate the provider so a fresh database is opened on next request.
                      ref.invalidate(appDatabaseProvider);

                      await AppModeStore.clear();
                      ref.read(appModeProvider.notifier).state = null;
                      ref.read(localOnboardingCompletedProvider.notifier).state = false;
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

            // ── About ──────────────────────────────────────────────────
            const SettingsLabel('About'),
            SettingsGroup(
              children: [
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snap) {
                    final version = snap.data != null
                        ? 'v${snap.data!.version}+${snap.data!.buildNumber} ($kBuildId)'
                        : '...';
                    return SettingsTile(
                      icon: LucideIcons.info,
                      iconColor: AfColors.textSecondary,
                      title: 'Aetherfin $version',
                      subtitle: 'Jellyfin-backed music player · FOSS',
                    );
                  },
                ),
                SettingsTile(
                  icon: LucideIcons.code,
                  iconColor: AfColors.textSecondary,
                  title: 'Source code',
                  subtitle: 'github.com/Aetherfin/mobile-app',
                  trailing: const Icon(
                    Icons.open_in_new_rounded,
                    color: AfColors.textTertiary,
                    size: 16,
                  ),
                  onTap: () => launchSettingsUrl(
                    'https://github.com/Aetherfin/mobile-app',
                  ),
                ),
                SettingsTile(
                  icon: LucideIcons.fileText,
                  iconColor: AfColors.textSecondary,
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
    return SettingsTile(
      icon: LucideIcons.database,
      iconColor: AfColors.textSecondary,
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
