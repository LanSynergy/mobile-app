import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/audio/play_actions.dart';
import '../core/jellyfin/models/items.dart';
import '../design_tokens/tokens.dart';
import '../state/providers.dart';

/// Bottom-sheet "more options" menu for an album.
///
/// Replaces the previous "More options coming soon" snackbars on the
/// album screen's app-bar `more_vert` and the action-row `more_horiz`
/// affordances — both of which used to fire from
/// `lib/features/album/album_screen.dart`. The sheet reuses the
/// player's existing primitives (`PlayActions.playAlbum`,
/// `AfPlayerService.playNext`, `AfPlayerService.addToQueue`) so it
/// behaves identically in server mode and local mode.
void showAlbumMoreSheet(
  BuildContext context,
  WidgetRef ref,
  AfAlbum album,
  List<AfTrack> tracks,
) {
  HapticFeedback.mediumImpact();
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AfRadii.lg)),
    ),
    builder: (sheetCtx) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          0,
          AfSpacing.s12,
          0,
          AfSpacing.s12,
        ),
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AfSpacing.gutterGenerous,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    album.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AfTypography.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    album.artistName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AfTypography.bodySmall.copyWith(
                      color: AfColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AfSpacing.s8),
            const Divider(height: 1, color: AfColors.surfaceHigh),
            _MenuItem(
              icon: CupertinoIcons.shuffle,
              label: 'Shuffle play',
              enabled: tracks.isNotEmpty,
              onTap: () async {
                Navigator.of(sheetCtx).pop();
                await ref.read(playerServiceProvider).setAfShuffleMode(true);
                await ref.read(playActionsProvider).playAlbum(tracks);
              },
            ),
            _MenuItem(
              icon: CupertinoIcons.play,
              label: 'Play next',
              enabled: tracks.isNotEmpty,
              onTap: () {
                Navigator.of(sheetCtx).pop();
                _enqueue(ref, tracks, atFront: true);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      _enqueueLabel(tracks.length, 'will play next'),
                    ),
                  ),
                );
              },
            ),
            _MenuItem(
              icon: CupertinoIcons.music_note_list,
              label: 'Add to queue',
              enabled: tracks.isNotEmpty,
              onTap: () {
                Navigator.of(sheetCtx).pop();
                _enqueue(ref, tracks, atFront: false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      _enqueueLabel(tracks.length, 'added to queue'),
                    ),
                  ),
                );
              },
            ),
            if (album.artistId != null)
              _MenuItem(
                icon: CupertinoIcons.person,
                label: 'Go to artist',
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  context.push('/artist/${album.artistId}');
                },
              ),
          ],
        ),
        ),
      ),
    ),
  );
}

/// Build the stream-URL resolver for queue mutations, mirroring
/// `track_context_menu.dart`'s helper. In local mode the track id IS
/// the `content://` URI; in server mode the backend resolves it.
String Function(AfTrack)? _streamResolver(WidgetRef ref) {
  final mode = ref.read(appModeProvider);
  if (mode == AppMode.local) {
    return (t) => t.id;
  }
  final backend = ref.read(musicBackendProvider);
  if (backend == null) return null;
  return (t) => backend.trackStreamUrl(t.id, maxBitrateKbps: 320);
}

/// Enqueue every track in [tracks]. When [atFront] is true the tracks
/// land right after the currently-playing track in order; otherwise
/// they're appended to the end of the queue.
void _enqueue(WidgetRef ref, List<AfTrack> tracks, {required bool atFront}) {
  if (tracks.isEmpty) return;
  final resolve = _streamResolver(ref);
  if (resolve == null) return;
  final svc = ref.read(playerServiceProvider);
  // Fire sequentially so order is preserved: each `playNext` inserts
  // at `_currentIndex + 1`, so we reverse the list when inserting at
  // the front to keep the first track of the album playing first.
  final ordered = atFront ? tracks.reversed.toList() : tracks;
  unawaited(() async {
    for (final t in ordered) {
      if (atFront) {
        await svc.playNext(t, resolveStreamUrl: resolve);
      } else {
        await svc.addToQueue(t, resolveStreamUrl: resolve);
      }
    }
  }());
}

String _enqueueLabel(int count, String verbPhrase) {
  if (count == 1) return '1 track $verbPhrase';
  return '$count tracks $verbPhrase';
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        icon,
        color: enabled
            ? AfColors.textSecondary
            : AfColors.textTertiary.withValues(alpha: 0.4),
        size: 22,
      ),
      title: Text(
        label,
        style: AfTypography.bodyMedium.copyWith(
          color: enabled
              ? AfColors.textPrimary
              : AfColors.textTertiary.withValues(alpha: 0.6),
        ),
      ),
      onTap: enabled ? onTap : null,
      dense: true,
    );
  }
}
