import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show Loop;

import '../../core/audio/af_loop_mode.dart';
import '../../core/audio/shuffle_mode.dart';
import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/af_dialog.dart';
import '../../widgets/press_scale.dart';

/// Transport controls — play/pause/skip/shuffle/repeat.
///
/// Watches playing/shuffle/loop — rebuilds on transport state changes only.
class ReactiveTransport extends ConsumerWidget {
  const ReactiveTransport({super.key, required this.track});
  final AfTrack track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPlaying = ref
        .watch(playingStreamProvider)
        .maybeWhen(data: (v) => v, orElse: () => false);
    final shuffleMode = ref
        .watch(shuffleModeProvider)
        .maybeWhen(data: (v) => v, orElse: () => ShuffleMode.off);
    final loopMode = ref
        .watch(loopModeProvider)
        .maybeWhen(data: (v) => v, orElse: () => AfLoopMode.off);
    final spectral = ref.watch(currentSpectralProvider);

    return TransportRow(
      isPlaying: isPlaying,
      shuffleOn: shuffleMode != ShuffleMode.off,
      shuffleMode: shuffleMode,
      loopMode: loopMode,
      repeatCount: ref.watch(repeatCountProvider),
      accent: spectral.energy,
      onShuffle: () {
        final svc = ref.read(playerServiceProvider);
        unawaited(
          svc.setAfShuffleMode(!svc.isShuffleEnabled).catchError((_) {}),
        );
      },
      onShuffleLongPress: () => _showShuffleOptions(context, ref),
      onRepeat: () {
        final svc = ref.read(playerServiceProvider);
        final currentMode = ref
            .read(loopModeProvider)
            .maybeWhen(data: (v) => v, orElse: () => AfLoopMode.off);
        switch (currentMode) {
          case AfLoopMode.off:
            unawaited(svc.setAfLoopMode(Loop.playlist).catchError((_) {}));
            break;
          case AfLoopMode.playlist:
            unawaited(svc.setAfLoopMode(Loop.file).catchError((_) {}));
            break;
          case AfLoopMode.file:
            ref.read(forNtimesModeProvider.notifier).state = true;
            unawaited(svc.setAfForNtimes(true).catchError((_) {}));
            break;
          case AfLoopMode.forNtimes:
            ref.read(forNtimesModeProvider.notifier).state = false;
            svc.setLoopModeOffSync();
            unawaited(svc.setAfForNtimes(false).catchError((_) {}));
            break;
        }
      },
      onPlayPause: () {
        final svc = ref.read(playerServiceProvider);
        isPlaying ? svc.pause() : svc.play();
      },
      onPrev: () => ref.read(playerServiceProvider).skipToPrevious(),
      onNext: () => ref.read(playerServiceProvider).skipToNext(),
    );
  }

  void _showShuffleOptions(BuildContext context, WidgetRef ref) {
    showBlurDialog(
      context: context,
      builder: (context, dismiss) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Shuffle options', style: AfTypography.titleMedium),
          const SizedBox(height: AfSpacing.s16),
          ListTile(
            leading: const Icon(LucideIcons.shuffle),
            title: const Text('Shuffle all'),
            onTap: () {
              dismiss();
              ref.read(playerServiceProvider).setAfShuffleMode(true);
            },
          ),
          ListTile(
            leading: const Icon(LucideIcons.arrowDownWideNarrow),
            title: const Text('Shuffle next'),
            subtitle: const Text('Only upcoming tracks'),
            onTap: () {
              dismiss();
              ref.read(playerServiceProvider).setAfShuffleTail();
            },
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Transport row — pure widget, no Riverpod
// ─────────────────────────────────────────────────────────────────────────────

class TransportRow extends StatelessWidget {
  const TransportRow({
    super.key,
    required this.isPlaying,
    required this.shuffleOn,
    required this.shuffleMode,
    required this.loopMode,
    required this.repeatCount,
    required this.accent,
    required this.onPlayPause,
    required this.onPrev,
    required this.onNext,
    required this.onShuffle,
    required this.onShuffleLongPress,
    required this.onRepeat,
  });
  final bool isPlaying;
  final bool shuffleOn;
  final ShuffleMode shuffleMode;
  final AfLoopMode loopMode;
  final int repeatCount;
  final Color accent;
  final VoidCallback onPlayPause;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onShuffle;
  final VoidCallback onShuffleLongPress;
  final VoidCallback onRepeat;

  static IconData _loopIcon(AfLoopMode mode) {
    return switch (mode) {
      AfLoopMode.file => LucideIcons.repeat1,
      AfLoopMode.playlist => LucideIcons.repeat,
      AfLoopMode.off => LucideIcons.repeat,
      AfLoopMode.forNtimes => LucideIcons.repeat,
    };
  }

  static Color _loopColor(AfLoopMode mode, Color accent) {
    return mode == AfLoopMode.off ? AfColors.textTertiary : accent;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Shuffle
        GestureDetector(
          onLongPress: onShuffleLongPress,
          child: TransportButton(
            icon: Icon(
              shuffleMode == ShuffleMode.tail
                  ? LucideIcons.arrowDownWideNarrow
                  : LucideIcons.shuffle,
              size: 20,
              color: shuffleOn ? accent : AfColors.textTertiary,
            ),
            onTap: onShuffle,
          ),
        ),
        const SizedBox(width: AfSpacing.s12),
        // Previous
        Semantics(
          label: 'Previous track',
          child: TransportButton(
            icon: const Icon(
              LucideIcons.skipBack,
              size: 26,
              color: AfColors.textPrimary,
            ),
            onTap: onPrev,
          ),
        ),
        const SizedBox(width: AfSpacing.s16),
        // Play / Pause — spectral glow
        Semantics(
          label: isPlaying ? 'Pause' : 'Play',
          child: PlayButton(
            isPlaying: isPlaying,
            accent: accent,
            onTap: onPlayPause,
          ),
        ),
        const SizedBox(width: AfSpacing.s16),
        // Next
        Semantics(
          label: 'Next track',
          child: TransportButton(
            icon: const Icon(
              LucideIcons.skipForward,
              size: 26,
              color: AfColors.textPrimary,
            ),
            onTap: onNext,
          ),
        ),
        const SizedBox(width: AfSpacing.s12),
        // Repeat
        TransportButton(
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                _loopIcon(loopMode),
                size: 20,
                color: _loopColor(loopMode, accent),
              ),
              if (loopMode == AfLoopMode.forNtimes)
                Positioned(
                  right: -6,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: AfColors.accentMuted,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$repeatCount',
                      style: AfTypography.caption.copyWith(
                        color: AfColors.textOnPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          onTap: onRepeat,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared transport widgets
// ─────────────────────────────────────────────────────────────────────────────

class TransportButton extends StatelessWidget {
  const TransportButton({super.key, required this.icon, required this.onTap});
  final Widget icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: SizedBox(
        width: AfSpacing.minHitTarget,
        height: AfSpacing.minHitTarget,
        child: Center(child: icon),
      ),
    );
  }
}

/// Play/pause button with spectral ambient glow.
/// 64dp circle with [accent] background and a pulsing outer glow shadow
/// driven by the spectral energy color.
class PlayButton extends ConsumerWidget {
  const PlayButton({
    super.key,
    required this.isPlaying,
    required this.accent,
    required this.onTap,
  });
  final bool isPlaying;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isBuffering = ref.watch(isBufferingProvider);
    return PressScale(
      ensureHitTarget: false,
      onTap: onTap,
      child: Container(
        width: AfSpacing.playButtonSize,
        height: AfSpacing.playButtonSize,
        decoration: BoxDecoration(
          color: accent,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.40),
              blurRadius: 24,
              spreadRadius: 2,
            ),
            BoxShadow(
              color: accent.withValues(alpha: 0.15),
              blurRadius: 48,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Center(
          child: isBuffering
              ? SizedBox(
                  width: AfSpacing.s24,
                  height: AfSpacing.s24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: _contrastColor(accent),
                  ),
                )
              : Icon(
                  isPlaying ? LucideIcons.pause : LucideIcons.play,
                  color: _contrastColor(accent),
                  size: 28,
                ),
        ),
      ),
    );
  }

  /// Returns black or white depending on the accent color luminance
  /// for maximum contrast on the spectral background.
  static Color _contrastColor(Color accent) {
    return accent.computeLuminance() > 0.45
        ? AfColors.surfaceCanvas
        : AfColors.textOnPrimary;
  }
}
