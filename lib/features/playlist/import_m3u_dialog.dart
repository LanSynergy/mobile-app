import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/local/local_backend.dart';
import '../../core/local/m3u_parser.dart';
import '../../state/providers.dart';

/// Service/Action to import an M3U playlist.
class ImportM3UAction {
  ImportM3UAction(this._ref);
  final Ref _ref;

  /// Open a paste dialog, parse the M3U content, resolve tracks,
  /// and create a new playlist.
  Future<void> import({required BuildContext context}) async {
    final controller = TextEditingController();
    final content = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Import M3U Playlist'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Paste the M3U content below to import it as a new playlist. '
              'Tracks will be resolved by ID or name search.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 8,
              decoration: const InputDecoration(
                hintText: 'Paste M3U content here...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (content == null || content.trim().isEmpty || !context.mounted) return;

    final parsed = M3uParser.parse(content);
    if (parsed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No tracks found in M3U content')),
      );
      return;
    }

    final backend = _ref.read(musicBackendProvider);
    if (backend == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to import playlists')),
      );
      return;
    }

    // Show loading dialog during resolution
    if (!context.mounted) return;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      ),
    );

    final resolved = <String>[];
    var failed = 0;

    for (final entry in parsed) {
      try {
        final aetherfinId = entry.tags['id'];
        // Try resolving by Aetherfin ID first
        if (aetherfinId != null) {
          if (backend is LocalBackend) {
            final track = await backend.db.trackById(aetherfinId);
            if (track != null) {
              resolved.add(track.id);
              continue;
            }
          } else {
            final details = await backend.trackDetails(aetherfinId);
            if (details != null) {
              resolved.add(details.track.id);
              continue;
            }
          }
        }

        // Fallback: search by title + artist
        final artist = entry.artist;
        final title = entry.title;
        final query =
            (artist != null &&
                artist.isNotEmpty &&
                title != null &&
                title.isNotEmpty)
            ? '$artist - $title'
            : (title ?? entry.path);
        final searchResult = await backend.search(query);
        if (searchResult.tracks.isNotEmpty) {
          resolved.add(searchResult.tracks.first.id);
        } else {
          failed++;
        }
      } catch (_) {
        failed++;
      }
    }

    // Dismiss loading dialog
    if (context.mounted) {
      Navigator.of(context).pop();
    }

    if (resolved.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not resolve any tracks in the M3U content'),
          ),
        );
      }
      return;
    }

    final playlistName =
        'Imported M3U (${DateTime.now().month}/${DateTime.now().day})';
    try {
      final playlistId = await backend.createPlaylist(playlistName, resolved);
      if (playlistId == null) throw Exception('Failed to create playlist');

      if (context.mounted) {
        _ref.invalidate(allPlaylistsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Imported ${resolved.length}/${parsed.length} tracks'
              '${failed > 0 ? '. $failed could not be found.' : ''}',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create playlist: ${e.toString()}')),
        );
      }
    }
  }
}

/// Provider for ImportM3UAction.
final importM3UActionProvider = Provider<ImportM3UAction>(ImportM3UAction.new);
