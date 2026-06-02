import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/audio/play_actions.dart';
import '../../core/backend/music_backend.dart';
import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../utils/display_error.dart';
import '../../widgets/af_dialog.dart';
import '../../widgets/af_scrollbar.dart';
import '../../widgets/async_error_view.dart';
import '../../widgets/track_context_menu.dart';
import '../../widgets/press_scale.dart';
import '../../widgets/track_row.dart';
import '../../widgets/skeletons/playlist_skeleton.dart';
import 'export_m3u_dialog.dart';

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
    final activeTrack = ref.watch(currentTrackProvider);
    final activeId = activeTrack?.id;
    final isBuffering = ref.watch(isBufferingProvider);
    final activeAccent = ref.watch(currentSpectralProvider).energy;

    return Scaffold(
      backgroundColor: AfColors.surfaceCanvas,
      appBar: AppBar(
        backgroundColor: AfColors.surfaceCanvas,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.pop(),
        ),
        title: Text('Playlist', style: AfTypography.titleSmall),
        actions: [
          if (backend != null)
            PopupMenuButton<_PlaylistAction>(
              icon: const Icon(LucideIcons.ellipsisVertical),
              onSelected: (action) =>
                  _handleAction(context, action, detailAsync.valueOrNull),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: _PlaylistAction.rename,
                  child: ListTile(
                    leading: Icon(LucideIcons.pencil, size: 20),
                    title: Text('Rename'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: _PlaylistAction.exportM3U,
                  child: ListTile(
                    leading: Icon(LucideIcons.download, size: 20),
                    title: Text('Export M3U'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: _PlaylistAction.delete,
                  child: ListTile(
                    leading: const Icon(
                      LucideIcons.trash2,
                      color: AfColors.semanticError,
                      size: 20,
                    ),
                    title: Text(
                      'Delete playlist',
                      style: AfTypography.bodyMedium.copyWith(
                        color: AfColors.semanticError,
                      ),
                    ),
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
            child: AfScrollbar(
              child: CustomScrollView(
                physics: const ClampingScrollPhysics(),
                slivers: [
                  // Header.
                  SliverToBoxAdapter(
                    child: _Header(pl: pl, tracks: tracks),
                  ),

                  // Action row.
                  SliverToBoxAdapter(
                    child: _ActionRow(
                      tracks: tracks,
                      onPlay: () =>
                          ref.read(playActionsProvider).playQueue(tracks),
                      onShuffle: () async {
                        await ref.read(playActionsProvider).playQueue(tracks);
                        await ref
                            .read(playerServiceProvider)
                            .setAfShuffleMode(true);
                      },
                    ),
                  ),

                  const SliverToBoxAdapter(
                    child: SizedBox(height: AfSpacing.s16),
                  ),

                  // Track list — wrapped in surfaceRaised container.
                  if (backend != null && tracks.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Container(
                        decoration: const BoxDecoration(
                          color: AfColors.surfaceRaised,
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(AfRadii.xl),
                            topRight: Radius.circular(AfRadii.xl),
                          ),
                        ),
                        child: ReorderableListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AfSpacing.s16,
                          ),
                          buildDefaultDragHandles: false,
                          itemCount: tracks.length,
                          onReorderItem: (oldIndex, newIndex) => _onReorder(
                            oldIndex,
                            newIndex,
                            tracks,
                            backend,
                            pl.id,
                          ),
                          itemBuilder: (context, i) {
                            final t = tracks[i];
                            final isActive = t.id == activeId;
                            return Dismissible(
                              key: ValueKey('${t.id}-$i'),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(
                                  right: AfSpacing.s16,
                                ),
                                color: AfColors.semanticError.withValues(
                                  alpha: 0.15,
                                ),
                                child: const Icon(
                                  LucideIcons.trash2,
                                  color: AfColors.semanticError,
                                ),
                              ),
                              confirmDismiss: (_) =>
                                  _confirmRemove(context, t.title),
                              onDismissed: (_) =>
                                  _removeTrack(i, tracks, backend, pl.id),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isActive
                                      ? AfColors.accentPrimary.withValues(
                                          alpha: 0.08,
                                        )
                                      : null,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: AfSpacing.s2,
                                  ),
                                  child: Row(
                                    children: [
                                      // Overline track number.
                                      SizedBox(
                                        width: AfSpacing.s32,
                                        child: Text(
                                          '${i + 1}',
                                          style: AfTypography.overline.copyWith(
                                            color: isActive
                                                ? AfColors.accentPrimary
                                                : AfColors.textDisabled,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                      Expanded(
                                        child: TrackRow(
                                          track: t,
                                          isActive: isActive,
                                          isBuffering:
                                              t.id == activeId && isBuffering,
                                          activeAccent: activeAccent,
                                          onTap: () => ref
                                              .read(playActionsProvider)
                                              .playQueue(tracks, startIndex: i),
                                          onLongPress: () =>
                                              showTrackContextMenu(
                                                context,
                                                ref,
                                                t,
                                              ),
                                        ),
                                      ),
                                      ReorderableDragStartListener(
                                        index: i,
                                        child: const Padding(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: AfSpacing.s8,
                                          ),
                                          child: Icon(
                                            LucideIcons.gripVertical,
                                            color: AfColors.textDisabled,
                                            size: 18,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    )
                  else if (tracks.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Container(
                        decoration: const BoxDecoration(
                          color: AfColors.surfaceRaised,
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(AfRadii.xl),
                            topRight: Radius.circular(AfRadii.xl),
                          ),
                        ),
                        child: ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AfSpacing.s16,
                          ),
                          itemCount: tracks.length,
                          itemBuilder: (context, i) {
                            final t = tracks[i];
                            final isActive = t.id == activeId;
                            return Container(
                              decoration: BoxDecoration(
                                color: isActive
                                    ? AfColors.accentPrimary.withValues(
                                        alpha: 0.08,
                                      )
                                    : null,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  bottom: AfSpacing.s2,
                                ),
                                child: Row(
                                  children: [
                                    // Overline track number.
                                    SizedBox(
                                      width: AfSpacing.s32,
                                      child: Text(
                                        '${i + 1}',
                                        style: AfTypography.overline.copyWith(
                                          color: isActive
                                              ? AfColors.accentPrimary
                                              : AfColors.textDisabled,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    Expanded(
                                      child: TrackRow(
                                        track: t,
                                        isActive: isActive,
                                        isBuffering:
                                            t.id == activeId && isBuffering,
                                        activeAccent: activeAccent,
                                        onTap: () => ref
                                            .read(playActionsProvider)
                                            .playQueue(tracks, startIndex: i),
                                        onLongPress: () => showTrackContextMenu(
                                          context,
                                          ref,
                                          t,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                  if (tracks.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(top: AfSpacing.s48),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: AfColors.accentPrimary.withValues(
                                    alpha: 0.08,
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  LucideIcons.listMusic,
                                  size: 36,
                                  color: AfColors.accentMuted,
                                ),
                              ),
                              const SizedBox(height: AfSpacing.s12),
                              Text(
                                'Empty playlist',
                                style: AfTypography.titleSmall,
                              ),
                              const SizedBox(height: AfSpacing.s8),
                              Text(
                                'Add songs to get started',
                                style: AfTypography.bodySmall.copyWith(
                                  color: AfColors.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  const SliverToBoxAdapter(
                    child: SizedBox(
                      height: AfSpacing.bottomInsetWithMiniAndNav,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Reorder ────────────────────────────────────────────────────────────────

  void _onReorder(
    int oldIndex,
    int newIndex,
    List<AfTrack> tracks,
    MusicBackend client,
    String playlistId,
  ) {
    // Note: no newIndex adjustment needed — onReorderItem already handles it.
    final updated = List<AfTrack>.from(tracks);
    final item = updated.removeAt(oldIndex);
    updated.insert(newIndex, item);
    setState(() => _localTracks = updated);

    // Fire-and-forget server sync — uses playlist entry ID (item.id is the
    // track ID here; movePlaylistItem uses it as the entry identifier).
    client.movePlaylistItem(playlistId, item.id, newIndex).catchError((
      Object e,
    ) {
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
              Text(
                'Remove "$title" from this playlist?',
                style: AfTypography.bodyMedium,
              ),
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
                    child: Text(
                      'Remove',
                      style: AfTypography.bodyMedium.copyWith(
                        color: AfColors.semanticError,
                      ),
                    ),
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
  Future<void> _removeTrack(
    int index,
    List<AfTrack> tracks,
    MusicBackend client,
    String playlistId,
  ) async {
    final removed = tracks[index];
    final updated = List<AfTrack>.from(tracks)..removeAt(index);
    setState(() => _localTracks = updated);

    try {
      // Pass the track ID as the entry ID. Jellyfin's playlist endpoint
      // accepts both track IDs and per-entry IDs for non-duplicate playlists.
      await client.removeFromPlaylist(playlistId, [removed.id]);

      ref
          .read(playlistUndoBufferProvider)
          .pushRemove(playlistId, [removed.id], [removed.id]);

      // Invalidate only after the server confirms the delete so the
      // refetch sees the updated list, not the pre-delete snapshot.
      ref.invalidate(playlistDetailProvider(widget.playlistId));
      ref.invalidate(allPlaylistsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text('Removed "${removed.title}"'),
              action: SnackBarAction(
                label: 'Undo',
                onPressed: () => _undoRemove(playlistId, client),
              ),
            ),
          );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _localTracks = tracks);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(displayError(e, prefix: 'Could not remove'))),
        );
      }
    }
  }

  Future<void> _undoRemove(String playlistId, MusicBackend client) async {
    final action = ref.read(playlistUndoBufferProvider).pop(playlistId);
    if (action == null) return;
    try {
      await client.addToPlaylist(playlistId, action.trackIds);
      ref.invalidate(playlistDetailProvider(playlistId));
      ref.invalidate(allPlaylistsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(displayError(e, prefix: 'Could not undo removal')),
          ),
        );
      }
    }
  }

  // ── Rename / Delete ────────────────────────────────────────────────────────

  Future<void> _handleAction(
    BuildContext context,
    _PlaylistAction action,
    ({AfPlaylist playlist, List<AfTrack> tracks})? detail,
  ) async {
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
              SnackBar(
                content: Text(displayError(e, prefix: 'Could not rename')),
              ),
            );
          }
        }

      case _PlaylistAction.exportM3U:
        try {
          await ref
              .read(exportM3UActionProvider)
              .export(
                tracks: detail.tracks,
                playlistName: detail.playlist.name,
                context: context,
              );
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(displayError(e, prefix: 'Could not export')),
              ),
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
                style: AfTypography.bodyMedium,
              ),
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
                    child: Text(
                      'Delete',
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
        if (confirmed != true) return;
        try {
          await backend.deletePlaylist(widget.playlistId);
          ref.invalidate(allPlaylistsProvider);
          if (context.mounted) context.pop();
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(displayError(e, prefix: 'Could not delete')),
              ),
            );
          }
        }
    }
  }

  Future<String?> _showRenameDialog(
    BuildContext context,
    String currentName,
  ) async {
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

enum _PlaylistAction { rename, exportM3U, delete }

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.pl, required this.tracks});
  final AfPlaylist pl;
  final List<AfTrack> tracks;

  String _formatDuration(Duration d) {
    final totalMinutes = d.inMinutes;
    if (totalMinutes < 1) return '${d.inSeconds}s';
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    final seconds = d.inSeconds % 60;
    return seconds > 0 ? '${minutes}m ${seconds}s' : '${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final totalDuration = tracks.fold<Duration>(
      Duration.zero,
      (sum, t) => sum + t.duration,
    );
    final artistCount = tracks.map((t) => t.artistName).toSet().length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AfSpacing.s16,
        AfSpacing.s8,
        AfSpacing.s16,
        AfSpacing.s16,
      ),
      child: Column(
        children: [
          // Centered hero artwork 128dp.
          Container(
            width: 128,
            height: 128,
            decoration: BoxDecoration(
              borderRadius: AfRadii.borderXl,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AfColors.accentPrimary.withValues(alpha: 0.3),
                  AfColors.surfaceLow,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: AfColors.accentPrimary.withValues(alpha: 0.15),
                  blurRadius: 32,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              LucideIcons.listMusic,
              color: AfColors.accentPrimary,
              size: 56,
            ),
          ),
          const SizedBox(height: AfSpacing.s16),

          // Centered playlist name — serif headline.
          Text(
            pl.name,
            style: AfTypography.titleLarge,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AfSpacing.s12),

          // Mono stat badges.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _StatBadge(
                label:
                    '${tracks.length} ${tracks.length == 1 ? "track" : "tracks"}',
              ),
              const SizedBox(width: AfSpacing.s8),
              _StatBadge(label: _formatDuration(totalDuration)),
              const SizedBox(width: AfSpacing.s8),
              _StatBadge(
                label:
                    '$artistCount ${artistCount == 1 ? "artist" : "artists"}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.tracks,
    required this.onPlay,
    required this.onShuffle,
  });
  final List<AfTrack> tracks;
  final VoidCallback onPlay;
  final VoidCallback onShuffle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
      child: _SegmentedControl(
        onLeft: tracks.isEmpty ? null : onPlay,
        onRight: tracks.isEmpty ? null : onShuffle,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Design-system widgets
// ─────────────────────────────────────────────────────────────────────────────

/// Mono stat badge used in the playlist hero header.
class _StatBadge extends StatelessWidget {
  const _StatBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AfSpacing.s12,
        vertical: AfSpacing.s4,
      ),
      decoration: const BoxDecoration(
        color: AfColors.surfaceLow,
        borderRadius: AfRadii.borderSm,
        border: Border.fromBorderSide(BorderSide(color: AfColors.surfaceHigh)),
      ),
      child: Text(
        label,
        style: AfTypography.mono.copyWith(
          fontSize: 10,
          color: AfColors.textTertiary,
        ),
      ),
    );
  }
}

/// Play / Shuffle segmented control.
class _SegmentedControl extends StatefulWidget {
  const _SegmentedControl({required this.onLeft, required this.onRight});
  final VoidCallback? onLeft;
  final VoidCallback? onRight;

  @override
  State<_SegmentedControl> createState() => _SegmentedControlState();
}

class _SegmentedControlState extends State<_SegmentedControl> {
  bool _isRightSelected = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: const BoxDecoration(
        color: AfColors.surfaceLow,
        borderRadius: AfRadii.borderPill,
        border: Border.fromBorderSide(BorderSide(color: AfColors.surfaceHigh)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(child: _buildOption(isRight: false)),
          Expanded(child: _buildOption(isRight: true)),
        ],
      ),
    );
  }

  Widget _buildOption({required bool isRight}) {
    final isSelected = _isRightSelected == isRight;
    final label = isRight ? 'Shuffle' : 'Play';
    final icon = isRight ? LucideIcons.shuffle : LucideIcons.play;
    final onTap = isRight ? widget.onRight : widget.onLeft;

    return AnimatedContainer(
      duration: AfDurations.quick,
      curve: AfCurves.easeStandard,
      decoration: BoxDecoration(
        color: isSelected ? AfColors.accentPrimary : Colors.transparent,
      ),
      child: PressScale(
        ensureHitTarget: false,
        onTap: onTap == null
            ? null
            : () => setState(() => _isRightSelected = isRight),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected
                  ? AfColors.surfaceCanvas
                  : AfColors.textTertiary,
            ),
            const SizedBox(width: AfSpacing.s8),
            Text(
              label,
              style: AfTypography.bodyMedium.copyWith(
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected
                    ? AfColors.surfaceCanvas
                    : AfColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
