import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart'
    show Cache, Format, Gapless, ReplayGain, ReplayGainSettings;
import 'package:url_launcher/url_launcher.dart';

import '../../core/audio/offline_cache_service.dart';
import '../../core/audio/player_settings_store.dart';
import '../../core/lastfm/lastfm_client.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/af_dialog.dart';
import '../../widgets/bottom_sheet.dart';
import 'settings_widgets.dart';

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

void showAudioBufferDialog(BuildContext context, WidgetRef ref) {
  const options = <(int, String)>[
    (50, '50 ms (low latency)'),
    (100, '100 ms'),
    (200, '200 ms (default)'),
    (500, '500 ms (stable)'),
    (1000, '1000 ms (very stable)'),
  ];

  final currentMs = ref.read(playerServiceProvider).audioBuffer.inMilliseconds;
  final effectiveMs = currentMs > 0 ? currentMs : 200;

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
          child: Text('Audio buffer', style: AfTypography.titleSmall),
        ),
        const SizedBox(height: AfSpacing.s4),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AfSpacing.gutterGenerous,
          ),
          child: Text(
            'Lower = less latency. Higher = more stable on slow networks.',
            style: AfTypography.bodySmall.copyWith(
              color: AfColors.textTertiary,
            ),
          ),
        ),
        const SizedBox(height: AfSpacing.s8),
        for (final (ms, label) in options)
          OptionTile(
            label: label,
            isActive: ms == effectiveMs,
            onTap: () {
              unawaited(
                ref
                    .read(playerServiceProvider)
                    .setAudioBuffer(Duration(milliseconds: ms)),
              );
              unawaited(PlayerSettingsStore.saveBufferMs(ms));
              dismiss();
            },
          ),
      ],
    ),
  );
}

void showGaplessDialog(BuildContext context, WidgetRef ref) {
  final svc = ref.read(playerServiceProvider);
  final current = svc.gaplessMode;

  const options = <(Gapless, String, String)>[
    (Gapless.yes, 'Full', 'Re-uses decoder for seamless transitions'),
    (Gapless.weak, 'Weak', 'Gapless only on compatible formats (default)'),
    (Gapless.no, 'Off', 'Close and re-open audio output between tracks'),
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
          child: Text('Gapless playback', style: AfTypography.titleSmall),
        ),
        const SizedBox(height: AfSpacing.s4),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AfSpacing.gutterGenerous,
          ),
          child: Text(
            'Controls how the player handles track transitions.',
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
            isActive: mode == current,
            onTap: () {
              unawaited(svc.setGapless(mode));
              unawaited(PlayerSettingsStore.saveGapless(mode));
              dismiss();
            },
          ),
      ],
    ),
  );
}

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
              activeColor: AfColors.accentPrimary,
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
                  activeColor: AfColors.accentPrimary,
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
              activeThumbColor: AfColors.accentPrimary,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ],
    );
  }
}

/// Bottom sheet to pick max offline cache size.
void showOfflineCacheSizeDialog(BuildContext context, WidgetRef ref) {
  const options = <(int, String)>[
    (500 * 1024 * 1024, '500 MB'),
    (1024 * 1024 * 1024, '1 GB'),
    (2 * 1024 * 1024 * 1024, '2 GB'),
    (5 * 1024 * 1024 * 1024, '5 GB'),
    (10 * 1024 * 1024 * 1024, '10 GB'),
  ];

  final currentSize = ref.read(offlineCacheMaxSizeProvider);
  final label = OfflineCacheService.formatSize(currentSize);

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
          child: Text('Max cache size', style: AfTypography.titleSmall),
        ),
        const SizedBox(height: AfSpacing.s4),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AfSpacing.gutterGenerous,
          ),
          child: Text(
            'Currently: $label',
            style: AfTypography.bodySmall.copyWith(
              color: AfColors.textTertiary,
            ),
          ),
        ),
        const SizedBox(height: AfSpacing.s8),
        for (final (bytes, label) in options)
          OptionTile(
            label: label,
            isActive: bytes == currentSize,
            onTap: () {
              ref.read(offlineCacheMaxSizeProvider.notifier).state = bytes;
              unawaited(PlayerSettingsStore.saveOfflineCacheMaxSize(bytes));
              // Trigger eviction with new limit.
              final cache = ref.read(offlineCacheServiceProvider);
              unawaited(cache.evictLRU(maxCacheSizeBytes: bytes));
              dismiss();
            },
          ),
      ],
    ),
  );
}

/// Confirmation dialog for clearing the offline cache.
Future<bool> showOfflineCacheClearDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final cache = ref.read(offlineCacheServiceProvider);
  final size = await cache.cacheSize();
  final count = await cache.cachedCount();
  final label = size > 0 ? OfflineCacheService.formatSize(size) : '0 B';

  if (!context.mounted) return false;

  final confirmed = await showBlurDialog<bool>(
    context: context,
    builder: (context, dismiss) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Clear offline cache?', style: AfTypography.titleMedium),
        const SizedBox(height: AfSpacing.s12),
        Text(
          count == 1
              ? '1 cached track ($label) will be deleted.'
              : '$count cached tracks ($label) will be deleted.',
          style: AfTypography.bodyMedium,
        ),
        const SizedBox(height: AfSpacing.s24),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => dismiss(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => dismiss(true),
              child: Text(
                'Clear cache',
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
  return confirmed == true;
}

/// Bottom sheet to pick streaming quality (max bitrate).
void showStreamingQualityDialog(BuildContext context, WidgetRef ref) {
  const options = <(int, String, String?)>[
    (
      0,
      'Original / Lossless',
      'Stream original audio files without transcoding',
    ),
    (320, '320 kbps', 'High quality compressed stream'),
    (256, '256 kbps', 'Very good balance of quality and speed'),
    (192, '192 kbps', 'Medium quality, standard compression'),
    (128, '128 kbps', 'Low quality, recommended for cellular data'),
    (96, '96 kbps', 'Data saver, uses minimal bandwidth'),
  ];

  final currentQuality = ref.read(maxBitrateProvider);

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
          child: Text('Streaming quality', style: AfTypography.titleSmall),
        ),
        const SizedBox(height: AfSpacing.s4),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AfSpacing.gutterGenerous,
          ),
          child: Text(
            'Limits the stream bitrate. Transcoding is performed on-the-fly by the server if needed.',
            style: AfTypography.bodySmall.copyWith(
              color: AfColors.textTertiary,
            ),
          ),
        ),
        const SizedBox(height: AfSpacing.s8),
        for (final (kbps, label, subtitle) in options)
          OptionTile(
            label: label,
            subtitle: subtitle,
            isActive: kbps == currentQuality,
            onTap: () {
              ref.read(maxBitrateProvider.notifier).state = kbps;
              unawaited(PlayerSettingsStore.saveMaxBitrate(kbps));
              dismiss();
            },
          ),
      ],
    ),
  );
}

void showAppIconDialog(BuildContext context, WidgetRef ref) {
  final currentIcon = ref.read(appIconProvider);

  final options = <(String, String, String)>[
    ('DefaultIcon', 'Default', 'Standard Aurora Purple themed icon'),
    ('MidnightIcon', 'Midnight', 'Sleek dark themed icon'),
    ('NordicIcon', 'Nordic', 'Cool ocean blue themed icon'),
    ('SunsetIcon', 'Sunset', 'Warm sunset red/amber themed icon'),
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
          child: Text('App icon', style: AfTypography.titleSmall),
        ),
        const SizedBox(height: AfSpacing.s4),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AfSpacing.gutterGenerous,
          ),
          child: Text(
            "Choose a custom theme for Aetherfin's launcher icon.",
            style: AfTypography.bodySmall.copyWith(
              color: AfColors.textTertiary,
            ),
          ),
        ),
        const SizedBox(height: AfSpacing.s8),
        for (final (iconName, label, description) in options)
          OptionTile(
            label: label,
            subtitle: description,
            isActive: iconName == currentIcon,
            onTap: () {
              unawaited(ref.read(appIconProvider.notifier).setIcon(iconName));
              dismiss();
            },
          ),
      ],
    ),
  );
}

void showLastFmApiConfigDialog(BuildContext context, WidgetRef ref) {
  final apiKeyController = TextEditingController(
    text: ref.read(lastfmApiKeyProvider),
  );
  final apiSecretController = TextEditingController(
    text: ref.read(lastfmApiSecretProvider),
  );

  showBlurDialog(
    context: context,
    builder: (context, dismiss) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Last.fm API Credentials', style: AfTypography.titleMedium),
        const SizedBox(height: AfSpacing.s12),
        Text(
          'To enable Last.fm scrobbling, you need your own API credentials.',
          style: AfTypography.bodyMedium,
        ),
        const SizedBox(height: AfSpacing.s8),
        InkWell(
          onTap: () => launchUrl(
            Uri.parse('https://www.last.fm/api/account/create'),
            mode: LaunchMode.externalApplication,
          ),
          child: Text(
            'Create a developer account and register your API key at last.fm/api/account/create',
            style: AfTypography.bodySmall.copyWith(
              color: AfColors.accentPrimary,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
        const SizedBox(height: AfSpacing.s16),
        TextField(
          controller: apiKeyController,
          decoration: const InputDecoration(
            labelText: 'API Key',
            border: OutlineInputBorder(),
          ),
          style: AfTypography.bodyMedium,
        ),
        const SizedBox(height: AfSpacing.s12),
        TextField(
          controller: apiSecretController,
          decoration: const InputDecoration(
            labelText: 'API Secret',
            border: OutlineInputBorder(),
          ),
          style: AfTypography.bodyMedium,
        ),
        const SizedBox(height: AfSpacing.s24),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => dismiss(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final key = apiKeyController.text.trim();
                final secret = apiSecretController.text.trim();
                ref.read(lastfmApiKeyProvider.notifier).state = key;
                ref.read(lastfmApiSecretProvider.notifier).state = secret;
                unawaited(PlayerSettingsStore.saveLastFmApiKey(key));
                unawaited(PlayerSettingsStore.saveLastFmApiSecret(secret));
                dismiss();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ],
    ),
  );
}

void showLastFmLoginDialog(BuildContext context, WidgetRef ref) {
  showBlurDialog(
    context: context,
    builder: (context, dismiss) => _LastFmBrowserAuthDialog(dismiss: dismiss),
  );
}

/// Browser-based Last.fm auth dialog.
///
/// Flow:
/// 1. Get token via [LastFmClient.getToken].
/// 2. Open browser for user to authorize at `last.fm/api/auth`.
/// 3. Poll [LastFmClient.getSession] until user authorizes.
/// 4. Save session key.
class _LastFmBrowserAuthDialog extends ConsumerStatefulWidget {
  const _LastFmBrowserAuthDialog({required this.dismiss});
  final VoidCallback dismiss;
  @override
  ConsumerState<_LastFmBrowserAuthDialog> createState() =>
      _LastFmBrowserAuthDialogState();
}

class _LastFmBrowserAuthDialogState
    extends ConsumerState<_LastFmBrowserAuthDialog> {
  bool _loading = true;
  String? _token;
  bool _waiting = false;
  String? _username;
  String? _error;
  Timer? _pollTimer;
  String _apiKey = '';
  String _apiSecret = '';

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _startAuth() async {
    _apiKey = ref.read(lastfmApiKeyProvider);
    _apiSecret = ref.read(lastfmApiSecretProvider);
    if (_apiKey.isEmpty || _apiSecret.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'API credentials are missing. Set them first.';
      });
      return;
    }

    try {
      final client = LastFmClient(apiKey: _apiKey, apiSecret: _apiSecret);
      final token = await client.getToken();

      final url = client.authPageUrl(token);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

      setState(() {
        _loading = false;
        _token = token;
        _waiting = true;
      });

      _startPolling(client, token);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  void _startPolling(LastFmClient client, String token) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted) return;
      try {
        final sessionKey = await client.getSession(token);
        _pollTimer?.cancel();
        if (!mounted) return;

        ref.read(lastfmSessionKeyProvider.notifier).state = sessionKey;
        // Recreate client with session key so verifySession can use it
        final verifiedClient = LastFmClient(
          apiKey: _apiKey,
          apiSecret: _apiSecret,
          sessionKey: sessionKey,
        );
        final verifiedName = await verifiedClient.verifySession();
        if (!mounted) return;
        final username = verifiedName.isNotEmpty
            ? verifiedName
            : (_username ?? 'Last.fm');
        ref.read(lastfmUsernameProvider.notifier).state = username;
        unawaited(PlayerSettingsStore.saveLastFmSessionKey(sessionKey));
        unawaited(PlayerSettingsStore.saveLastFmUsername(username));

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connected to Last.fm as $username!')),
        );
        widget.dismiss();
      } catch (_) {}
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startAuth());
  }

  void _checkAgain() {
    if (_token == null) return;
    final apiKey = ref.read(lastfmApiKeyProvider);
    final apiSecret = ref.read(lastfmApiSecretProvider);
    if (apiKey.isEmpty || apiSecret.isEmpty) return;
    final client = LastFmClient(apiKey: apiKey, apiSecret: apiSecret);
    _startPolling(client, _token!);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Link Last.fm Account', style: AfTypography.titleMedium),
        const SizedBox(height: AfSpacing.s12),
        if (_loading) ...[
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: AfSpacing.s24),
              child: CircularProgressIndicator(),
            ),
          ),
        ] else if (_error != null) ...[
          Text(
            _error!,
            style: AfTypography.bodyMediumSmall.copyWith(
              color: AfColors.semanticError,
            ),
          ),
          const SizedBox(height: AfSpacing.s16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => widget.dismiss(),
                child: const Text('Close'),
              ),
              const SizedBox(width: AfSpacing.s8),
              TextButton(
                onPressed: () {
                  setState(() {
                    _error = null;
                    _loading = true;
                  });
                  _startAuth();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ] else if (_waiting) ...[
          Text(
            'Authorize Aetherfin in your browser, then come back here.',
            style: AfTypography.bodyMedium,
          ),
          const SizedBox(height: AfSpacing.s8),
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: AfSpacing.s12),
              Expanded(
                child: Text(
                  'Waiting for authorization…',
                  style: AfTypography.bodySmall.copyWith(
                    color: AfColors.textTertiary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AfSpacing.s16),
          if (_username != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'Last.fm Username (optional)',
                  hintText: 'Your Last.fm username',
                  border: OutlineInputBorder(),
                ),
                style: AfTypography.bodyMedium,
                autocorrect: false,
                onChanged: (v) => _username = v.trim(),
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  _pollTimer?.cancel();
                  widget.dismiss();
                },
                child: const Text('Cancel'),
              ),
              const SizedBox(width: AfSpacing.s8),
              TextButton(
                onPressed: () {
                  _pollTimer?.cancel();
                  _checkAgain();
                },
                child: const Text('Check Again'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

Future<void> showLastFmSignOutDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final confirmed = await showBlurDialog<bool>(
    context: context,
    builder: (context, dismiss) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Disconnect Last.fm?', style: AfTypography.titleMedium),
        const SizedBox(height: AfSpacing.s12),
        Text(
          'You will be signed out from Last.fm, and tracks will no longer be scrobbled.',
          style: AfTypography.bodyMedium,
        ),
        const SizedBox(height: AfSpacing.s24),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => dismiss(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => dismiss(true),
              child: Text(
                'Disconnect',
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

  if (confirmed == true) {
    ref.read(lastfmSessionKeyProvider.notifier).state = '';
    ref.read(lastfmUsernameProvider.notifier).state = '';
    unawaited(PlayerSettingsStore.saveLastFmSessionKey(''));
    unawaited(PlayerSettingsStore.saveLastFmUsername(''));

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Disconnected from Last.fm.')),
      );
    }
  }
}
