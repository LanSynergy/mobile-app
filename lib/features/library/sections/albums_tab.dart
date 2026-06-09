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
///
/// Returns sliver-compatible widgets for use inside a [CustomScrollView].
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
          return const SliverToBoxAdapter(
            child: EmptyState(
              icon: LucideIcons.disc,
              title: 'No albums found',
              body: 'Albums from your library will appear here',
            ),
          );
        }
        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AfSpacing.s16,
            0,
            AfSpacing.s16,
            AfSpacing.bottomInsetWithMiniAndNav,
          ),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisExtent: 220,
              crossAxisSpacing: AfSpacing.s16,
              mainAxisSpacing: AfSpacing.s16,
            ),
            delegate: SliverChildBuilderDelegate((context, i) {
              final a = list[i];
              return Semantics(
                button: true,
                label: 'Album: ${a.name} by ${a.artistName}',
                child: Tile(
                  title: a.name,
                  subtitle: a.artistName,
                  variant: TileVariant.album,
                  imageUrl: a.imageUrl,
                  size: double.infinity,
                  onTap: () => context.push('/album/${a.id}'),
                  onLongPress: () => showAlbumContextMenu(context, ref, a),
                ),
              );
            }, childCount: list.length),
          ),
        );
      },
      loading: () => const SliverToBoxAdapter(
        child: LibrarySkeleton(mode: LibrarySkeletonMode.albums),
      ),
      error: (e, _) => SliverToBoxAdapter(
        child: AsyncErrorView(
          label: 'Couldn\u2019t load albums',
          error: e,
          onRetry: () => ref.invalidate(provider),
        ),
      ),
    );
  }
}
