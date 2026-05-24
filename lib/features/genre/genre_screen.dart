import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/async_error_view.dart';
import '../../widgets/tile.dart';
import '../../widgets/track_context_menu.dart';

/// Albums filtered by genre. Uses Jellyfin's `Genres=` query parameter
/// via [genreAlbumsProvider] so only albums actually tagged with this
/// genre are shown.
class GenreScreen extends ConsumerWidget {
  const GenreScreen({super.key, required this.genreName});
  final String genreName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albumsAsync = ref.watch(genreAlbumsProvider(genreName));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: Text(genreName, style: AfTypography.titleMedium),
      ),
      body: albumsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AsyncErrorView(
          label: 'Could not load "$genreName"',
          error: e,
          onRetry: () => ref.invalidate(genreAlbumsProvider(genreName)),
        ),
        data: (albums) {
          if (albums.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AfSpacing.gutterGenerous,
                ),
                child: Text(
                  'No albums found for "$genreName".',
                  style: AfTypography.bodyMedium.copyWith(
                    color: AfColors.textTertiary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(
              AfSpacing.s16,
              AfSpacing.s16,
              AfSpacing.s16,
              AfSpacing.bottomInsetWithMiniAndNav,
            ),
            itemCount: albums.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisExtent: 220,
              crossAxisSpacing: AfSpacing.s16,
              mainAxisSpacing: AfSpacing.s16,
            ),
            itemBuilder: (context, i) {
              final a = albums[i];
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
          );
        },
      ),
    );
  }
}
