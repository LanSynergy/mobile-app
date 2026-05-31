import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/async_error_view.dart';
import '../../widgets/opacity_app_bar.dart';
import '../../widgets/tile.dart';
import '../../widgets/skeletons/genre_skeleton.dart';

class GenreScreen extends ConsumerStatefulWidget {
  const GenreScreen({super.key, required this.genre});
  final String genre;

  @override
  ConsumerState<GenreScreen> createState() => _GenreScreenState();
}

class _GenreScreenState extends ConsumerState<GenreScreen> {
  final _scroll = ScrollController();
  late final ValueNotifier<double> _scrollOffset = ValueNotifier(0.0);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(
      () => _scrollOffset.value = _scroll.hasClients ? _scroll.offset : 0.0,
    );
  }

  @override
  void dispose() {
    _scrollOffset.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final albumsAsync = ref.watch(genreAlbumsProvider(widget.genre));

    return Scaffold(
      backgroundColor: AfColors.surfaceCanvas,
      body: albumsAsync.when(
        loading: () => const GenreSkeleton(),
        error: (e, _) => AsyncErrorView(
          label: 'Could not load genre',
          error: e,
          onRetry: () => ref.invalidate(genreAlbumsProvider(widget.genre)),
        ),
        data: (albums) {
          return Stack(
            children: [
              ValueListenableBuilder<double>(
                valueListenable: _scrollOffset,
                builder: (context, offset, _) => Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: OpacityAppBar(
                    scrollOffset: offset,
                    threshold: 140,
                    title: widget.genre,
                    onBack: () => context.pop(),
                  ),
                ),
              ),

              CustomScrollView(
                controller: _scroll,
                physics: const ClampingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.only(
                        top:
                            MediaQuery.of(context).padding.top +
                            kToolbarHeight +
                            AfSpacing.s16,
                        left: AfSpacing.gutterGenerous,
                        right: AfSpacing.gutterGenerous,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.genre,
                            style: AfTypography.display.copyWith(
                              color: AfColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: AfSpacing.s4),
                          Text(
                            albums.isEmpty
                                ? 'No albums'
                                : albums.length == 1
                                ? '1 album'
                                : '${albums.length} albums',
                            style: AfTypography.bodyMedium.copyWith(
                              color: AfColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (albums.isNotEmpty) ...[
                    const SliverToBoxAdapter(
                      child: SizedBox(height: AfSpacing.s24),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AfSpacing.s16,
                      ),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisExtent: 220,
                              crossAxisSpacing: AfSpacing.s16,
                              mainAxisSpacing: AfSpacing.s16,
                            ),
                        delegate: SliverChildBuilderDelegate((context, i) {
                          final a = albums[i];
                          return Tile(
                            title: a.name,
                            subtitle: a.artistName,
                            variant: TileVariant.album,
                            imageUrl: a.imageUrl,
                            size: double.infinity,
                            onTap: () => context.push('/album/${a.id}'),
                          );
                        }, childCount: albums.length),
                      ),
                    ),
                  ],
                  const SliverToBoxAdapter(
                    child: SizedBox(
                      height: AfSpacing.bottomInsetWithMiniAndNav,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
