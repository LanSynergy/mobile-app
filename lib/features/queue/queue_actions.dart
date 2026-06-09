import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend/music_backend.dart';
import '../../core/jellyfin/models/items.dart';
import '../../core/youtube/youtube_music_client.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../utils/display_error.dart';
import '../../utils/log.dart';
import '../../widgets/af_dialog.dart';

/// Prompts for a name and creates a new playlist containing every
/// track in [items]. The default name is "Queue · YYYY-MM-DD HH:mm"
/// so distinct saves never collide visually.
///
/// Works in both local and server modes — both backends implement
/// `MusicBackend.createPlaylist`. Returns silently when [items] is empty.
Future<void> saveQueueAsPlaylist(
  BuildContext context,
  WidgetRef ref,
  List<AfTrack> items,
) async {
  if (items.isEmpty) return;
  final backend = ref.read(musicBackendProvider);
  if (backend == null) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Sign in to save playlists')));
    return;
  }

  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final defaultName =
      'Queue · ${now.year}-${two(now.month)}-${two(now.day)} '
      '${two(now.hour)}:${two(now.minute)}';
  final controller = TextEditingController(text: defaultName);
  final String? name;
  try {
    name = await showBlurDialog<String>(
      context: context,
      builder: (context, dismiss) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Save queue as playlist', style: AfTypography.titleMedium),
          const SizedBox(height: AfSpacing.s16),
          TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Playlist name',
              hintText: 'Playlist name',
              border: OutlineInputBorder(
                borderRadius: AfRadii.borderSm,
                borderSide: BorderSide(color: AfColors.surfaceHigh),
              ),
            ),
            onSubmitted: (v) => dismiss(v.trim()),
          ),
          const SizedBox(height: AfSpacing.s24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => dismiss(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => dismiss(controller.text.trim()),
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  } finally {
    controller.dispose();
  }

  if (name == null || name.isEmpty || !context.mounted) return;

  final snapshot = List<String>.from(items.map((t) => t.id));
  try {
    await backend.createPlaylist(name, snapshot);
    ref.invalidate(allPlaylistsProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved as "$name" · ${snapshot.length} tracks')),
    );
  } on Exception catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(displayError(e, prefix: 'Failed to save queue'))),
    );
  }
}

/// Resolve a stream URL for the track — used by undo-reinsert logic.
///
/// Handles local content URIs, YouTube Music, offline cache, and
/// standard server streaming.
Future<String> resolveTrackStreamUrl(
  AfTrack track, {
  required AppMode mode,
  required MusicBackend? backend,
  required WidgetRef ref,
}) async {
  if (mode == AppMode.local) return track.id;

  if (backend is YouTubeMusicClient) {
    try {
      return await backend.resolveStreamUrl(track.id);
    } on Exception catch (e) {
      afLog('audio', 'YouTube stream resolve failed', error: e);
      return 'about:blank';
    }
  }

  final cacheEnabled = ref.read(offlineCacheEnabledProvider);
  if (cacheEnabled) {
    final cache = ref.read(offlineCacheServiceProvider);
    final cachedUri = await cache.cachedFileUri(track.id);
    if (cachedUri != null) return cachedUri;
  }
  if (backend != null) {
    final maxBitrate = ref.read(maxBitrateProvider);
    return backend.trackStreamUrl(
      track.id,
      maxBitrateKbps: maxBitrate == 0 ? null : maxBitrate,
    );
  }
  return 'about:blank';
}
