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

/// Filter chips at the top of the results panel. Lets the user scope
/// to a single result type — when active, the per-type cap is lifted
/// so the full list is browsable (matches Spotify/Apple Music behavior).
enum SearchFilter { all, tracks, albums, artists, playlists }

extension on SearchFilter {
  String get label => switch (this) {
        SearchFilter.all => 'All',
        SearchFilter.tracks => 'Tracks',
        SearchFilter.albums => 'Albums',
        SearchFilter.artists => 'Artists',
        SearchFilter.playlists => 'Playlists',
      };
}

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  // ValueNotifier so only the results panel rebuilds on query change.
  final _queryNotifier = ValueNotifier<String>('');
  // Filter chip selection — independent ValueNotifier so toggling
  // chips doesn't force the search field or recent-history widget
  // to rebuild.
  final _filterNotifier = ValueNotifier<SearchFilter>(SearchFilter.all);

  static const _debounce = Duration(milliseconds: 250);
  Timer? _debounceTimer;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    _queryNotifier.dispose();
    _filterNotifier.dispose();
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
      // Persist the committed query as a recent search. We push on
      // debounce-commit (not every keystroke) so the history only
      // captures queries the user actually waited on a result for.
      unawaited(
        ref.read(searchHistoryProvider.notifier).push(normalized),
      );
    });
  }

  /// Re-run a recent search from the chip row — sets the field text,
  /// commits the query immediately (no debounce — the chip tap is
  /// already a deliberate commit), and re-promotes the entry to the
  /// head of the history.
  void _runRecent(String query) {
    _debounceTimer?.cancel();
    _controller.text = query;
    _controller.selection =
        TextSelection.collapsed(offset: query.length);
    _queryNotifier.value = query;
    unawaited(
      ref.read(searchHistoryProvider.notifier).push(query),
    );
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
                AfSpacing.s16,
              ),
              child: Row(
                children: [
                  Text('Search', style: AfTypography.titleLarge),
                  const Spacer(),
                  const SizedBox(width: 48), // match icon width for alignment
                ],
              ),
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
                    unawaited(
                      ref
                          .read(searchHistoryProvider.notifier)
                          .push(normalized),
                    );
                  }
                },
              ),
            ),
            const SizedBox(height: AfSpacing.s12),
            // Filter chips — only visible once a query is committed.
            ValueListenableBuilder<String>(
              valueListenable: _queryNotifier,
              builder: (context, query, _) {
                if (query.isEmpty) return const SizedBox.shrink();
                return ValueListenableBuilder<SearchFilter>(
                  valueListenable: _filterNotifier,
                  builder: (context, filter, _) => _SearchFilterChips(
                    selected: filter,
                    onChanged: (next) => _filterNotifier.value = next,
                  ),
                );
              },
            ),
            Expanded(
              // ValueListenableBuilder: only this subtree rebuilds on query change.
              child: ValueListenableBuilder<String>(
                valueListenable: _queryNotifier,
                builder: (context, query, _) => query.isEmpty
                    ? _SearchIdleState(onRecent: _runRecent)
                    : ValueListenableBuilder<SearchFilter>(
                        valueListenable: _filterNotifier,
                        builder: (context, filter, _) =>
                            _LiveSearchResults(query: query, filter: filter),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal filter chip row. Renders once a query is committed and
/// scopes the results to a single category (lifting the per-type cap).
class _SearchFilterChips extends StatelessWidget {
  final SearchFilter selected;
  final ValueChanged<SearchFilter> onChanged;
  const _SearchFilterChips({
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
        itemCount: SearchFilter.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: AfSpacing.s8),
        itemBuilder: (context, i) {
          final f = SearchFilter.values[i];
          final active = f == selected;
          return ChoiceChip(
            label: Text(f.label),
            selected: active,
            onSelected: (_) => onChanged(f),
            backgroundColor: AfColors.surfaceBase,
            selectedColor: AfColors.indigo700,
            labelStyle: AfTypography.bodySmall.copyWith(
              color: active ? AfColors.indigo300 : AfColors.textSecondary,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: active ? AfColors.indigo300 : AfColors.surfaceHigh,
              ),
            ),
            showCheckmark: false,
            padding: const EdgeInsets.symmetric(
                horizontal: AfSpacing.s8, vertical: 0),
          );
        },
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
  final SearchFilter filter;
  const _LiveSearchResults({required this.query, required this.filter});

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
        // Scope the buckets to the active filter so the list view
        // only renders the requested category. SearchFilter.all keeps
        // the original top-N preview layout.
        final tracks = filter == SearchFilter.all ||
                filter == SearchFilter.tracks
            ? res.tracks
            : const <AfTrack>[];
        final albums = filter == SearchFilter.all ||
                filter == SearchFilter.albums
            ? res.albums
            : const <AfAlbum>[];
        final artists = filter == SearchFilter.all ||
                filter == SearchFilter.artists
            ? res.artists
            : const <AfArtist>[];
        final playlists = filter == SearchFilter.all ||
                filter == SearchFilter.playlists
            ? res.playlists
            : const <AfPlaylist>[];
        final empty = tracks.isEmpty &&
            albums.isEmpty &&
            artists.isEmpty &&
            playlists.isEmpty;
        if (empty) {
          return Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AfSpacing.s16,
              vertical: AfSpacing.s24,
            ),
            child: Text(
              filter == SearchFilter.all
                  ? 'No results for "$query".'
                  : 'No ${filter.label.toLowerCase()} found for "$query".',
              style: AfTypography.bodyMedium.copyWith(
                color: AfColors.textTertiary,
              ),
            ),
          );
        }
        return _SearchResults(
          tracks: tracks,
          albums: albums,
          artists: artists,
          playlists: playlists,
          // When a single-type filter is active, drop the preview caps.
          unbounded: filter != SearchFilter.all,
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
  final void Function(String query) onRecent;
  const _SearchIdleState({required this.onRecent});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final genresAsync = ref.watch(allGenresProvider);
    final genres = genresAsync.maybeWhen(
      data: (g) => g,
      orElse: () => const <AfGenre>[],
    );
    final recent = ref.watch(searchHistoryProvider);

    return CustomScrollView(
      physics: const ClampingScrollPhysics(),
      slivers: [
        if (recent.isNotEmpty) ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AfSpacing.s16,
              0,
              AfSpacing.s16,
              0,
            ),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Expanded(
                    child: SectionHeader(
                      title: 'Recent',
                      uppercase: true,
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        ref.read(searchHistoryProvider.notifier).clear(),
                    style: TextButton.styleFrom(
                      foregroundColor: AfColors.textTertiary,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AfSpacing.s16,
              0,
              AfSpacing.s16,
              AfSpacing.s16,
            ),
            sliver: SliverToBoxAdapter(
              child: Wrap(
                spacing: AfSpacing.s8,
                runSpacing: AfSpacing.s8,
                children: [
                  for (final q in recent)
                    InputChip(
                      label: Text(q),
                      backgroundColor: AfColors.surfaceRaised,
                      side: BorderSide(color: AfColors.surfaceHigh),
                      labelStyle: AfTypography.bodySmall.copyWith(
                        color: AfColors.textPrimary,
                      ),
                      deleteIcon: const Icon(Icons.close_rounded, size: 16),
                      deleteIconColor: AfColors.textTertiary,
                      onPressed: () => onRecent(q),
                      onDeleted: () => ref
                          .read(searchHistoryProvider.notifier)
                          .remove(q),
                    ),
                ],
              ),
            ),
          ),
        ],
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
  /// When true, render every result of each type (no preview cap).
  /// Set when a single-type filter chip is active.
  final bool unbounded;

  const _SearchResults({
    required this.tracks,
    required this.albums,
    required this.artists,
    required this.playlists,
    this.unbounded = false,
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
          for (var i = 0;
              i < tracks.length && (unbounded || i < 20);
              i++)
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
          for (final a in unbounded ? albums : albums.take(10))
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
          for (final a in unbounded ? artists : artists.take(10))
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
          for (final p in unbounded ? playlists : playlists.take(10))
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
