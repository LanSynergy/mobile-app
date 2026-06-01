import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/audio/play_actions.dart';
import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../utils/display_error.dart';
import '../../widgets/artwork.dart';
import '../../widgets/section_header.dart';
import '../../widgets/tile.dart';
import '../../widgets/track_context_menu.dart';
import '../../widgets/track_row.dart';
import '../../widgets/af_scrollbar.dart';
import '../../widgets/skeletons/search_skeleton.dart';

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
      unawaited(ref.read(searchHistoryProvider.notifier).push(normalized));
    });
  }

  /// Re-run a recent search from the chip row — sets the field text,
  /// commits the query immediately (no debounce — the chip tap is
  /// already a deliberate commit), and re-promotes the entry to the
  /// head of the history.
  void _runRecent(String query) {
    _debounceTimer?.cancel();
    _controller.text = query;
    _controller.selection = TextSelection.collapsed(offset: query.length);
    _queryNotifier.value = query;
    unawaited(ref.read(searchHistoryProvider.notifier).push(query));
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
                prefixIcon: Icon(
                  LucideIcons.search,
                  color: AfColors.textTertiary,
                  size: 22,
                ),
              ),
              onChanged: _onChanged,
              onSubmitted: (_) {
                // Commit immediately on keyboard search action.
                _debounceTimer?.cancel();
                final normalized = _controller.text.trim().toLowerCase();
                if (normalized.length >= _kMinQueryLength) {
                  _queryNotifier.value = normalized;
                  unawaited(
                    ref.read(searchHistoryProvider.notifier).push(normalized),
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
    );
  }
}

/// Horizontal filter chip row. Renders once a query is committed and
/// scopes the results to a single category (lifting the per-type cap).
class _SearchFilterChips extends StatelessWidget {
  const _SearchFilterChips({required this.selected, required this.onChanged});
  final SearchFilter selected;
  final ValueChanged<SearchFilter> onChanged;

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
              borderRadius: AfRadii.borderPill,
              side: BorderSide(
                color: active ? AfColors.indigo300 : AfColors.surfaceHigh,
              ),
            ),
            showCheckmark: false,
            padding: const EdgeInsets.symmetric(
              horizontal: AfSpacing.s8,
              vertical: 0,
            ),
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
  const _LiveSearchResults({required this.query, required this.filter});
  final String query;
  final SearchFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(searchProvider(query));
    return async.when(
      loading: () => const SearchSkeleton(),
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
          style: AfTypography.bodySmall.copyWith(color: AfColors.semanticError),
        ),
      ),
      data: (res) {
        // Scope the buckets to the active filter so the list view
        // only renders the requested category. SearchFilter.all keeps
        // the original top-N preview layout.
        final tracks =
            filter == SearchFilter.all || filter == SearchFilter.tracks
            ? res.tracks
            : const <AfTrack>[];
        final albums =
            filter == SearchFilter.all || filter == SearchFilter.albums
            ? res.albums
            : const <AfAlbum>[];
        final artists =
            filter == SearchFilter.all || filter == SearchFilter.artists
            ? res.artists
            : const <AfArtist>[];
        final playlists =
            filter == SearchFilter.all || filter == SearchFilter.playlists
            ? res.playlists
            : const <AfPlaylist>[];
        final empty =
            tracks.isEmpty &&
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

/// Idle (empty query) panel — shows recent searches + pill selector
/// (Artists | Genres | Albums) with a browsable grid.
class _SearchIdleState extends ConsumerStatefulWidget {
  const _SearchIdleState({required this.onRecent});
  final void Function(String query) onRecent;

  @override
  ConsumerState<_SearchIdleState> createState() => _SearchIdleStateState();
}

enum _IdleFilter { artists, genres, albums }

extension on _IdleFilter {
  String get label => switch (this) {
    _IdleFilter.artists => 'Artists',
    _IdleFilter.genres => 'Genres',
    _IdleFilter.albums => 'Albums',
  };
}

class _SearchIdleStateState extends ConsumerState<_SearchIdleState> {
  _IdleFilter _filter = _IdleFilter.artists;

  @override
  Widget build(BuildContext context) {
    final recent = ref.watch(searchHistoryProvider);
    final mode = ref.watch(appModeProvider);
    final isLocal = mode == AppMode.local;

    return AfScrollbar(
      child: CustomScrollView(
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
                    const Expanded(
                      child: SectionHeader(title: 'Recent', uppercase: true),
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
                        side: const BorderSide(color: AfColors.surfaceHigh),
                        labelStyle: AfTypography.bodySmall.copyWith(
                          color: AfColors.textPrimary,
                        ),
                        deleteIcon: const Icon(Icons.close_rounded, size: 16),
                        deleteIconColor: AfColors.textTertiary,
                        onPressed: () => widget.onRecent(q),
                        onDeleted: () =>
                            ref.read(searchHistoryProvider.notifier).remove(q),
                      ),
                  ],
                ),
              ),
            ),
          ],
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
            sliver: SliverToBoxAdapter(
              child: _IdleFilterPills(
                selected: _filter,
                onChanged: (v) => setState(() => _filter = v),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AfSpacing.s12)),
          ..._buildGrid(isLocal),
          const SliverToBoxAdapter(
            child: SizedBox(height: AfSpacing.bottomInsetWithMiniAndNav),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildGrid(bool isLocal) {
    switch (_filter) {
      case _IdleFilter.artists:
        return [_ArtistIdleGrid(isLocal: isLocal)];
      case _IdleFilter.genres:
        return [_GenreIdleGrid(isLocal: isLocal)];
      case _IdleFilter.albums:
        return [_AlbumIdleGrid(isLocal: isLocal)];
    }
  }
}

class _IdleFilterPills extends StatelessWidget {
  const _IdleFilterPills({required this.selected, required this.onChanged});
  final _IdleFilter selected;
  final ValueChanged<_IdleFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _IdleFilter.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: AfSpacing.s8),
        itemBuilder: (context, i) {
          final f = _IdleFilter.values[i];
          final active = f == selected;
          return GestureDetector(
            onTap: () => onChanged(f),
            child: AnimatedContainer(
              duration: AfDurations.quick,
              curve: AfCurves.easeStandard,
              padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
              decoration: BoxDecoration(
                color: active ? AfColors.indigo600 : AfColors.surfaceRaised,
                borderRadius: AfRadii.borderPill,
              ),
              alignment: Alignment.center,
              child: Text(
                f.label,
                style: AfTypography.bodyMedium.copyWith(
                  color: active
                      ? AfColors.textOnPrimary
                      : AfColors.textSecondary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Parse a hex color string from the server, falling back to indigo on error.
Color _parseTint(String hex) {
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

class _ArtistIdleGrid extends ConsumerWidget {
  const _ArtistIdleGrid({required this.isLocal});
  final bool isLocal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = isLocal ? localArtistsProvider : allArtistsProvider;
    final async = ref.watch(provider);
    return async.when(
      loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
      error: (_, _) => const SliverToBoxAdapter(child: SizedBox.shrink()),
      data: (list) => SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
        sliver: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisExtent: 160,
            crossAxisSpacing: AfSpacing.s12,
            mainAxisSpacing: AfSpacing.s12,
          ),
          itemCount: list.length,
          itemBuilder: (context, i) {
            final a = list[i];
            return Tile(
              title: a.name,
              subtitle: a.statLine,
              variant: TileVariant.artist,
              imageUrl: a.imageUrl,
              size: double.infinity,
              onTap: () => context.push('/artist/${a.id}'),
            );
          },
        ),
      ),
    );
  }
}

class _GenreIdleGrid extends ConsumerWidget {
  const _GenreIdleGrid({required this.isLocal});
  final bool isLocal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = isLocal ? localGenresProvider : allGenresProvider;
    final async = ref.watch(provider);
    return async.when(
      loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
      error: (_, _) => const SliverToBoxAdapter(child: SizedBox.shrink()),
      data: (list) => SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
        sliver: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisExtent: 80,
            crossAxisSpacing: AfSpacing.s12,
            mainAxisSpacing: AfSpacing.s12,
          ),
          itemCount: list.length,
          itemBuilder: (context, i) {
            final g = list[i];
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
    );
  }
}

class _AlbumIdleGrid extends ConsumerWidget {
  const _AlbumIdleGrid({required this.isLocal});
  final bool isLocal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = isLocal ? localAlbumsProvider : allAlbumsProvider;
    final async = ref.watch(provider);
    return async.when(
      loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
      error: (_, _) => const SliverToBoxAdapter(child: SizedBox.shrink()),
      data: (list) => SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
        sliver: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisExtent: 220,
            crossAxisSpacing: AfSpacing.s16,
            mainAxisSpacing: AfSpacing.s16,
          ),
          itemCount: list.length,
          itemBuilder: (context, i) {
            final a = list[i];
            return Tile(
              title: a.name,
              subtitle: a.artistName,
              variant: TileVariant.album,
              imageUrl: a.imageUrl,
              size: double.infinity,
              onTap: () => context.push('/album/${a.id}'),
            );
          },
        ),
      ),
    );
  }
}

class _SearchResults extends ConsumerWidget {
  const _SearchResults({
    required this.tracks,
    required this.albums,
    required this.artists,
    required this.playlists,
    this.unbounded = false,
  });
  final List<AfTrack> tracks;
  final List<AfAlbum> albums;
  final List<AfArtist> artists;
  final List<AfPlaylist> playlists;

  /// When true, render every result of each type (no preview cap).
  /// Set when a single-type filter chip is active.
  final bool unbounded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeId = ref.watch(currentTrackProvider)?.id;
    final isBuffering = ref.watch(isBufferingProvider);
    final activeAccent = ref.watch(currentSpectralProvider).energy;

    return AfScrollbar(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AfSpacing.s16,
          0,
          AfSpacing.s16,
          AfSpacing.bottomInsetWithMiniAndNav,
        ),
        children: [
          if (tracks.isNotEmpty) ...[
            const SectionHeader(title: 'Tracks', uppercase: true),
            const SizedBox(height: AfSpacing.s8),
            for (var i = 0; i < tracks.length && (unbounded || i < 20); i++)
              Padding(
                padding: const EdgeInsets.only(bottom: AfSpacing.s4),
                child: TrackRow(
                  track: tracks[i],
                  isActive: tracks[i].id == activeId,
                  isBuffering: tracks[i].id == activeId && isBuffering,
                  activeAccent: activeAccent,
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
            const SectionHeader(title: 'Albums', uppercase: true),
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
            const SectionHeader(title: 'Artists', uppercase: true),
            const SizedBox(height: AfSpacing.s8),
            for (final a in unbounded ? artists : artists.take(10))
              ListTile(
                // Use Artwork widget (cached_network_image) instead of raw
                // NetworkImage to avoid repeated fetches and memory spikes.
                leading: Artwork(
                  url: a.imageUrl,
                  size: 44,
                  radius: AfRadii.borderPill,
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
            const SectionHeader(title: 'Playlists', uppercase: true),
            const SizedBox(height: AfSpacing.s8),
            for (final p in unbounded ? playlists : playlists.take(10))
              ListTile(
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    borderRadius: AfRadii.borderSm,
                    gradient: LinearGradient(
                      colors: [AfColors.indigo700, AfColors.indigo900],
                    ),
                  ),
                  child: const Icon(
                    Icons.playlist_play_rounded,
                    color: AfColors.indigo300,
                  ),
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
      ),
    );
  }
}
