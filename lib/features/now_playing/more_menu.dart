import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show Device;

import '../../core/audio/play_actions.dart';
import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/af_dialog.dart';
import '../../widgets/bottom_sheet.dart';
import '../../widgets/save_to_playlist_sheet.dart';
import '../../widgets/track_details_sheet.dart';
import 'sleep_timer_dialog.dart';

// ─────────────────────────────────────────────────────────────────────────────
// More sheet
// ─────────────────────────────────────────────────────────────────────────────

void showMoreSheet(BuildContext context, WidgetRef ref) {
  final pageNotifier = ValueNotifier<_MorePage>(_MorePage.menu);

  showBlurBottomSheet<void>(
    context: context,
    builder: (context, dismiss) => ValueListenableBuilder<_MorePage>(
      valueListenable: pageNotifier,
      builder: (context, page, _) {
        if (page == _MorePage.details) {
          final track = ref.read(currentTrackProvider);
          if (track == null) {
            pageNotifier.value = _MorePage.menu;
            return const SizedBox.shrink();
          }
          return _DetailsView(
            track: track,
            onBack: () => pageNotifier.value = _MorePage.menu,
          );
        }
        return _MoreMenu(
          dismiss: dismiss,
          context: context,
          ref: ref,
          pageNotifier: pageNotifier,
        );
      },
    ),
  );
}

enum _MorePage { menu, details }

class _MoreMenu extends StatelessWidget {
  const _MoreMenu({
    required this.dismiss,
    required this.context,
    required this.ref,
    required this.pageNotifier,
  });

  final void Function() dismiss;
  final BuildContext context;
  final WidgetRef ref;
  final ValueNotifier<_MorePage> pageNotifier;

  @override
  Widget build(BuildContext context) {
    final track = ref.watch(currentTrackProvider);
    final savedIds = ref.watch(savedTrackIdsProvider);
    final serverIds = ref
        .watch(playlistTrackIdsProvider)
        .maybeWhen(data: (ids) => ids, orElse: () => const <String>{});
    final spectral = ref.watch(currentSpectralProvider);
    final isSaved =
        track != null &&
        (savedIds.contains(track.id) || serverIds.contains(track.id));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Quick actions ──
        MoreItem(
          icon: const Icon(
            LucideIcons.radio,
            size: 22,
            color: AfColors.textSecondary,
          ),
          label: 'Start radio',
          onTap: () async {
            dismiss();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Starting Instant Mix…'),
                  duration: AfDurations.snackBarInfo,
                ),
              );
            }
            await ref.read(playActionsProvider).playInstantMix(track!);
          },
        ),
        MoreItem(
          icon: const Icon(
            LucideIcons.slidersHorizontal,
            size: 22,
            color: AfColors.textSecondary,
          ),
          label: 'EQ',
          onTap: () {
            dismiss();
            context.push('/eq-dsp');
          },
        ),
        MoreItem(
          icon: Icon(
            LucideIcons.plus,
            size: 22,
            color: isSaved ? spectral.primary : AfColors.textSecondary,
          ),
          label: isSaved ? 'Saved' : 'Save',
          onTap: () {
            dismiss();
            showSaveDialog(this.context, ref);
          },
        ),
        MoreItem(
          icon: const Icon(
            LucideIcons.listMusic,
            size: 22,
            color: AfColors.textSecondary,
          ),
          label: 'Queue',
          onTap: () {
            dismiss();
            context.push('/queue');
          },
        ),
        if (track?.albumId != null)
          MoreItem(
            icon: const Icon(
              LucideIcons.disc3,
              size: 22,
              color: AfColors.textSecondary,
            ),
            label: 'Go to album',
            onTap: () {
              dismiss();
              context.push('/album/${track!.albumId}');
            },
          ),
        if (track?.artistId != null)
          MoreItem(
            icon: const Icon(
              LucideIcons.user,
              size: 22,
              color: AfColors.textSecondary,
            ),
            label: 'Go to artist',
            onTap: () {
              dismiss();
              context.push('/artist/${track!.artistId}');
            },
          ),
        const Divider(height: 1, color: AfColors.surfaceHigh),
        // ── Advanced actions ──
        MoreItem(
          icon: Icon(
            LucideIcons.arrowLeftRight,
            size: 22,
            color: ref.watch(abLoopAProvider) != null
                ? spectral.primary
                : AfColors.textSecondary,
          ),
          label: 'A-B Loop',
          onTap: () {
            dismiss();
            showAbLoopDialog(this.context, ref);
          },
        ),
        MoreItem(
          icon: const Icon(
            LucideIcons.moon,
            size: 22,
            color: AfColors.textSecondary,
          ),
          label: 'Sleep timer',
          onTap: () {
            dismiss();
            showSleepDialog(this.context, ref);
          },
        ),
        MoreItem(
          icon: const Icon(
            LucideIcons.gauge,
            size: 22,
            color: AfColors.textSecondary,
          ),
          label: 'Playback speed',
          onTap: () {
            dismiss();
            showSpeedDialog(this.context, ref);
          },
        ),
        MoreItem(
          icon: const Icon(
            LucideIcons.cast,
            size: 22,
            color: AfColors.textSecondary,
          ),
          label: 'Audio output',
          onTap: () {
            dismiss();
            showOutputDialog(this.context, ref);
          },
        ),
        MoreItem(
          icon: const Icon(
            LucideIcons.volume2,
            size: 22,
            color: AfColors.textSecondary,
          ),
          label: 'Volume',
          onTap: () {
            dismiss();
            showVolumeDialog(this.context, ref);
          },
        ),
        MoreItem(
          icon: const Icon(
            LucideIcons.bluetooth,
            size: 22,
            color: AfColors.textSecondary,
          ),
          label: 'Audio delay',
          onTap: () {
            dismiss();
            showAudioDelayDialog(this.context, ref);
          },
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: AfSpacing.s24),
          child: MoreItem(
            icon: const Icon(
              LucideIcons.info,
              size: 22,
              color: AfColors.textSecondary,
            ),
            label: 'Show details',
            onTap: () {
              pageNotifier.value = _MorePage.details;
            },
          ),
        ),
      ],
    );
  }
}

class _DetailsView extends ConsumerWidget {
  const _DetailsView({required this.track, required this.onBack});

  final AfTrack track;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _TrackDetailsWrapper(track: track, onBack: onBack);
  }
}

class _TrackDetailsWrapper extends StatefulWidget {
  const _TrackDetailsWrapper({required this.track, required this.onBack});

  final AfTrack track;
  final VoidCallback onBack;

  @override
  State<_TrackDetailsWrapper> createState() => _TrackDetailsWrapperState();
}

class _TrackDetailsWrapperState extends State<_TrackDetailsWrapper> {
  @override
  void initState() {
    super.initState();
    HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onBack();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AfSpacing.s4,
              vertical: AfSpacing.s4,
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(
                    LucideIcons.arrowLeft,
                    color: AfColors.textPrimary,
                    size: 22,
                  ),
                  onPressed: widget.onBack,
                ),
                const SizedBox(width: AfSpacing.s8),
                Text('Track Details', style: AfTypography.titleSmall),
              ],
            ),
          ),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 400),
              child: TrackDetailsBody(track: widget.track),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Volume dialog
// ─────────────────────────────────────────────────────────────────────────────

void showVolumeDialog(BuildContext context, WidgetRef ref) {
  final svc = ref.read(playerServiceProvider);
  final spectral = ref.read(currentSpectralProvider);
  double volume = svc.volume;
  bool muted = svc.isMuted;
  showBlurDialog<void>(
    context: context,
    builder: (context, dismiss) => StatefulBuilder(
      builder: (ctx, setDialogState) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Volume', style: AfTypography.titleMedium),
              const Spacer(),
              IconButton(
                icon: Icon(
                  muted ? LucideIcons.volumeX : LucideIcons.volume2,
                  color: AfColors.textPrimary,
                  size: 24,
                ),
                onPressed: () {
                  muted = !muted;
                  svc.setMute(muted);
                  setDialogState(() {});
                },
              ),
            ],
          ),
          const SizedBox(height: AfSpacing.s16),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: spectral.primary,
              inactiveTrackColor: AfColors.surfaceHigh,
              thumbColor: spectral.primary,
              overlayColor: spectral.primary.withValues(alpha: 0.1),
            ),
            child: Slider(
              value: volume.clamp(0, 150),
              min: 0,
              max: 150,
              divisions: 30,
              label: '${volume.round()}%',
              onChanged: (v) {
                volume = v;
                svc.setVolume(v);
                setDialogState(() {});
              },
            ),
          ),
          Text(
            '${volume.round()}%',
            style: AfTypography.mono.copyWith(color: AfColors.textTertiary),
          ),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Audio delay dialog
// ─────────────────────────────────────────────────────────────────────────────

void showAudioDelayDialog(BuildContext context, WidgetRef ref) {
  final svc = ref.read(playerServiceProvider);
  final spectral = ref.read(currentSpectralProvider);
  double delayMs = svc.audioDelay.inMilliseconds.toDouble();
  showBlurDialog<void>(
    context: context,
    builder: (context, dismiss) => StatefulBuilder(
      builder: (ctx, setDialogState) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Audio delay', style: AfTypography.titleMedium),
          const SizedBox(height: AfSpacing.s12),
          Text(
            'Shift audio timing for Bluetooth sync',
            style: AfTypography.bodySmall.copyWith(
              color: AfColors.textTertiary,
            ),
          ),
          const SizedBox(height: AfSpacing.s16),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: spectral.primary,
              inactiveTrackColor: AfColors.surfaceHigh,
              thumbColor: spectral.primary,
              overlayColor: spectral.primary.withValues(alpha: 0.1),
            ),
            child: Slider(
              value: delayMs.clamp(-500, 500),
              min: -500,
              max: 500,
              divisions: 20,
              label: '${delayMs.round()} ms',
              onChanged: (v) {
                delayMs = v;
                svc.setAudioDelay(Duration(milliseconds: v.round()));
                setDialogState(() {});
              },
            ),
          ),
          Text(
            '${delayMs.round()} ms',
            style: AfTypography.mono.copyWith(color: AfColors.textTertiary),
          ),
          const SizedBox(height: AfSpacing.s24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  delayMs = 0;
                  svc.setAudioDelay(Duration.zero);
                  setDialogState(() {});
                },
                child: const Text('Reset'),
              ),
              const SizedBox(width: AfSpacing.s8),
              TextButton(onPressed: () => dismiss(), child: const Text('Done')),
            ],
          ),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// A-B Loop dialog
// ─────────────────────────────────────────────────────────────────────────────

void showAbLoopDialog(BuildContext context, WidgetRef ref) {
  final svc = ref.read(playerServiceProvider);
  final spectral = ref.read(currentSpectralProvider);
  showBlurDialog<void>(
    context: context,
    builder: (context, dismiss) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('A-B Loop', style: AfTypography.titleMedium),
        const SizedBox(height: AfSpacing.s12),
        Text(
          'Set markers to loop a section of the track.',
          style: AfTypography.bodySmall.copyWith(color: AfColors.textTertiary),
        ),
        const SizedBox(height: AfSpacing.s16),
        FilledButton.icon(
          onPressed: () async {
            final pos = await svc.getRawPosition();
            await svc.setAbLoopA(pos);
            ref.read(abLoopAProvider.notifier).state = pos;
            dismiss();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Loop start: ${fmtDuration(pos)}')),
              );
            }
          },
          icon: const Icon(LucideIcons.flag, size: 18),
          label: const Text('Set A (start)'),
          style: FilledButton.styleFrom(
            backgroundColor: spectral.primary,
            foregroundColor: AfColors.surfaceCanvas,
          ),
        ),
        const SizedBox(height: AfSpacing.s8),
        FilledButton.icon(
          onPressed: () async {
            final pos = await svc.getRawPosition();
            await svc.setAbLoopB(pos);
            ref.read(abLoopBProvider.notifier).state = pos;
            dismiss();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Loop end: ${fmtDuration(pos)}')),
              );
            }
          },
          icon: const Icon(LucideIcons.flag, size: 18),
          label: const Text('Set B (end)'),
          style: FilledButton.styleFrom(
            backgroundColor: spectral.primary,
            foregroundColor: AfColors.surfaceCanvas,
          ),
        ),
        const SizedBox(height: AfSpacing.s8),
        OutlinedButton.icon(
          onPressed: () async {
            await svc.setAbLoopA(null);
            await svc.setAbLoopB(null);
            ref.read(abLoopAProvider.notifier).state = null;
            ref.read(abLoopBProvider.notifier).state = null;
            dismiss();
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('A-B loop cleared')));
            }
          },
          icon: const Icon(LucideIcons.x, size: 18),
          label: const Text('Clear loop'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AfColors.semanticError,
            side: const BorderSide(color: AfColors.surfaceHigh),
          ),
        ),
      ],
    ),
  );
}

String fmtDuration(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}

// ─────────────────────────────────────────────────────────────────────────────
// Save dialog
// ─────────────────────────────────────────────────────────────────────────────

void showSaveDialog(BuildContext context, WidgetRef ref) {
  final track = ref.read(currentTrackProvider);
  if (track == null) return;
  showSaveToPlaylistSheet(context, ref, track);
}

// ─────────────────────────────────────────────────────────────────────────────
// Speed dialog
// ─────────────────────────────────────────────────────────────────────────────

void showSpeedDialog(BuildContext context, WidgetRef ref) {
  const speeds = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
  final current = ref.read(playerServiceProvider).speed;
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
          child: Text('Playback speed', style: AfTypography.titleSmall),
        ),
        const SizedBox(height: AfSpacing.s8),
        for (final s in speeds)
          ListTile(
            title: Text(
              '${s.toStringAsFixed(s == s.roundToDouble() ? 1 : 2)}×',
              style: AfTypography.bodyMedium,
            ),
            trailing: (s - current).abs() < 0.001
                ? const Icon(LucideIcons.check, size: 20)
                : null,
            onTap: () {
              unawaited(ref.read(playerServiceProvider).setAfSpeed(s));
              dismiss();
            },
          ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Sleep dialog
// ─────────────────────────────────────────────────────────────────────────────

void showSleepDialog(BuildContext context, WidgetRef ref) {
  showBlurBottomSheet<void>(
    context: context,
    builder: (context, dismiss) => SleepTimerDialogContent(dismiss: dismiss),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Output dialog
// ─────────────────────────────────────────────────────────────────────────────

void showOutputDialog(BuildContext context, WidgetRef ref) {
  showBlurBottomSheet<void>(
    context: context,
    builder: (context, dismiss) => ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360, maxHeight: 480),
      child: OutputDialogContent(dismiss: dismiss),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Output dialog content
// ─────────────────────────────────────────────────────────────────────────────

class OutputDialogContent extends ConsumerWidget {
  const OutputDialogContent({super.key, required this.dismiss});

  final void Function() dismiss;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final svc = ref.watch(playerServiceProvider);
    final spectral = ref.watch(currentSpectralProvider);

    return StreamBuilder<List<Device>>(
      stream: svc.audioDevicesStream,
      initialData: svc.audioDevices,
      builder: (context, devicesSnap) {
        return StreamBuilder<Device>(
          stream: svc.audioDeviceStream,
          initialData: svc.audioDevice,
          builder: (context, activeSnap) {
            final devices = devicesSnap.data ?? [];
            final active = activeSnap.data;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: AfSpacing.s16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AfSpacing.gutterGenerous,
                    ),
                    child: Text('Output', style: AfTypography.titleSmall),
                  ),
                  const SizedBox(height: AfSpacing.s8),
                  if (devices.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(AfSpacing.gutterGenerous),
                      child: Text(
                        'No audio devices found.\nStart playback first.',
                        style: AfTypography.bodyMedium.copyWith(
                          color: AfColors.textTertiary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    ...devices.map((device) {
                      final isActive = active?.name == device.name;
                      return ListTile(
                        leading: iconForDevice(
                          device.description.isNotEmpty
                              ? device.description
                              : device.name,
                          color: isActive
                              ? spectral.primary
                              : AfColors.textSecondary,
                        ),
                        title: Text(
                          device.description.isNotEmpty
                              ? device.description
                              : device.name,
                          style: AfTypography.bodyMedium,
                        ),
                        trailing: isActive
                            ? Icon(
                                LucideIcons.check,
                                color: spectral.primary,
                                size: 20,
                              )
                            : null,
                        onTap: () async {
                          await svc.setAudioDevice(device);
                          dismiss();
                        },
                      );
                    }),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget iconForDevice(String name, {required Color color}) {
    final n = name.toLowerCase();
    if (n.contains('bluetooth') || n.contains('bt')) {
      return Icon(LucideIcons.bluetooth, color: color, size: 22);
    }
    if (n.contains('headphone') ||
        n.contains('headset') ||
        n.contains('earphone') ||
        n.contains('airpod')) {
      return Icon(LucideIcons.headphones, color: color, size: 22);
    }
    if (n.contains('speaker')) {
      return Icon(LucideIcons.speaker, color: color, size: 22);
    }
    if (n.contains('hdmi')) {
      return Icon(LucideIcons.monitor, color: color, size: 22);
    }
    if (n.contains('usb')) {
      return Icon(LucideIcons.usb, color: color, size: 22);
    }
    return Icon(LucideIcons.smartphone, color: color, size: 22);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// More item
// ─────────────────────────────────────────────────────────────────────────────

class MoreItem extends StatelessWidget {
  const MoreItem({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final Widget icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AfSpacing.gutterGenerous,
          vertical: AfSpacing.s12,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(width: 22, height: 22, child: Center(child: icon)),
            const SizedBox(width: AfSpacing.s16),
            SizedBox(
              height: 20,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(label, style: AfTypography.bodyMedium),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
