import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/audio/play_actions.dart';
import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../utils/display_error.dart';
import '../../widgets/artwork.dart';
import '../../widgets/section_header.dart';
import '../../widgets/track_context_menu.dart';
import '../../widgets/track_row.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SearchScreen
//
// Architecture
// ────────────
// • Query state lives in a ValueNotifier<String> so only the results
//   panel rebuilds on keystroke — the search field and header are static.
//
// • Normalization: queries are trimmed + lowercased before comparison so
//   "Radiohead", "radiohead ", " RADIOHEAD" all hit the same provider key.
//
// • Minimum length: queries shorter than 2 chars don't fire a request.
//
// • Stale-result guard: Riverpod autoDispose.family cancels in-flight
//   requests when the query key changes. The when() builder (not maybeWhen)
//   surfaces loading state so the user sees a skeleton instead of stale data.
// ─────────────────────────────────────────────────────────────────────────────

/// Minimum query length before a server request is fired.
const _kMinQueryLength = 2;

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  // ValueNotifier so only the results panel rebuilds on query change.
  final _queryNotifier = ValueNotifier<String>('');

  static const _debounce = Duration(milliseconds: 250);
  Timer? _debounceTimer;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    _queryNotifier.dispose();
    super.dispose();
  }

  void _onChanged(String raw) {
    _debounceTimer?.cancel();
    // Normalize: trim + lowercase for consistent provider key.
    final normalized = raw.trim().toLowerCase();

    // Empty → collapse to idle immediately (feels instant on clear).
    if (normalized.isEmpty) {
      _queryNotifier.value = '';
      return;
    }

    // Below minimum length → show idle, don't fire request.
    if (normalized.length < _kMinQueryLength) {
      _queryNotifier.value = '';
      return;
    }

    // Debounce: wait for typing to settle before firing.
    _debounceTimer = Timer(_debounce, () {
      if (!mounted) return;
      if (_queryNotifier.value == normalized) return;
      _queryNotifier.value = normalized;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AfColors.surfaceCanvas,
      child: SafeArea(
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
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Artists, albums, tracks…',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onChanged: _onChanged,
                onSubmitted: (_) {
                  // Commit immediately on keyboard search action.
                  _debounceTimer?.cancel();
                  final normalized = _controller.text.trim().toLowerCase();
                  if (normalized.length >= _kMinQueryLength) {
                    _queryNotifier.value = normalized;
                  }
                },
              ),
            ),
            const SizedBox(height: AfSpacing.s16),
            Expanded(
              // ValueListenableBuilder: only this subtree rebuilds on query change.
              child: ValueListenableBuilder<String>(
                valueListenable: _queryNotifier,
                builder: (context, query, _) => query.isEmpty
                    ? const _SearchIdleState()
                    : _LiveSearchResults(query: query),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Live results panel.
///
/// Uses when() (not maybeWhen) so loading state shows a skeleton instead
/// of stale data. Riverpod autoDispose.family cancels the in-flight request
/// when the query key changes, preventing stale-result races.
class _LiveSearchResults extends ConsumerWidget {
  final String query;
  const _LiveSearchResults({required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(searchProvider(query));
    return async.when(
      loading: () => const _SearchLoadingSkeleton(),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AfSpacing.s16,
          vertical: AfSpacing.s24,
        ),
        child: Text(
          // displayError redacts the api_key / `t` / `s` / `u` query
          // params Dio includes in `DioException.toString()` — those
          // would otherwise land on screen verbatim on a search failure.
          displayError(e, prefix: 'Search failed'),
          style: AfTypography.bodySmall.copyWith(
            color: AfColors.semanticError,
          ),
        ),
      ),
      data: (res) {
        final empty = res.tracks.isEmpty &&
            res.albums.isEmpty &&
            res.artists.isEmpty &&
            res.playlists.isEmpty;
        if (empty) {
          return Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AfSpacing.s16,
              vertical: AfSpacing.s24,
            ),
            child: Text(
              'No results for "$query".',
              style: AfTypography.bodyMedium.copyWith(
                color: AfColors.textTertiary,
              ),
            ),
          );
        }
        return _SearchResults(
          tracks: res.tracks,
          albums: res.albums,
          artists: res.artists,
          playlists: res.playlists,
        );
      },
    );
  }
}

/// Subtle loading skeleton — avoids the "frozen UI" feeling of a blank
/// state while preventing spinner storms on fast networks.
class _SearchLoadingSkeleton extends StatelessWidget {
  const _SearchLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AfSpacing.s16,
        vertical: AfSpacing.s24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < 5; i++) ...[
            _SkeletonBar(width: i.isEven ? 200 : 140, height: 14),
            const SizedBox(height: AfSpacing.s12),
          ],
        ],
      ),
    );
  }
}

class _SkeletonBar extends StatelessWidget {
  final double width;
  final double height;
  const _SkeletonBar({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AfColors.surfaceBase,
        borderRadius: AfRadii.borderSm,
      ),
    );
  }
}

/// Idle (empty query) panel — uses CustomScrollView + slivers to avoid
/// the shrinkWrap GridView-inside-ListView layout penalty.
class _SearchIdleState extends ConsumerWidget {
  const _SearchIdleState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final genresAsync = ref.watch(allGenresProvider);
    final genres = genresAsync.maybeWhen(
      data: (g) => g,
      orElse: () => const <AfGenre>[],
    );

    return CustomScrollView(
      physics: const ClampingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
          sliver: SliverToBoxAdapter(
            child: SectionHeader(title: 'Genres', uppercase: true),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: AfSpacing.s12)),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisExtent: 80,
              crossAxisSpacing: AfSpacing.s12,
              mainAxisSpacing: AfSpacing.s12,
            ),
            itemCount: genres.length,
            itemBuilder: (context, i) {
              final g = genres[i];
              // Defensive color parsing — malformed server hex won't crash.
              final tint = _parseTint(g.tint);
              return GestureDetector(
                onTap: () =>
                    context.push('/genre/${Uri.encodeComponent(g.name)}'),
                child: Container(
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
                ),
              );
            },
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: AfSpacing.s24)),
        const SliverToBoxAdapter(
          child: SizedBox(height: AfSpacing.bottomInsetWithMiniAndNav),
        ),
      ],
    );
  }

  /// Parse a hex color string from the server, falling back to indigo on error.
  static Color _parseTint(String hex) {
    try {
      final cleaned = hex.replaceFirst('#', '');
      if (cleaned.length != 6 && cleaned.length != 8) return AfColors.indigo600;
      final value = int.parse(
        cleaned.length == 6 ? 'FF$cleaned' : cleaned,
        radix: 16,
      );
      return Color(value);
    } catch (_) {
      return AfColors.indigo600;
    }
  }
}

class _SearchResults extends ConsumerWidget {
  final List<AfTrack> tracks;
  final List<AfAlbum> albums;
  final List<AfArtist> artists;
  final List<AfPlaylist> playlists;

  const _SearchResults({
    required this.tracks,
    required this.albums,
    required this.artists,
    required this.playlists,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AfSpacing.s16,
        0,
        AfSpacing.s16,
        AfSpacing.bottomInsetWithMiniAndNav,
      ),
      children: [
        if (tracks.isNotEmpty) ...[
          SectionHeader(title: 'Tracks', uppercase: true),
          const SizedBox(height: AfSpacing.s8),
          for (var i = 0; i < tracks.length && i < 20; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: TrackRow(
                track: tracks[i],
                onTap: () => ref
                    .read(playActionsProvider)
                    .playQueue(tracks, startIndex: i),
                onLongPress: () =>
                    showTrackContextMenu(context, ref, tracks[i]),
              ),
            ),
          const SizedBox(height: AfSpacing.s16),
        ],
        if (albums.isNotEmpty) ...[
          SectionHeader(title: 'Albums', uppercase: true),
          const SizedBox(height: AfSpacing.s8),
          for (final a in albums.take(10))
            ListTile(
              leading: SizedBox(
                width: 44,
                height: 44,
                child: Artwork(url: a.imageUrl, size: 44),
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
              onTap: () => context.push('/album/${a.id}'),
            ),
          const SizedBox(height: AfSpacing.s16),
        ],
        if (artists.isNotEmpty) ...[
          SectionHeader(title: 'Artists', uppercase: true),
          const SizedBox(height: AfSpacing.s8),
          for (final a in artists.take(10))
            ListTile(
              // Use Artwork widget (cached_network_image) instead of raw
              // NetworkImage to avoid repeated fetches and memory spikes.
              leading: Artwork(
                url: a.imageUrl,
                size: 44,
                radius: BorderRadius.circular(22),
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
              onTap: () => context.push('/artist/${a.id}'),
            ),
          const SizedBox(height: AfSpacing.s16),
        ],
        if (playlists.isNotEmpty) ...[
          SectionHeader(title: 'Playlists', uppercase: true),
          const SizedBox(height: AfSpacing.s8),
          for (final p in playlists.take(10))
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
                child: const Icon(Icons.playlist_play_rounded,
                    color: AfColors.indigo300),
              ),
              title: Text(p.name, style: AfTypography.bodyMedium),
              subtitle: Text(
                p.trackCountLabel,
                style: AfTypography.bodySmall.copyWith(
                  color: AfColors.textTertiary,
                ),
              ),
              tileColor: Colors.transparent,
              contentPadding: EdgeInsets.zero,
              onTap: () => context.push('/playlist/${p.id}'),
            ),
        ],
      ],
    );
  }
}
