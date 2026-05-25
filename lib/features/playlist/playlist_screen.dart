import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/audio/play_actions.dart';
import '../../core/backend/music_backend.dart';
import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../utils/display_error.dart';
import '../../widgets/af_dialog.dart';
import '../../widgets/async_error_view.dart';
import '../../widgets/press_scale.dart';
import '../../widgets/track_context_menu.dart';
import '../../widgets/track_row.dart';
import '../../widgets/skeletons/playlist_skeleton.dart';

/// Playlist detail screen with full management:
///   • Play / Shuffle
///   • Drag-to-reorder tracks
///   • Swipe-to-remove tracks
///   • Rename playlist (appbar action)
///   • Delete playlist (appbar action)
class PlaylistScreen extends ConsumerStatefulWidget {
  const PlaylistScreen({super.key, required this.playlistId});
  final String playlistId;

  @override
  ConsumerState<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends ConsumerState<PlaylistScreen> {
  /// Local mutable copy of the track list for optimistic reorder/remove.
  List<AfTrack>? _localTracks;

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(playlistDetailProvider(widget.playlistId));
    final backend = ref.watch(musicBackendProvider);

    return Scaffold(
      backgroundColor: AfColors.surfaceCanvas,
      appBar: AppBar(
        backgroundColor: AfColors.surfaceCanvas,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: Text('Playlist', style: AfTypography.titleSmall),
        actions: [
          if (backend != null)
            PopupMenuButton<_PlaylistAction>(
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (action) => _handleAction(context, action, detailAsync.valueOrNull),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: _PlaylistAction.rename,
                  child: ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Rename'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: _PlaylistAction.delete,
                  child: ListTile(
                    leading: Icon(Icons.delete_outline_rounded,
                        color: AfColors.semanticError),
                    title: Text('Delete playlist',
                        style: TextStyle(color: AfColors.semanticError)),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
        ],
      ),
      body: detailAsync.when(
        loading: () => const PlaylistSkeleton(),
        error: (e, _) => AsyncErrorView(
          label: 'Could not load playlist',
          error: e,
          onRetry: () =>
              ref.invalidate(playlistDetailProvider(widget.playlistId)),
        ),
        data: (detail) {
          if (detail == null) {
            return const Center(child: Text('Playlist not found'));
          }
          final pl = detail.playlist;
          // Use local copy if available (after reorder/remove), else server data.
          final tracks = _localTracks ?? detail.tracks;

          return SafeArea(
            child: CustomScrollView(
              physics: const ClampingScrollPhysics(),
              slivers: [
                // Header.
                SliverToBoxAdapter(child: _Header(pl: pl, tracks: tracks)),

                // Action row.
                SliverToBoxAdapter(
                  child: _ActionRow(
                    tracks: tracks,
                    onPlay: () =>
                        ref.read(playActionsProvider).playQueue(tracks),
                    onShuffle: () {
                      ref.read(playerServiceProvider).setAfShuffleMode(true);
                      ref.read(playActionsProvider).playQueue(tracks);
                    },
                  ),
                ),

                const SliverToBoxAdapter(
                    child: SizedBox(height: AfSpacing.s16)),

                // Track list — reorderable when signed in.
                if (backend != null && tracks.isNotEmpty)
                  SliverToBoxAdapter(
                    child: ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                          horizontal: AfSpacing.s16),
                      buildDefaultDragHandles: false,
                      itemCount: tracks.length,
                      onReorderItem: (oldIndex, newIndex) =>
                          _onReorder(oldIndex, newIndex, tracks, backend, pl.id),
                      itemBuilder: (context, i) {
                        final t = tracks[i];
                        return Dismissible(
                          key: ValueKey('${t.id}-$i'),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: AfSpacing.s16),
                            color: AfColors.semanticError.withValues(alpha: 0.15),
                            child: const Icon(Icons.delete_outline_rounded,
                                color: AfColors.semanticError),
                          ),
                          confirmDismiss: (_) => _confirmRemove(context, t.title),
                          onDismissed: (_) =>
                              _removeTrack(i, tracks, backend, pl.id),
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: AfSpacing.s4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TrackRow(
                                    track: t,
                                    onTap: () => ref
                                        .read(playActionsProvider)
                                        .playQueue(tracks, startIndex: i),
                                    onLongPress: () =>
                                        showTrackContextMenu(context, ref, t),
                                  ),
                                ),
                                ReorderableDragStartListener(
                                  index: i,
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: AfSpacing.s8),
                                    child: Icon(Icons.drag_indicator_rounded,
                                        color: AfColors.textTertiary),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  )
                else
                  SliverFixedExtentList(
                    itemExtent: 68.0,
                    delegate: SliverChildBuilderDelegate(
                      childCount: tracks.length,
                      (context, i) {
                        final t = tracks[i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AfSpacing.s16),
                          child: Column(
                            children: [
                              TrackRow(
                                track: t,
                                onTap: () => ref
                                    .read(playActionsProvider)
                                    .playQueue(tracks, startIndex: i),
                                onLongPress: () =>
                                    showTrackContextMenu(context, ref, t),
                              ),
                              const SizedBox(height: 4),
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                const SliverToBoxAdapter(
                  child: SizedBox(height: AfSpacing.bottomInsetWithMiniAndNav),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Reorder ────────────────────────────────────────────────────────────────

  void _onReorder(int oldIndex, int newIndex, List<AfTrack> tracks,
      MusicBackend client, String playlistId) {
    // Note: no newIndex adjustment needed — onReorderItem already handles it.
    final updated = List<AfTrack>.from(tracks);
    final item = updated.removeAt(oldIndex);
    updated.insert(newIndex, item);
    setState(() => _localTracks = updated);

    // Fire-and-forget server sync — uses playlist entry ID (item.id is the
    // track ID here; movePlaylistItem uses it as the entry identifier).
    client.movePlaylistItem(playlistId, item.id, newIndex).catchError((Object e) {
      // Revert on failure.
      if (mounted) {
        setState(() => _localTracks = tracks);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(displayError(e, prefix: 'Could not reorder'))),
        );
      }
    });
  }

  // ── Remove ─────────────────────────────────────────────────────────────────

  Future<bool> _confirmRemove(BuildContext context, String title) async {
    return await showBlurDialog<bool>(
          context: context,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Remove track', style: AfTypography.titleMedium),
              const SizedBox(height: AfSpacing.s12),
              Text('Remove "$title" from this playlist?', style: AfTypography.bodyMedium),
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
                    child: const Text('Remove',
                        style: TextStyle(color: AfColors.semanticError)),
                  ),
                ],
              ),
            ],
          ),
        ) ??
        false;
  }

  /// Remove a track from the playlist.
  ///
  /// Awaits the server call before invalidating providers so the refetch
  /// sees the updated list (not the pre-delete snapshot). Reverts the
  /// optimistic local state on failure.
  Future<void> _removeTrack(int index, List<AfTrack> tracks,
      MusicBackend client, String playlistId) async {
    final removed = tracks[index];
    final updated = List<AfTrack>.from(tracks)..removeAt(index);
    setState(() => _localTracks = updated);

    try {
      // Pass the track ID as the entry ID. Jellyfin's playlist endpoint
      // accepts both track IDs and per-entry IDs for non-duplicate playlists.
      await client.removeFromPlaylist(playlistId, [removed.id]);
      // Invalidate only after the server confirms the delete so the
      // refetch sees the updated list, not the pre-delete snapshot.
      ref.invalidate(playlistDetailProvider(widget.playlistId));
      ref.invalidate(allPlaylistsProvider);
    } catch (e) {
      if (mounted) {
        setState(() => _localTracks = tracks);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(displayError(e, prefix: 'Could not remove'))),
        );
      }
    }
  }

  // ── Rename / Delete ────────────────────────────────────────────────────────

  Future<void> _handleAction(BuildContext context, _PlaylistAction action,
      ({AfPlaylist playlist, List<AfTrack> tracks})? detail) async {
    if (detail == null) return;
    final backend = ref.read(musicBackendProvider);
    if (backend == null) return;

    switch (action) {
      case _PlaylistAction.rename:
        final newName = await _showRenameDialog(context, detail.playlist.name);
        if (newName == null || newName.isEmpty) return;
        try {
          await backend.renamePlaylist(widget.playlistId, newName);
          ref.invalidate(playlistDetailProvider(widget.playlistId));
          ref.invalidate(allPlaylistsProvider);
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(displayError(e, prefix: 'Could not rename'))),
            );
          }
        }

      case _PlaylistAction.delete:
        final confirmed = await showBlurDialog<bool>(
          context: context,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Delete playlist', style: AfTypography.titleMedium),
              const SizedBox(height: AfSpacing.s12),
              Text(
                  'Delete "${detail.playlist.name}"? This cannot be undone.',
                  style: AfTypography.bodyMedium),
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
                    child: const Text('Delete',
                        style: TextStyle(color: AfColors.semanticError)),
                  ),
                ],
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        try {
          await backend.deletePlaylist(widget.playlistId);
          ref.invalidate(allPlaylistsProvider);
          if (context.mounted) context.pop();
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(displayError(e, prefix: 'Could not delete'))),
            );
          }
        }
    }
  }

  Future<String?> _showRenameDialog(
      BuildContext context, String currentName) async {
    final ctl = TextEditingController(text: currentName);
    try {
      return await showBlurDialog<String>(
        context: context,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Rename playlist', style: AfTypography.titleMedium),
            const SizedBox(height: AfSpacing.s16),
            TextField(
              controller: ctl,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Playlist name'),
              onSubmitted: (v) => Navigator.pop(context, v),
            ),
            const SizedBox(height: AfSpacing.s24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, ctl.text),
                  child: const Text('Rename'),
                ),
              ],
            ),
          ],
        ),
      );
    } finally {
      ctl.dispose();
    }
  }
}

enum _PlaylistAction { rename, delete }

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.pl, required this.tracks});
  final AfPlaylist pl;
  final List<AfTrack> tracks;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AfSpacing.s16, AfSpacing.s8, AfSpacing.s16, AfSpacing.s16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: const BoxDecoration(
              borderRadius: AfRadii.borderMd,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AfColors.indigo700, AfColors.indigo950],
              ),
            ),
            child: const Icon(Icons.playlist_play_rounded,
                color: AfColors.indigo300, size: 40),
          ),
          const SizedBox(width: AfSpacing.s16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pl.name,
                    style: AfTypography.titleLarge,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: AfSpacing.s4),
                Text(
                  '${tracks.length} ${tracks.length == 1 ? "track" : "tracks"}',
                  style: AfTypography.bodySmall
                      .copyWith(color: AfColors.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow(
      {required this.tracks, required this.onPlay, required this.onShuffle});
  final List<AfTrack> tracks;
  final VoidCallback onPlay;
  final VoidCallback onShuffle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
      child: Row(
        children: [
          Expanded(
            child: PressScale(
              onTap: tracks.isEmpty ? null : onPlay,
              child: Container(
                height: 48,
                decoration: const BoxDecoration(
                  color: AfColors.indigo600,
                  borderRadius: AfRadii.borderPill,
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.play_arrow_rounded,
                        color: AfColors.textOnPrimary),
                    const SizedBox(width: AfSpacing.s8),
                    Text('Play',
                        style: AfTypography.bodyMedium
                            .copyWith(color: AfColors.textOnPrimary)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: AfSpacing.s12),
          Expanded(
            child: PressScale(
              onTap: tracks.isEmpty ? null : onShuffle,
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: AfColors.surfaceBase,
                  borderRadius: AfRadii.borderPill,
                  border: Border.all(color: AfColors.surfaceHigh, width: 1),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.shuffle_rounded,
                        color: AfColors.textPrimary),
                    const SizedBox(width: AfSpacing.s8),
                    Text('Shuffle', style: AfTypography.bodyMedium),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
