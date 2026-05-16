import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/audio/play_actions.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/track_context_menu.dart';
import '../../widgets/track_row.dart';

/// Shows the resolved tracks for a smart playlist + play button.
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
        title: Text(playlist?.name ?? 'Smart Playlist'),
        centerTitle: false,
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
              child: Text(
                'No tracks match these rules.',
                style: AfTypography.bodyMedium.copyWith(
                  color: AfColors.textTertiary,
                ),
              ),
            );
          }
          return Column(
            children: [
              // Play all bar
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AfSpacing.s16,
                  vertical: AfSpacing.s8,
                ),
                child: Row(
                  children: [
                    Text(
                      '${tracks.length} tracks',
                      style: AfTypography.bodySmall.copyWith(
                        color: AfColors.textTertiary,
                      ),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: () => ref
                          .read(playActionsProvider)
                          .playQueue(tracks),
                      icon: const Icon(Icons.play_arrow_rounded, size: 20),
                      label: const Text('Play all'),
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
              // Track list
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AfSpacing.s16,
                  ).add(const EdgeInsets.only(
                      bottom: AfSpacing.bottomInsetWithMiniAndNav)),
                  itemCount: tracks.length,
                  separatorBuilder: (_, _) =>
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
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}
