import 'package:flutter/material.dart';

import '../../design_tokens/tokens.dart';
import '../../widgets/af_dialog.dart';

/// Confirm removing a track from the playlist.
Future<bool> confirmRemoveTrack(BuildContext context, String title) async {
  return await showBlurDialog<bool>(
        context: context,
        builder: (context, dismiss) => Column(
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
                  onPressed: () => dismiss(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => dismiss(true),
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

/// Confirm deleting the entire playlist.
Future<bool> confirmDeletePlaylist(
  BuildContext context,
  String playlistName,
) async {
  return await showBlurDialog<bool>(
        context: context,
        builder: (context, dismiss) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Delete playlist', style: AfTypography.titleMedium),
            const SizedBox(height: AfSpacing.s12),
            Text(
              'Delete "$playlistName"? This cannot be undone.',
              style: AfTypography.bodyMedium,
            ),
            const SizedBox(height: AfSpacing.s24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => dismiss(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => dismiss(true),
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
      ) ??
      false;
}

/// Show rename dialog and return the new name, or null if cancelled.
Future<String?> showRenamePlaylistDialog(
  BuildContext context,
  String currentName,
) async {
  final ctl = TextEditingController(text: currentName);
  try {
    return await showBlurDialog<String>(
      context: context,
      builder: (context, dismiss) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Rename playlist', style: AfTypography.titleMedium),
          const SizedBox(height: AfSpacing.s16),
          TextField(
            controller: ctl,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Playlist name'),
            onSubmitted: (v) => dismiss(v),
          ),
          const SizedBox(height: AfSpacing.s24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => dismiss(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => dismiss(ctl.text),
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
