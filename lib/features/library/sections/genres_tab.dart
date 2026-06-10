import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../design_tokens/tokens.dart';
import '../../../state/providers.dart';
import '../../../utils/color_parse.dart';
import '../../../widgets/async_error_view.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/skeletons/library_skeleton.dart';
import '../../../widgets/tile.dart';

/// Genres grid — local or server.
///
/// Returns sliver-compatible widgets for use inside a [CustomScrollView].
class GenresTab extends ConsumerWidget {
  const GenresTab({required this.isLocal, super.key});
  final bool isLocal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = isLocal ? localGenresProvider : allGenresProvider;
    final async = ref.watch(provider);
    return async.when(
      data: (list) {
        if (list.isEmpty) {
          return const SliverToBoxAdapter(
            child: EmptyState(
              icon: LucideIcons.music2,
              title: 'No genres found',
              body: 'Genres from your library will appear here',
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
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: AfLayout.genreGridMaxTileExtent,
              mainAxisExtent: 96,
              crossAxisSpacing: AfSpacing.s12,
              mainAxisSpacing: AfSpacing.s12,
            ),
            delegate: SliverChildBuilderDelegate((context, i) {
              final g = list[i];
              final tint = parseGenreTint(g.tint);
              return GenreTile(
                name: g.name,
                tint: tint,
                imageUrl: g.imageUrl,
                width: double.infinity,
                height: double.infinity,
                onTap: () => context.push('/genre/${g.name}'),
              );
            }, childCount: list.length),
          ),
        );
      },
      loading: () => const SliverToBoxAdapter(
        child: LibrarySkeleton(mode: LibrarySkeletonMode.genres),
      ),
      error: (e, _) => SliverToBoxAdapter(
        child: AsyncErrorView(
          label: 'Couldn\u2019t load genres',
          error: e,
          onRetry: () => ref.invalidate(provider),
        ),
      ),
    );
  }
}

/// Parse a hex color string from the server, falling back to indigo on error.
Color parseGenreTint(String hex) =>
    parseHexColor(hex, fallback: AfColors.indigo600);
