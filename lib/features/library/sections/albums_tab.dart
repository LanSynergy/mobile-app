import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../design_tokens/tokens.dart';
import '../../../state/providers.dart';
import '../../../widgets/async_error_view.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/skeletons/library_skeleton.dart';
import '../../../widgets/tile.dart';
import '../../../widgets/track_context_menu.dart';

/// Albums grid — local or server.
class AlbumsTab extends ConsumerWidget {
  const AlbumsTab({required this.isLocal, super.key});
  final bool isLocal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = isLocal ? localAlbumsProvider : allAlbumsProvider;
    final async = ref.watch(provider);
    return async.when(
      data: (list) {
        if (list.isEmpty) {
          return const EmptyState(
            icon: LucideIcons.disc,
            title: 'No albums found',
            body: 'Albums from your library will appear here',
          );
        }
        const padding = EdgeInsets.symmetric(horizontal: AfSpacing.s16);
        return RepaintBoundary(
          child: GridView.builder(
            padding: padding.add(
              const EdgeInsets.only(
                bottom: AfSpacing.bottomInsetWithMiniAndNav,
              ),
            ),
            itemCount: list.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisExtent: 220,
              crossAxisSpacing: AfSpacing.s16,
              mainAxisSpacing: AfSpacing.s16,
            ),
            itemBuilder: (context, i) {
              final a = list[i];
              return Tile(
                title: a.name,
                subtitle: a.artistName,
                variant: TileVariant.album,
                imageUrl: a.imageUrl,
                size: double.infinity,
                onTap: () => context.push('/album/${a.id}'),
                onLongPress: () => showAlbumContextMenu(context, ref, a),
              );
            },
          ),
        );
      },
      loading: () => const LibrarySkeleton(mode: LibrarySkeletonMode.albums),
      error: (e, _) => AsyncErrorView(
        label: 'Couldn\u2019t load albums',
        error: e,
        onRetry: () => ref.invalidate(provider),
      ),
    );
  }
}
