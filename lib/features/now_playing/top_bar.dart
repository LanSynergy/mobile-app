import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/jellyfin/models/items.dart';
import '../../state/providers.dart';
import '../../widgets/track_details_sheet.dart';

class TopBar extends ConsumerWidget {
  const TopBar({super.key, required this.track});

  final AfTrack track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_downward_rounded),
          onPressed: () => Navigator.maybePop(context),
        ),
        if (track.albumId != null)
          GestureDetector(
            onTap: () => GoRouter.of(context).push('/album/${track.albumId}'),
            child: Text(
              track.albumName,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                    decoration: TextDecoration.underline,
                  ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_horiz),
          onSelected: (value) {
            switch (value) {
              case 'album':
                if (track.albumId != null) {
                  GoRouter.of(context).push('/album/${track.albumId}');
                }
              case 'artist':
                if (track.artistId != null) {
                  GoRouter.of(context).push('/artist/${track.artistId}');
                }
              case 'details':
                showTrackDetailsSheet(context, ref, track);
              case 'radio':
                ref.read(playerServiceProvider).playQueue(
                      [],
                      startIndex: 0,
                      resolveStreamUrl: (_) => '',
                    );
            }
          },
          itemBuilder: (context) => [
            if (track.albumId != null)
              const PopupMenuItem(
                value: 'album',
                child: ListTile(
                  leading: Icon(Icons.album),
                  title: Text('Go to album'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            if (track.artistId != null)
              const PopupMenuItem(
                value: 'artist',
                child: ListTile(
                  leading: Icon(Icons.person),
                  title: Text('Go to artist'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            const PopupMenuItem(
              value: 'details',
              child: ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Details'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem(
              value: 'radio',
              child: ListTile(
                leading: Icon(LucideIcons.radio),
                title: Text('Start radio'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

