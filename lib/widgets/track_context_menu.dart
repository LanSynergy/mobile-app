import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/audio/play_actions.dart';
import '../core/jellyfin/models/items.dart';
import '../design_tokens/tokens.dart';
import '../state/providers.dart';

/// Shows a track context menu as a popup dialog.
///
/// Actions:
///   - Play next
///   - Add to queue
///   - Go to album
///   - Go to artist
void showTrackContextMenu(
  BuildContext context,
  WidgetRef ref,
  AfTrack track,
) {
  HapticFeedback.mediumImpact();
  showDialog<void>(
    context: context,
    builder: (dialogCtx) => Dialog(
      backgroundColor: AfColors.surfaceBase,
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
              icon: Icons.playlist_play_rounded,
              label: 'Play next',
              onTap: () {
                _playNext(ref, track);
                Navigator.of(dialogCtx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('"${track.title}" will play next')),
                );
              },
            ),
            _MenuItem(
              icon: Icons.queue_music_rounded,
              label: 'Add to queue',
              onTap: () {
                _addToQueue(ref, track);
                Navigator.of(dialogCtx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text('"${track.title}" added to queue')),
                );
              },
            ),
            if (track.albumId != null)
              _MenuItem(
                icon: Icons.album_outlined,
                label: 'Go to album',
                onTap: () {
                  Navigator.of(dialogCtx).pop();
                  context.push('/album/${track.albumId}');
                },
              ),
            if (track.artistId != null)
              _MenuItem(
                icon: Icons.person_outline_rounded,
                label: 'Go to artist',
                onTap: () {
                  Navigator.of(dialogCtx).pop();
                  context.push('/artist/${track.artistId}');
                },
              ),
          ],
        ),
      ),
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
  showDialog<void>(
    context: context,
    builder: (dialogCtx) => Dialog(
      backgroundColor: AfColors.surfaceBase,
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
              icon: Icons.play_arrow_rounded,
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

void _playNext(WidgetRef ref, AfTrack track) {
  final backend = ref.read(musicBackendProvider);
  if (backend == null) return;
  unawaited(ref.read(playerServiceProvider).playNext(
    track,
    resolveStreamUrl: (t) => backend.trackStreamUrl(t.id, maxBitrateKbps: 320),
  ));
}

void _addToQueue(WidgetRef ref, AfTrack track) {
  final backend = ref.read(musicBackendProvider);
  if (backend == null) return;
  unawaited(ref.read(playerServiceProvider).addToQueue(
    track,
    resolveStreamUrl: (t) => backend.trackStreamUrl(t.id, maxBitrateKbps: 320),
  ));
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AfColors.textSecondary, size: 22),
      title: Text(label, style: AfTypography.bodyMedium),
      onTap: onTap,
      dense: true,
    );
  }
}
