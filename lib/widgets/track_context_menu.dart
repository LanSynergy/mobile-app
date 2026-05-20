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
import '../utils/display_error.dart';
import 'af_dialog.dart';
import 'save_to_playlist_sheet.dart';
import 'track_details_sheet.dart';

/// Shows a track context menu as a popup dialog.
///
/// Actions:
///   - Like / Unlike (favorite toggle)
///   - Play next
///   - Add to queue
///   - Save to playlist
///   - Go to album
///   - Go to artist
///   - Show details
void showTrackContextMenu(
  BuildContext context,
  WidgetRef ref,
  AfTrack track,
) {
  HapticFeedback.mediumImpact();
  showAfDialog<void>(
    context: context,
    builder: (dialogCtx) => Consumer(
      builder: (ctx, innerRef, _) {
        final overrides = innerRef.watch(trackFavoriteOverridesProvider);
        final isFavorite = overrides[track.id] ?? track.isFavorite;
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: AfRadii.borderLg),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AfSpacing.s12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Track info header.
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AfSpacing.gutterGenerous,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AfTypography.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        track.artistName,
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
                  icon: isFavorite
                      ? CupertinoIcons.heart
                      : CupertinoIcons.heart,
                  iconColor: isFavorite ? AfColors.indigo300 : null,
                  label: isFavorite ? 'Remove from liked' : 'Add to liked',
                  onTap: () async {
                    Navigator.of(dialogCtx).pop();
                    try {
                      await innerRef.read(favoriteToggleProvider)(track);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(isFavorite
                                ? 'Removed from liked songs'
                                : 'Added to liked songs'),
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content:
                                Text(displayError(e, prefix: 'Failed')),
                          ),
                        );
                      }
                    }
                  },
                ),
                _MenuItem(
                  icon: CupertinoIcons.play,
                  label: 'Play next',
                  onTap: () {
                    _playNext(innerRef, track);
                    Navigator.of(dialogCtx).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content:
                              Text('"${track.title}" will play next')),
                    );
                  },
                ),
                _MenuItem(
                  icon: CupertinoIcons.music_note_list,
                  label: 'Add to queue',
                  onTap: () {
                    _addToQueue(innerRef, track);
                    Navigator.of(dialogCtx).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content:
                              Text('"${track.title}" added to queue')),
                    );
                  },
                ),
                _MenuItem(
                  icon: CupertinoIcons.plus,
                  label: 'Save to playlist',
                  onTap: () {
                    Navigator.of(dialogCtx).pop();
                    showSaveToPlaylistSheet(context, innerRef, track);
                  },
                ),
                if (track.albumId != null)
                  _MenuItem(
                    icon: CupertinoIcons.music_albums,
                    label: 'Go to album',
                    onTap: () {
                      Navigator.of(dialogCtx).pop();
                      context.push('/album/${track.albumId}');
                    },
                  ),
                if (track.artistId != null)
                  _MenuItem(
                    icon: CupertinoIcons.person,
                    label: 'Go to artist',
                    onTap: () {
                      Navigator.of(dialogCtx).pop();
                      context.push('/artist/${track.artistId}');
                    },
                  ),
                _MenuItem(
                  icon: CupertinoIcons.info,
                  label: 'Show details',
                  onTap: () {
                    Navigator.of(dialogCtx).pop();
                    showTrackDetailsSheet(context, innerRef, track);
                  },
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// Shows an album context menu as a popup dialog.
void showAlbumContextMenu(
  BuildContext context,
  WidgetRef ref,
  AfAlbum album,
) {
  HapticFeedback.mediumImpact();
  showAfDialog<void>(
    context: context,
    builder: (dialogCtx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: AfRadii.borderLg),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AfSpacing.s12),
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
              icon: CupertinoIcons.play_fill,
              label: 'Play album',
              onTap: () async {
                Navigator.of(dialogCtx).pop();
                final detail = await ref.read(
                    albumDetailProvider(album.id).future);
                if (detail != null) {
                  await ref.read(playActionsProvider).playAlbum(detail.tracks);
                }
              },
            ),
            if (album.artistId != null)
              _MenuItem(
                icon: Icons.person_outline_rounded,
                label: 'Go to artist',
                onTap: () {
                  Navigator.of(dialogCtx).pop();
                  context.push('/artist/${album.artistId}');
                },
              ),
          ],
        ),
      ),
    ),
  );
}

/// Build the stream-URL resolver for queue mutations.
///
/// In server mode the backend resolves track id → authenticated stream
/// URL. In local mode (no backend) the track id IS a `content://` URI
/// that mpv can open directly — matching the pattern used by
/// `PlayActions.playQueue`. The previous implementation early-returned
/// when `backend == null`, so "Play next" and "Add to queue" silently
/// did nothing in local mode while the snackbar still claimed success.
String Function(AfTrack)? _streamResolver(WidgetRef ref) {
  final mode = ref.read(appModeProvider);
  if (mode == AppMode.local) {
    return (t) => t.id;
  }
  final backend = ref.read(musicBackendProvider);
  if (backend == null) return null;
  return (t) => backend.trackStreamUrl(t.id, maxBitrateKbps: 320);
}

void _playNext(WidgetRef ref, AfTrack track) {
  final resolve = _streamResolver(ref);
  if (resolve == null) return;
  unawaited(ref.read(playerServiceProvider).playNext(
    track,
    resolveStreamUrl: resolve,
  ));
}

void _addToQueue(WidgetRef ref, AfTrack track) {
  final resolve = _streamResolver(ref);
  if (resolve == null) return;
  unawaited(ref.read(playerServiceProvider).addToQueue(
    track,
    resolveStreamUrl: resolve,
  ));
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: iconColor ?? AfColors.textSecondary, size: 22),
      title: Text(label, style: AfTypography.bodyMedium),
      onTap: onTap,
      dense: true,
    );
  }
}
