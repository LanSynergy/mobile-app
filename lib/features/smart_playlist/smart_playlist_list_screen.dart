import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/smart_playlist/smart_playlist_model.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/af_dialog.dart';
import '../../widgets/async_error_view.dart';
import '../../widgets/skeletons/playlist_skeleton.dart';

/// Lists all user-created smart playlists — Samsung One UI style.
class SmartPlaylistListScreen extends ConsumerWidget {
  const SmartPlaylistListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistsAsync = ref.watch(smartPlaylistsProvider);

    return Scaffold(
      backgroundColor: AfColors.surfaceCanvas,
      appBar: AppBar(
        backgroundColor: AfColors.surfaceCanvas,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: Text('Smart Playlists', style: AfTypography.display),
        centerTitle: false,
        titleSpacing: 0,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/smart-playlist/new'),
        backgroundColor: AfColors.indigo600,
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: playlistsAsync.when(
        data: (playlists) => playlists.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AfColors.indigo500.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.auto_awesome_rounded,
                        size: 36,
                        color: AfColors.indigo400,
                      ),
                    ),
                    const SizedBox(height: AfSpacing.s16),
                    Text(
                      'No smart playlists yet',
                      style: AfTypography.titleSmall,
                    ),
                    const SizedBox(height: AfSpacing.s4),
                    Text(
                      'Create rule-based playlists that update automatically',
                      style: AfTypography.bodySmall.copyWith(
                        color: AfColors.textTertiary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            : ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AfSpacing.s16,
                  vertical: AfSpacing.s8,
                ),
                children: [
                  // Grouped card container
                  Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: const BoxDecoration(
                      color: AfColors.surfaceBase,
                      borderRadius: AfRadii.borderLg,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (int i = 0; i < playlists.length; i++) ...[
                          _PlaylistTile(
                            playlist: playlists[i],
                            onTap: () => context.push(
                              '/smart-playlist/${playlists[i].id}',
                            ),
                            onDelete: () async {
                              final db = ref.read(smartPlaylistDbProvider);
                              await db.delete(playlists[i].id);
                              ref.invalidate(smartPlaylistsProvider);
                            },
                          ),
                          if (i < playlists.length - 1)
                            const Divider(
                              height: 0,
                              thickness: 0.5,
                              indent: 64,
                              color: AfColors.surfaceHigh,
                            ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: AfSpacing.s24),
                ],
              ),
        loading: () => const PlaylistSkeleton(),
        error: (e, _) => AsyncErrorView(
          label: 'Could not load smart playlists',
          error: e,
          onRetry: () => ref.invalidate(smartPlaylistsProvider),
        ),
      ),
    );
  }
}

class _PlaylistTile extends StatelessWidget {
  const _PlaylistTile({
    required this.playlist,
    required this.onTap,
    required this.onDelete,
  });
  final SmartPlaylist playlist;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: () => _showDeleteDialog(context),
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
                color: AfColors.indigo500.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                size: 20,
                color: AfColors.indigo400,
              ),
            ),
            const SizedBox(width: AfSpacing.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(playlist.name, style: AfTypography.bodyMedium),
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
            const Icon(
              Icons.chevron_right_rounded,
              color: AfColors.textTertiary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteDialog(BuildContext context) {
    showBlurDialog<void>(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Delete "${playlist.name}"?', style: AfTypography.titleMedium),
          const SizedBox(height: AfSpacing.s12),
          Text('This action cannot be undone.', style: AfTypography.bodyMedium),
          const SizedBox(height: AfSpacing.s24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  onDelete();
                },
                child: const Text(
                  'Delete',
                  style: TextStyle(color: AfColors.semanticError),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
