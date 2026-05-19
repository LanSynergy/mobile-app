import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/audio/play_actions.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/async_error_view.dart';
import '../../widgets/track_context_menu.dart';
import '../../widgets/track_row.dart';

/// Shows the resolved tracks for a smart playlist — Samsung One UI style.
class SmartPlaylistDetailScreen extends ConsumerWidget {
  final String playlistId;
  const SmartPlaylistDetailScreen({super.key, required this.playlistId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracksAsync = ref.watch(smartPlaylistTracksProvider(playlistId));
    final playlistAsync = ref.watch(smartPlaylistsProvider);
    final playlist = playlistAsync.maybeWhen(
      data: (list) => list.where((p) => p.id == playlistId).firstOrNull,
      orElse: () => null,
    );

    return Scaffold(
      backgroundColor: AfColors.surfaceCanvas,
      appBar: AppBar(
        backgroundColor: AfColors.surfaceCanvas,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: Text(playlist?.name ?? 'Smart Playlist',
            style: AfTypography.display),
        centerTitle: false,
        titleSpacing: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded),
            onPressed: () => context.push('/smart-playlist/$playlistId/edit'),
            tooltip: 'Edit rules',
          ),
        ],
      ),
      body: tracksAsync.when(
        data: (tracks) {
          if (tracks.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AfColors.textTertiary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.music_off_rounded,
                        size: 36, color: AfColors.textTertiary),
                  ),
                  const SizedBox(height: AfSpacing.s16),
                  Text(
                    'No tracks match these rules',
                    style: AfTypography.titleSmall,
                  ),
                  const SizedBox(height: AfSpacing.s4),
                  Text(
                    'Try editing the rules to broaden the criteria',
                    style: AfTypography.bodySmall.copyWith(
                      color: AfColors.textTertiary,
                    ),
                  ),
                ],
              ),
            );
          }
          return Column(
            children: [
              // Header card with play controls
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AfSpacing.s16,
                  vertical: AfSpacing.s8,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AfSpacing.s16,
                    vertical: AfSpacing.s12,
                  ),
                  decoration: BoxDecoration(
                    color: AfColors.surfaceBase,
                    borderRadius: AfRadii.borderLg,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AfColors.indigo500.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.auto_awesome_rounded,
                            size: 20, color: AfColors.indigo400),
                      ),
                      const SizedBox(width: AfSpacing.s12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('${tracks.length} tracks',
                                style: AfTypography.bodyMedium),
                            if (playlist != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  playlist.ruleSummary,
                                  style: AfTypography.bodySmall.copyWith(
                                    color: AfColors.textTertiary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AfSpacing.s8),
                      IconButton(
                        onPressed: () {
                          final svc = ref.read(playerServiceProvider);
                          svc.setAfShuffleMode(true);
                          ref.read(playActionsProvider).playQueue(tracks);
                        },
                        icon: const Icon(Icons.shuffle_rounded),
                        color: AfColors.textSecondary,
                        tooltip: 'Shuffle',
                      ),
                      FilledButton.icon(
                        onPressed: () =>
                            ref.read(playActionsProvider).playQueue(tracks),
                        icon: const Icon(Icons.play_arrow_rounded, size: 20),
                        label: const Text('Play'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AfColors.indigo600,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AfSpacing.s16,
                            vertical: AfSpacing.s8,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Track list
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AfSpacing.s16,
                  ).add(const EdgeInsets.only(
                      bottom: AfSpacing.bottomInsetWithMiniAndNav)),
                  itemCount: tracks.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: AfSpacing.s4),
                  itemBuilder: (context, i) {
                    final t = tracks[i];
                    return TrackRow(
                      track: t,
                      onTap: () => ref
                          .read(playActionsProvider)
                          .playQueue(tracks, startIndex: i),
                      onLongPress: () =>
                          showTrackContextMenu(context, ref, t),
                    );
                  },
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AsyncErrorView(
          label: 'Could not resolve smart playlist',
          error: e,
          onRetry: () =>
              ref.invalidate(smartPlaylistTracksProvider(playlistId)),
        ),
      ),
    );
  }
}
