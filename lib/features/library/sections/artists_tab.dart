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

/// Artists grid — local or server.
///
/// Returns sliver-compatible widgets for use inside a [CustomScrollView].
class ArtistsTab extends ConsumerWidget {
  const ArtistsTab({required this.isLocal, super.key});
  final bool isLocal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = isLocal ? localArtistsProvider : allArtistsProvider;
    final async = ref.watch(provider);
    return async.when(
      data: (list) {
        if (list.isEmpty) {
          return const SliverToBoxAdapter(
            child: EmptyState(
              icon: LucideIcons.users,
              title: 'No artists found',
              body: 'Artists from your library will appear here',
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
              crossAxisCount: 3,
              mainAxisExtent: 180,
              crossAxisSpacing: AfSpacing.s12,
              mainAxisSpacing: AfSpacing.s12,
            ),
            delegate: SliverChildBuilderDelegate((context, i) {
              final a = list[i];
              return Tile(
                title: a.name,
                subtitle: a.statLine,
                variant: TileVariant.artist,
                imageUrl: a.imageUrl,
                size: double.infinity,
                onTap: () => context.push('/artist/${a.id}'),
              );
            }, childCount: list.length),
          ),
        );
      },
      loading: () => const SliverToBoxAdapter(
        child: LibrarySkeleton(mode: LibrarySkeletonMode.artists),
      ),
      error: (e, _) => SliverToBoxAdapter(
        child: AsyncErrorView(
          label: 'Couldn\u2019t load artists',
          error: e,
          onRetry: () => ref.invalidate(provider),
        ),
      ),
    );
  }
}
