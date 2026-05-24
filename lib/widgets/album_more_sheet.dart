import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../core/audio/play_actions.dart';
import '../core/jellyfin/models/items.dart';
import '../design_tokens/tokens.dart';
import '../state/providers.dart';

void showAlbumMoreSheet(
  BuildContext context,
  WidgetRef ref,
  AfAlbum album,
  List<AfTrack> tracks,
) {
  HapticFeedback.mediumImpact();
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetCtx) => ClipRRect(
      borderRadius: const BorderRadius.vertical(top: AfRadii.rXl),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xB30B0B14),
            border: Border(
              top: BorderSide(color: AfColors.surfaceLow, width: 1),
            ),
          ),
          child: SafeArea(
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
                  // Drag handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AfColors.textTertiary.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: AfSpacing.s12),
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
                    icon: FontAwesomeIcons.shuffle,
                    label: 'Shuffle play',
                    enabled: tracks.isNotEmpty,
                    onTap: () async {
                      Navigator.of(sheetCtx).pop();
                      await ref.read(playerServiceProvider).setAfShuffleMode(true);
                      await ref.read(playActionsProvider).playAlbum(tracks);
                    },
                  ),
                  _MenuItem(
                    icon: FontAwesomeIcons.play,
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
                    icon: FontAwesomeIcons.listUl,
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
                      icon: FontAwesomeIcons.user,
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
  final cache = ref.read(offlineCacheServiceProvider);
  final cacheEnabled = ref.read(offlineCacheEnabledProvider);
  final backend = ref.read(musicBackendProvider);
  if (backend == null) return null;
  return (t) {
    if (cacheEnabled) {
      final cachedUri = cache.cachedFileUri(t.id);
      if (cachedUri != null) return cachedUri;
    }
    final maxBitrate = ref.read(maxBitrateProvider);
    return backend.trackStreamUrl(t.id, maxBitrateKbps: maxBitrate == 0 ? null : maxBitrate);
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
  final FaIconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: FaIcon(
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
