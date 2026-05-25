import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/favorite_heart_button.dart';
import '../../widgets/quality_chip.dart';

class MetadataRow extends ConsumerWidget {
  const MetadataRow({super.key, required this.track});

  final AfTrack track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        Text(
          track.title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          maxLines: 1,
        ),
        const SizedBox(height: AfSpacing.s4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: GestureDetector(
                onTap: track.artistId != null
                    ? () => context.push('/artist/${track.artistId}')
                    : null,
                child: Text(
                  track.artistName,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                ),
              ),
            ),
            if (track.albumName.isNotEmpty) ...[
              const Text(' · '),
              Flexible(
                child: GestureDetector(
                  onTap: track.albumId != null
                      ? () => context.push('/album/${track.albumId}')
                      : null,
                  child: Text(
                    track.albumName,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AfSpacing.s12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const _AbLoopButton(),
            const SizedBox(width: AfSpacing.s12),
            FavoriteHeartButton(track: track),
            if (track.quality != null) ...[
              const SizedBox(width: AfSpacing.s8),
              QualityChip(quality: track.quality!),
            ],
          ],
        ),
      ],
    );
  }
}

class _AbLoopButton extends ConsumerWidget {
  const _AbLoopButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final abA = ref.watch(abLoopAProvider);
    final abB = ref.watch(abLoopBProvider);
    final active = abA != null || abB != null;
    return GestureDetector(
      onTap: () {
        // Clear existing A-B loop
        if (active) {
          ref.read(playerServiceProvider).setAbLoopA(null);
          ref.read(playerServiceProvider).setAbLoopB(null);
          ref.read(abLoopAProvider.notifier).state = null;
          ref.read(abLoopBProvider.notifier).state = null;
          return;
        }
        // Set A at current position
        final pos = ref.read(positionStreamProvider);
        ref.read(playerServiceProvider).setAbLoopA(pos);
        ref.read(abLoopAProvider.notifier).state = pos;
      },
      child: Icon(
        active ? LucideIcons.repeat1 : LucideIcons.repeat1,
        size: 20,
        color: active
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
      ),
    );
  }
}
