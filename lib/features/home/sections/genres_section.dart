import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design_tokens/tokens.dart';
import '../../../state/providers.dart';
import '../../../utils/color_parse.dart';
import '../../../widgets/async_error_view.dart';
import '../../../widgets/section_header.dart';
import '../../../widgets/skeleton.dart';
import '../../../widgets/tile.dart';
import '../../library/library_screen.dart' show SongsPill, songsPillProvider;

/// Horizontal scroll of large genre cards with tint colour and glass overlay.
class GenresSection extends ConsumerWidget {
  const GenresSection({super.key, required this.isLocal});
  final bool isLocal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final genresAsync = isLocal
        ? ref.watch(localGenresProvider)
        : ref.watch(allGenresProvider);
    return SliverList(
      delegate: SliverChildListDelegate([
        const SizedBox(height: AfSpacing.sectionGap),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
          child: SectionHeader(
            title: 'Genres',
            actionLabel: 'See more',
            onActionTap: () {
              ref.read(songsPillProvider.notifier).state = SongsPill.genres;
              context.go('/library');
            },
          ),
        ),
        const SizedBox(height: AfSpacing.s12),
        SizedBox(
          height: 100,
          child: genresAsync.when(
            data: (genres) => ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
              itemCount: genres.length,
              // itemExtent enables layout caching for large lists.
              // 140px card width + 12px trailing separator gap per item.
              itemExtent: 140 + AfSpacing.s12,
              itemBuilder: (context, i) {
                final g = genres[i];
                final tint = parseHexColor(g.tint);
                return GenreTile(
                  name: g.name,
                  tint: tint,
                  imageUrl: g.imageUrl,
                  width: 140,
                  height: 100,
                  onTap: () {
                    ref.read(songsPillProvider.notifier).state =
                        SongsPill.genres;
                    context.go('/library');
                  },
                );
              },
            ),
            loading: () => Row(
              children: List.generate(
                3,
                (_) => const Padding(
                  padding: EdgeInsets.only(right: AfSpacing.s12),
                  child: SkeletonBlock(
                    width: 140,
                    height: 100,
                    borderRadius: AfRadii.borderMd,
                  ),
                ),
              ),
            ),
            error: (e, _) => AsyncErrorView.compact(
              label: 'Couldn\'t load genres',
              error: e,
              height: 100,
              onRetry: () => ref.invalidate(
                isLocal ? localGenresProvider : allGenresProvider,
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
