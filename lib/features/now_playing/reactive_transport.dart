import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show Loop;

import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import 'transport_widgets.dart';

class ReactiveTransport extends ConsumerWidget {
  const ReactiveTransport({super.key, required this.track});

  final AfTrack track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPlaying = ref.watch(playingStreamProvider).valueOrNull ?? false;
    final shuffleEnabled =
        ref.watch(shuffleModeProvider).valueOrNull ?? false;
    final loop = ref.watch(loopModeProvider).valueOrNull ?? Loop.off;

    final iconColor = Theme.of(context).colorScheme.onSurface;
    final accentColor = Theme.of(context).colorScheme.primary;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ShuffleButton(
              enabled: shuffleEnabled,
              iconColor: iconColor,
              accentColor: accentColor,
            ),
            const SizedBox(width: AfSpacing.s32),
            _PreviousButton(iconColor: iconColor),
            const SizedBox(width: AfSpacing.s32),
            PlayButton(isPlaying: isPlaying),
            const SizedBox(width: AfSpacing.s32),
            _NextButton(iconColor: iconColor),
            const SizedBox(width: AfSpacing.s32),
            _LoopButton(
              loop: loop,
              iconColor: iconColor,
              accentColor: accentColor,
            ),
          ],
        ),
        const SizedBox(height: AfSpacing.s24),
        const PlaybackSpeedSlider(),
      ],
    );
  }
}

class _ShuffleButton extends ConsumerWidget {
  const _ShuffleButton({
    required this.enabled,
    required this.iconColor,
    required this.accentColor,
  });

  final bool enabled;
  final Color iconColor;
  final Color accentColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TransportButton(
      icon: FaIcon(
        FontAwesomeIcons.shuffle,
        size: 20,
        color: enabled ? accentColor : iconColor.withValues(alpha: 0.7),
      ),
      onPressed: () => ref
          .read(playerServiceProvider)
          .setAfShuffleMode(!enabled),
    );
  }
}

class _PreviousButton extends ConsumerWidget {
  const _PreviousButton({required this.iconColor});

  final Color iconColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TransportButton(
      icon: FaIcon(
        FontAwesomeIcons.backwardStep,
        size: 22,
        color: iconColor.withValues(alpha: 0.7),
      ),
      onPressed: () => ref.read(playerServiceProvider).skipToPrevious(),
    );
  }
}

class _NextButton extends ConsumerWidget {
  const _NextButton({required this.iconColor});

  final Color iconColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TransportButton(
      icon: FaIcon(
        FontAwesomeIcons.forwardStep,
        size: 22,
        color: iconColor.withValues(alpha: 0.7),
      ),
      onPressed: () => ref.read(playerServiceProvider).skipToNext(),
    );
  }
}

class _LoopButton extends ConsumerWidget {
  const _LoopButton({
    required this.loop,
    required this.iconColor,
    required this.accentColor,
  });

  final Loop loop;
  final Color iconColor;
  final Color accentColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TransportButton(
      icon: FaIcon(
        switch (loop) {
          Loop.off => FontAwesomeIcons.rotateRight,
          Loop.playlist => FontAwesomeIcons.repeat,
          Loop.file => FontAwesomeIcons.arrowsSpin,
        },
        size: 20,
        color: loop != Loop.off
            ? accentColor
            : iconColor.withValues(alpha: 0.7),
      ),
      onPressed: () {
        final next = switch (loop) {
          Loop.off => Loop.playlist,
          Loop.playlist => Loop.file,
          Loop.file => Loop.off,
        };
        ref.read(playerServiceProvider).setAfLoopMode(next);
      },
    );
  }
}

class PlaybackSpeedSlider extends ConsumerWidget {
  const PlaybackSpeedSlider({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final speed = ref.watch(playbackSpeedProvider).valueOrNull ?? 1.0;
    return Row(
      children: [
        Text(
          '${speed.toStringAsFixed(1)}\u00d7',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6),
              ),
        ),
        Expanded(
          child: Slider(
            value: speed.clamp(0.5, 2.0),
            min: 0.5,
            max: 2.0,
            divisions: 15,
            label: '${speed.toStringAsFixed(1)}\u00d7',
            onChanged: (v) =>
                ref.read(playerServiceProvider).setAfSpeed(v),
          ),
        ),
      ],
    );
  }
}
