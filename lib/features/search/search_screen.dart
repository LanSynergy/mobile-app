import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/section_header.dart';
import '../../widgets/track_row.dart';
import 'ask_sheet.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AfSpacing.s16,
              AfSpacing.s8,
              AfSpacing.s16,
              AfSpacing.s8,
            ),
            child: Text('Search', style: AfTypography.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
            child: TextField(
              controller: _controller,
              autofocus: false,
              decoration: const InputDecoration(
                hintText: 'Artists, albums, tracks…',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          const SizedBox(height: AfSpacing.s16),
          Expanded(
            child: _query.isEmpty
                ? _SearchIdleState(
                    onAskTap: () => AskSheet.show(context),
                  )
                : _LiveSearchResults(query: _query),
          ),
        ],
      ),
    );
  }
}

/// Live results panel — watches [searchProvider] so a flick of the
/// keyboard hits the Jellyfin server (`/Users/{id}/Items?searchTerm=`),
/// not `DemoLibrary`. Loading state is intentionally blank so the rapid
/// keystrokes don't trigger a spinner storm; an empty-result state has
/// its own message.
class _LiveSearchResults extends ConsumerWidget {
  final String query;
  const _LiveSearchResults({required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(searchProvider(query));
    return async.maybeWhen(
      data: (res) => _SearchResults(
        tracks: res.tracks,
        albums: res.albums,
        artists: res.artists,
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AfSpacing.s16,
          vertical: AfSpacing.s24,
        ),
        child: Text(
          'Search failed: $e',
          style: AfTypography.bodySmall.copyWith(
            color: AfColors.semanticError,
          ),
        ),
      ),
      orElse: () => const SizedBox.shrink(),
    );
  }
}

/// Idle (empty query) panel. Genres come from `allGenresProvider` so
/// signed-in users see their real library, signed-out users see the
/// demo palette — single source of truth, no duplicated fallback.
class _SearchIdleState extends ConsumerWidget {
  final VoidCallback onAskTap;
  const _SearchIdleState({required this.onAskTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final genresAsync = ref.watch(allGenresProvider);
    final genres = genresAsync.maybeWhen(
      data: (g) => g,
      orElse: () => const <AfGenre>[],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
      child: ListView(
        children: [
          SectionHeader(title: 'Recent', uppercase: true),
          const SizedBox(height: AfSpacing.s12),
          Wrap(
            spacing: AfSpacing.s8,
            runSpacing: AfSpacing.s8,
            children: [
              for (final label in const [
                'Skylark',
                'Velvet Signal',
                'Field Notes',
                'Lumen Tide',
              ])
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AfSpacing.s12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AfColors.surfaceBase,
                    borderRadius: AfRadii.borderPill,
                  ),
                  child: Text(label, style: AfTypography.bodySmall),
                ),
            ],
          ),
          const SizedBox(height: AfSpacing.s24),
          SectionHeader(title: 'Genres', uppercase: true),
          const SizedBox(height: AfSpacing.s12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: genres.length,
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisExtent: 80,
              crossAxisSpacing: AfSpacing.s12,
              mainAxisSpacing: AfSpacing.s12,
            ),
            itemBuilder: (context, i) {
              final g = genres[i];
              final tint = Color(int.parse(
                  g.tint.replaceFirst('#', '0xFF')));
              return Container(
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: AfRadii.borderMd,
                ),
                padding: const EdgeInsets.all(AfSpacing.s12),
                alignment: Alignment.bottomLeft,
                child: Text(
                  g.name,
                  style: AfTypography.titleSmall.copyWith(
                    color: AfColors.textOnPrimary,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: AfSpacing.s24),
          GestureDetector(
            onTap: onAskTap,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AfSpacing.s16,
                vertical: AfSpacing.s12,
              ),
              decoration: BoxDecoration(
                color: AfColors.surfaceBase,
                borderRadius: AfRadii.borderPill,
                border: Border.all(
                    color: AfColors.surfaceHigh, width: 1),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome_rounded,
                      color: AfColors.indigo300, size: 20),
                  const SizedBox(width: AfSpacing.s12),
                  Expanded(
                    child: Text(
                      'Ask your library…',
                      style: AfTypography.bodyMedium.copyWith(
                        color: AfColors.textSecondary,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: AfColors.textTertiary),
                ],
              ),
            ),
          ),
          const SizedBox(height: AfSpacing.bottomInsetWithMiniAndNav),
        ],
      ),
    );
  }
}

class _SearchResults extends StatelessWidget {
  final List<AfTrack> tracks;
  final List<AfAlbum> albums;
  final List<AfArtist> artists;

  const _SearchResults({
    required this.tracks,
    required this.albums,
    required this.artists,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
      children: [
        if (tracks.isNotEmpty) ...[
          SectionHeader(title: 'Tracks', uppercase: true),
          const SizedBox(height: AfSpacing.s8),
          for (final t in tracks.take(4))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: TrackRow(track: t),
            ),
          const SizedBox(height: AfSpacing.s16),
        ],
        if (albums.isNotEmpty) ...[
          SectionHeader(title: 'Albums', uppercase: true),
          const SizedBox(height: AfSpacing.s8),
          for (final a in albums.take(3))
            ListTile(
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: AfRadii.borderSm,
                  gradient: const LinearGradient(
                    colors: [AfColors.indigo700, AfColors.indigo900],
                  ),
                ),
                child: const Icon(Icons.album_outlined,
                    color: AfColors.indigo300),
              ),
              title: Text(a.name, style: AfTypography.bodyMedium),
              subtitle: Text(
                a.artistName,
                style: AfTypography.bodySmall.copyWith(
                  color: AfColors.textTertiary,
                ),
              ),
              tileColor: Colors.transparent,
              contentPadding: EdgeInsets.zero,
            ),
          const SizedBox(height: AfSpacing.s16),
        ],
        if (artists.isNotEmpty) ...[
          SectionHeader(title: 'Artists', uppercase: true),
          const SizedBox(height: AfSpacing.s8),
          for (final a in artists.take(3))
            ListTile(
              leading: CircleAvatar(
                radius: 22,
                backgroundColor: AfColors.indigo800,
                child: Text(
                  a.name.substring(0, 1),
                  style: AfTypography.titleSmall.copyWith(
                    color: AfColors.textOnPrimary,
                  ),
                ),
              ),
              title: Text(a.name, style: AfTypography.bodyMedium),
              subtitle: Text(
                a.statLine,
                style: AfTypography.bodySmall.copyWith(
                  color: AfColors.textTertiary,
                ),
              ),
              tileColor: Colors.transparent,
              contentPadding: EdgeInsets.zero,
            ),
          const SizedBox(height: AfSpacing.s16),
        ],
        if (tracks.isEmpty && albums.isEmpty && artists.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AfSpacing.s24),
            child: Text(
              'No results in your library.',
              textAlign: TextAlign.center,
              style: AfTypography.bodyMedium.copyWith(
                color: AfColors.textTertiary,
              ),
            ),
          ),
        const SizedBox(height: AfSpacing.bottomInsetWithMiniAndNav),
      ],
    );
  }
}
