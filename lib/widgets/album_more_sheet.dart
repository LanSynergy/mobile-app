import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/audio/play_actions.dart';
import '../core/jellyfin/models/items.dart';
import '../design_tokens/tokens.dart';
import '../state/providers.dart';
import 'af_dialog.dart';

void showAlbumMoreSheet(
  BuildContext context,
  WidgetRef ref,
  AfAlbum album,
  List<AfTrack> tracks,
) {
  HapticFeedback.mediumImpact();
  showBlurDialog<void>(
    context: context,
    builder: (context, dismiss) => Column(
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
              const SizedBox(height: AfSpacing.s2),
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
          icon: LucideIcons.shuffle,
          label: 'Shuffle play',
          enabled: tracks.isNotEmpty,
          onTap: () async {
            dismiss();
            await ref.read(playActionsProvider).playAlbum(tracks);
            await ref.read(playerServiceProvider).setAfShuffleMode(true);
          },
        ),
        _MenuItem(
          icon: LucideIcons.play,
          label: 'Play next',
          enabled: tracks.isNotEmpty,
          onTap: () {
            dismiss();
            _enqueue(ref, tracks, atFront: true);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(_enqueueLabel(tracks.length, 'will play next')),
              ),
            );
          },
        ),
        _MenuItem(
          icon: LucideIcons.list,
          label: 'Add to queue',
          enabled: tracks.isNotEmpty,
          onTap: () {
            dismiss();
            _enqueue(ref, tracks, atFront: false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(_enqueueLabel(tracks.length, 'added to queue')),
              ),
            );
          },
        ),
        if (album.artistId != null)
          _MenuItem(
            icon: LucideIcons.user,
            label: 'Go to artist',
            onTap: () {
              dismiss();
              context.push('/artist/${album.artistId}');
            },
          ),
      ],
    ),
  );
}

/// Build the stream-URL resolver for queue mutations, mirroring
/// `track_context_menu.dart`'s helper. In local mode the track id IS
/// the `content://` URI; in server mode the backend resolves it.
FutureOr<String> Function(AfTrack)? _streamResolver(WidgetRef ref) {
  final mode = ref.read(appModeProvider);
  if (mode == AppMode.local) {
    return (t) => t.id;
  }
  final cache = ref.read(offlineCacheServiceProvider);
  final cacheEnabled = ref.read(offlineCacheEnabledProvider);
  final backend = ref.read(musicBackendProvider);
  if (backend == null) return null;
  return (t) async {
    if (cacheEnabled) {
      final cachedUri = await cache.cachedFileUri(t.id);
      if (cachedUri != null) return cachedUri;
    }
    final maxBitrate = ref.read(maxBitrateProvider);
    return backend.trackStreamUrl(
      t.id,
      maxBitrateKbps: maxBitrate == 0 ? null : maxBitrate,
    );
  };
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
  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        icon,
        color: enabled
            ? AfColors.textSecondary
            : AfColors.textTertiary.withValues(alpha: 0.4),
        size: AfIconSizes.sm,
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
