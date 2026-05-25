import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/models/items.dart';
import '../../core/local/m3u_parser.dart';

/// Service/Action to export playlist tracks to an M3U file.
class ExportM3UAction {
  const ExportM3UAction();

  /// Export [tracks] as an M3U file.
  Future<void> export({
    required List<AfTrack> tracks,
    required String playlistName,
    required BuildContext context,
  }) async {
    if (tracks.isEmpty) return;

    final entries = tracks.map((t) {
      return M3UEntry(
        duration: t.duration,
        artist: t.artistName,
        title: t.title,
        path: t.id, // track ID as path reference
        tags: {'id': t.id}, // store Aetherfin track ID as custom tag
      );
    }).toList();

    final m3uContent = M3uParser.write(entries);

    // Save to a temp file and show a toast/snack confirmation
    try {
      final tempDir = Directory.systemTemp;
      final file = File('${tempDir.path}/$playlistName.m3u');
      await file.writeAsString(m3uContent);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Exported "$playlistName.m3u" (${tracks.length} tracks) to temp storage',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to export: ${e.toString()}')),
        );
      }
    }
  }
}

/// Provider for ExportM3UAction.
final exportM3UActionProvider = Provider<ExportM3UAction>(
  (ref) => const ExportM3UAction(),
);
