import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/smart_playlist/smart_playlist_model.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';

/// Lists all user-created smart playlists.
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
        title: const Text('Smart Playlists'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: () => context.push('/smart-playlist/new'),
            tooltip: 'Create smart playlist',
          ),
        ],
      ),
      body: playlistsAsync.when(
        data: (playlists) => playlists.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome_rounded,
                        size: 48, color: AfColors.textTertiary),
                    const SizedBox(height: AfSpacing.s12),
                    Text(
                      'No smart playlists yet',
                      style: AfTypography.bodyMedium.copyWith(
                        color: AfColors.textTertiary,
                      ),
                    ),
                    const SizedBox(height: AfSpacing.s16),
                    FilledButton.icon(
                      onPressed: () => context.push('/smart-playlist/new'),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Create one'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AfColors.indigo600,
                      ),
                    ),
                  ],
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: AfSpacing.s16,
                  vertical: AfSpacing.s8,
                ),
                itemCount: playlists.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AfSpacing.s8),
                itemBuilder: (context, i) {
                  final sp = playlists[i];
                  return _SmartPlaylistTile(
                    playlist: sp,
                    onTap: () => context.push('/smart-playlist/${sp.id}'),
                    onDelete: () async {
                      final db = ref.read(smartPlaylistDbProvider);
                      await db.delete(sp.id);
                      ref.invalidate(smartPlaylistsProvider);
                    },
                  );
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _SmartPlaylistTile extends StatelessWidget {
  final SmartPlaylist playlist;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _SmartPlaylistTile({
    required this.playlist,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AfColors.surfaceBase,
      borderRadius: AfRadii.borderLg,
      child: InkWell(
        onTap: onTap,
        borderRadius: AfRadii.borderLg,
        onLongPress: () => _showDeleteDialog(context),
        child: Padding(
          padding: const EdgeInsets.all(AfSpacing.s16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AfColors.indigo500.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.auto_awesome_rounded,
                    color: AfColors.indigo400, size: 22),
              ),
              const SizedBox(width: AfSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(playlist.name, style: AfTypography.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      playlist.ruleSummary,
                      style: AfTypography.bodySmall.copyWith(
                        color: AfColors.textTertiary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AfColors.textTertiary, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AfColors.surfaceBase,
        title: Text('Delete "${playlist.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              onDelete();
            },
            child: Text('Delete',
                style: TextStyle(color: AfColors.semanticError)),
          ),
        ],
      ),
    );
  }
}
