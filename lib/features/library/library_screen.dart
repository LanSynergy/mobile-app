import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/audio/play_actions.dart';
import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/async_error_view.dart';
import '../../widgets/tile.dart';
import '../../widgets/track_context_menu.dart';
import '../../widgets/track_row.dart';
import '../../widgets/skeletons/library_skeleton.dart';
import '../playlist/import_m3u_dialog.dart';

enum LibrarySection { albums, artists, songs, playlists, genres, liked }

/// Sort options for library items.
enum LibrarySortOption {
  nameAsc('Name (A-Z)'),
  nameDesc('Name (Z-A)'),
  artistAsc('Artist (A-Z)'),
  artistDesc('Artist (Z-A)'),
  yearDesc('Year (Newest)'),
  yearAsc('Year (Oldest)');

  const LibrarySortOption(this.label);
  final String label;
}

/// Sections available in local mode (no server playlists, no liked — those are server concepts).
/// Smart playlists are accessible from the playlists tab.
const _localSections = [
  LibrarySection.albums,
  LibrarySection.artists,
  LibrarySection.songs,
  LibrarySection.playlists,
  LibrarySection.genres,
];

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({
    super.key,
    this.initialSection,
    this.simpleMode = false,
  });

  /// When set, the screen opens directly on this tab instead of Albums.
  /// Used by deep-links from Home (genre tiles → Genres, artists → Artists).
  final LibrarySection? initialSection;

  /// When true, hides header, sort, and pill — shows only the selected section.
  final bool simpleMode;

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  late LibrarySection _section;
  LibrarySortOption _sortOption = LibrarySortOption.nameAsc;

  @override
  void initState() {
    super.initState();
    _section = widget.initialSection ?? LibrarySection.albums;
  }

  /// Sort a list of albums.
  List<AfAlbum> _sortAlbums(List<AfAlbum> list) {
    final sorted = List<AfAlbum>.from(list);
    switch (_sortOption) {
      case LibrarySortOption.nameAsc:
        sorted.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        break;
      case LibrarySortOption.nameDesc:
        sorted.sort(
          (a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()),
        );
        break;
      case LibrarySortOption.artistAsc:
        sorted.sort(
          (a, b) =>
              a.artistName.toLowerCase().compareTo(b.artistName.toLowerCase()),
        );
        break;
      case LibrarySortOption.artistDesc:
        sorted.sort(
          (a, b) =>
              b.artistName.toLowerCase().compareTo(a.artistName.toLowerCase()),
        );
        break;
      case LibrarySortOption.yearDesc:
        sorted.sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
        break;
      case LibrarySortOption.yearAsc:
        sorted.sort((a, b) => (a.year ?? 0).compareTo(b.year ?? 0));
        break;
    }
    return sorted;
  }

  /// Sort a list of artists.
  List<AfArtist> _sortArtists(List<AfArtist> list) {
    final sorted = List<AfArtist>.from(list);
    switch (_sortOption) {
      case LibrarySortOption.nameAsc:
        sorted.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        break;
      case LibrarySortOption.nameDesc:
        sorted.sort(
          (a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()),
        );
        break;
      case LibrarySortOption.artistAsc:
      case LibrarySortOption.artistDesc:
        // Artists are already sorted by name, no secondary sort by artist
        break;
      case LibrarySortOption.yearDesc:
      case LibrarySortOption.yearAsc:
        // Artists don't have year
        break;
    }
    return sorted;
  }

  /// Sort a list of tracks.
  List<AfTrack> _sortTracks(List<AfTrack> list) {
    final sorted = List<AfTrack>.from(list);
    switch (_sortOption) {
      case LibrarySortOption.nameAsc:
        sorted.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
        break;
      case LibrarySortOption.nameDesc:
        sorted.sort(
          (a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()),
        );
        break;
      case LibrarySortOption.artistAsc:
        sorted.sort(
          (a, b) =>
              a.artistName.toLowerCase().compareTo(b.artistName.toLowerCase()),
        );
        break;
      case LibrarySortOption.artistDesc:
        sorted.sort(
          (a, b) =>
              b.artistName.toLowerCase().compareTo(a.artistName.toLowerCase()),
        );
        break;
      case LibrarySortOption.yearDesc:
      case LibrarySortOption.yearAsc:
        // Tracks don't have year in the same way
        break;
    }
    return sorted;
  }

  Future<void> _onRefresh() async {
    final isLocal = ref.read(appModeProvider) == AppMode.local;

    // Refresh paginated tracks
    await ref.read(tracksPaginationProvider.notifier).loadFirstPage();

    // Invalidate other section providers
    ref.invalidate(isLocal ? localAlbumsProvider : allAlbumsProvider);
    ref.invalidate(isLocal ? localArtistsProvider : allArtistsProvider);
    ref.invalidate(allPlaylistsProvider);
    ref.invalidate(isLocal ? localGenresProvider : allGenresProvider);
    if (!isLocal) ref.invalidate(favoriteTracksProvider);

    final providers = <Future<Object?>>[
      ref.read((isLocal ? localAlbumsProvider : allAlbumsProvider).future),
      ref.read((isLocal ? localArtistsProvider : allArtistsProvider).future),
      ref.read(allPlaylistsProvider.future),
      ref.read((isLocal ? localGenresProvider : allGenresProvider).future),
    ];
    if (!isLocal) {
      providers.add(ref.read(favoriteTracksProvider.future));
    }
    await Future.wait(providers).catchError((_) => <Object?>[]);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _onRefresh,
        color: AfColors.indigo300,
        backgroundColor: AfColors.surfaceBase,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.simpleMode)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AfSpacing.s16,
                  AfSpacing.s8,
                  AfSpacing.s16,
                  0,
                ),
                child: Text('Songs', style: AfTypography.titleLarge),
              ),
            if (widget.simpleMode)
              const SizedBox(height: AfSpacing.s12)
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AfSpacing.s16,
                  AfSpacing.s8,
                  AfSpacing.s16,
                  AfSpacing.s16,
                ),
                child: Row(
                  children: [
                    Text('Library', style: AfTypography.titleLarge),
                    const Spacer(),
                    if (_section == LibrarySection.playlists)
                      IconButton(
                        icon: const Icon(
                          LucideIcons.listPlus,
                          color: AfColors.indigo400,
                          size: 22,
                        ),
                        tooltip: 'Import M3U',
                        onPressed: () => ref
                            .read(importM3UActionProvider)
                            .import(context: context),
                      ),
                    PopupMenuButton<LibrarySortOption>(
                      icon: const Icon(
                        LucideIcons.arrowDownWideNarrow,
                        color: AfColors.textPrimary,
                        size: 22,
                      ),
                      tooltip: 'Sort',
                      initialValue: _sortOption,
                      onSelected: (option) {
                        setState(() => _sortOption = option);
                      },
                      itemBuilder: (context) => LibrarySortOption.values
                          .map(
                            (option) => PopupMenuItem<LibrarySortOption>(
                              value: option,
                              child: Row(
                                children: [
                                  if (_sortOption == option)
                                    const Icon(
                                      Icons.check,
                                      size: 18,
                                      color: AfColors.indigo400,
                                    )
                                  else
                                    const SizedBox(width: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    option.label,
                                    style: AfTypography.bodyMedium,
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
              ),
              _SegmentedPill(
                value: _section,
                onChanged: (v) => setState(() => _section = v),
              ),
              const SizedBox(height: AfSpacing.s16),
            ],
            Expanded(
              child: _SectionBody(
                section: _section,
                sortOption: _sortOption,
                sortAlbums: _sortAlbums,
                sortArtists: _sortArtists,
                sortTracks: _sortTracks,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SegmentedPill extends ConsumerWidget {
  const _SegmentedPill({required this.value, required this.onChanged});
  final LibrarySection value;
  final ValueChanged<LibrarySection> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(appModeProvider);
    final sections = mode == AppMode.local
        ? _localSections
        : LibrarySection.values;

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
        itemCount: sections.length,
        separatorBuilder: (context, index) =>
            const SizedBox(width: AfSpacing.s8),
        itemBuilder: (context, i) {
          final s = sections[i];
          final selected = s == value;
          return GestureDetector(
            onTap: () => onChanged(s),
            child: AnimatedContainer(
              duration: AfDurations.quick,
              curve: AfCurves.easeStandard,
              padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
              decoration: BoxDecoration(
                color: selected ? AfColors.indigo600 : AfColors.surfaceRaised,
                borderRadius: AfRadii.borderPill,
              ),
              alignment: Alignment.center,
              child: Text(
                _label(s),
                style: AfTypography.bodyMedium.copyWith(
                  color: selected
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

  String _label(LibrarySection s) => switch (s) {
    LibrarySection.albums => 'Albums',
    LibrarySection.artists => 'Artists',
    LibrarySection.songs => 'Songs',
    LibrarySection.playlists => 'Playlists',
    LibrarySection.genres => 'Genres',
    LibrarySection.liked => 'Liked',
  };
}

class _SectionBody extends ConsumerWidget {
  const _SectionBody({
    required this.section,
    required this.sortOption,
    this.sortAlbums,
    this.sortArtists,
    this.sortTracks,
  });
  final LibrarySection section;
  final LibrarySortOption sortOption;
  final List<AfAlbum> Function(List<AfAlbum>)? sortAlbums;
  final List<AfArtist> Function(List<AfArtist>)? sortArtists;
  final List<AfTrack> Function(List<AfTrack>)? sortTracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const padding = EdgeInsets.symmetric(horizontal: AfSpacing.s16);
    const songPadding = EdgeInsets.symmetric(horizontal: AfSpacing.s8);
    final mode = ref.watch(appModeProvider);
    final isLocal = mode == AppMode.local;
    final activeId = ref.watch(currentTrackProvider)?.id;
    final isBuffering = ref.watch(isBufferingProvider);
    final activeAccent = ref.watch(currentSpectralProvider).energy;

    switch (section) {
      case LibrarySection.albums:
        final albumsProvider = isLocal
            ? localAlbumsProvider
            : allAlbumsProvider;
        final albums = ref.watch(albumsProvider);
        return albums.when(
          data: (list) {
            final sorted = sortAlbums != null ? sortAlbums!(list) : list;
            return RepaintBoundary(
              child: GridView.builder(
                padding: padding.add(
                  const EdgeInsets.only(
                    bottom: AfSpacing.bottomInsetWithMiniAndNav,
                  ),
                ),
                itemCount: sorted.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisExtent: 220,
                  crossAxisSpacing: AfSpacing.s16,
                  mainAxisSpacing: AfSpacing.s16,
                ),
                itemBuilder: (context, i) {
                  final a = sorted[i];
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
              ),
            );
          },
          loading: () =>
              const LibrarySkeleton(mode: LibrarySkeletonMode.albums),
          error: (e, _) => AsyncErrorView(
            label: 'Couldn\u2019t load albums',
            error: e,
            onRetry: () => ref.invalidate(albumsProvider),
          ),
        );
      case LibrarySection.artists:
        final artistsProvider = isLocal
            ? localArtistsProvider
            : allArtistsProvider;
        final artists = ref.watch(artistsProvider);
        return artists.when(
          data: (list) {
            final sorted = sortArtists != null ? sortArtists!(list) : list;
            return RepaintBoundary(
              child: GridView.builder(
                padding: padding.add(
                  const EdgeInsets.only(
                    bottom: AfSpacing.bottomInsetWithMiniAndNav,
                  ),
                ),
                itemCount: sorted.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisExtent: 180,
                  crossAxisSpacing: AfSpacing.s12,
                  mainAxisSpacing: AfSpacing.s12,
                ),
                itemBuilder: (context, i) {
                  final a = sorted[i];
                  return Tile(
                    title: a.name,
                    subtitle: a.statLine,
                    variant: TileVariant.artist,
                    imageUrl: a.imageUrl,
                    size: double.infinity,
                    onTap: () => context.go('/library'),
                  );
                },
              ),
            );
          },
          loading: () =>
              const LibrarySkeleton(mode: LibrarySkeletonMode.artists),
          error: (e, _) => AsyncErrorView(
            label: 'Couldn\u2019t load artists',
            error: e,
            onRetry: () => ref.invalidate(artistsProvider),
          ),
        );
      case LibrarySection.songs:
        // Local mode: use the simple localTracksProvider (fast, SQL-backed)
        if (isLocal) {
          final tracks = ref.watch(localTracksProvider);
          return tracks.when(
            data: (list) {
              final sorted = sortTracks != null ? sortTracks!(list) : list;
              return RepaintBoundary(
                child: ListView.builder(
                  padding: songPadding.add(
                    const EdgeInsets.only(
                      bottom: AfSpacing.bottomInsetWithMiniAndNav,
                    ),
                  ),
                  itemCount: sorted.length,
                  itemBuilder: (context, i) {
                    final t = sorted[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: TrackRow(
                        track: t,
                        steelBackground: true,
                        isActive: t.id == activeId,
                        isBuffering: t.id == activeId && isBuffering,
                        activeAccent: activeAccent,
                        onTap: () =>
                            ref.read(playActionsProvider).playSingle(t),
                        onLongPress: () =>
                            showTrackContextMenu(context, ref, t),
                      ),
                    );
                  },
                ),
              );
            },
            loading: () =>
                const LibrarySkeleton(mode: LibrarySkeletonMode.songs),
            error: (e, _) => AsyncErrorView(
              label: 'Couldn\u2019t load songs',
              error: e,
              onRetry: () => ref.invalidate(localTracksProvider),
            ),
          );
        }

        // Server mode: paginated with infinite scroll
        final tracksState = ref.watch(tracksPaginationProvider);

        if (tracksState.error != null && tracksState.items.isEmpty) {
          return AsyncErrorView(
            label: 'Couldn\u2019t load songs',
            error: Exception(tracksState.error),
            onRetry: () =>
                ref.read(tracksPaginationProvider.notifier).loadFirstPage(),
          );
        }

        if (tracksState.items.isEmpty && tracksState.isLoadingMore) {
          return const Center(child: CircularProgressIndicator());
        }

        final sorted = sortTracks != null
            ? sortTracks!(tracksState.items)
            : tracksState.items;

        return RepaintBoundary(
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollEndNotification &&
                  notification.metrics.pixels >=
                      notification.metrics.maxScrollExtent - 200 &&
                  tracksState.hasMore &&
                  !tracksState.isLoadingMore) {
                ref.read(tracksPaginationProvider.notifier).loadNextPage();
              }
              return false;
            },
            child: ListView.separated(
              padding: songPadding.add(
                const EdgeInsets.only(
                  bottom: AfSpacing.bottomInsetWithMiniAndNav,
                ),
              ),
              itemCount: sorted.length + (tracksState.isLoadingMore ? 1 : 0),
              separatorBuilder: (context, index) =>
                  const SizedBox(height: AfSpacing.s4),
              itemBuilder: (context, i) {
                if (i >= sorted.length) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }
                final t = sorted[i];
                return TrackRow(
                  track: t,
                  steelBackground: true,
                  isActive: t.id == activeId,
                  isBuffering: t.id == activeId && isBuffering,
                  activeAccent: activeAccent,
                  onTap: () => ref.read(playActionsProvider).playSingle(t),
                  onLongPress: () => showTrackContextMenu(context, ref, t),
                );
              },
            ),
          ),
        );
      case LibrarySection.playlists:
        final playlists = ref.watch(allPlaylistsProvider);
        final smartPlaylists = ref.watch(smartPlaylistsProvider);
        final smartCount = smartPlaylists.maybeWhen(
          data: (list) => list.length,
          orElse: () => 0,
        );
        return playlists.when(
          data: (list) => RepaintBoundary(
            child: ListView.separated(
              padding: padding.add(
                const EdgeInsets.only(
                  bottom: AfSpacing.bottomInsetWithMiniAndNav,
                ),
              ),
              itemCount: list.length + 1, // +1 for smart playlists tile
              separatorBuilder: (context, index) =>
                  const SizedBox(height: AfSpacing.s8),
              itemBuilder: (context, i) {
                // First item: Smart Playlists entry
                if (i == 0) {
                  return ListTile(
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        borderRadius: AfRadii.borderSm,
                        color: AfColors.indigo900,
                      ),
                      child: const Icon(
                        Icons.auto_awesome_rounded,
                        color: AfColors.indigo300,
                      ),
                    ),
                    title: Text(
                      'Smart Playlists',
                      style: AfTypography.titleSmall,
                    ),
                    subtitle: Text(
                      '$smartCount playlists',
                      style: AfTypography.bodySmall.copyWith(
                        color: AfColors.textTertiary,
                      ),
                    ),
                    tileColor: AfColors.surfaceRaised,
                    shape: const RoundedRectangleBorder(
                      borderRadius: AfRadii.borderMd,
                    ),
                    onTap: () => context.push('/smart-playlists'),
                  );
                }
                final p = list[i - 1];
                return ListTile(
                  leading: Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      borderRadius: AfRadii.borderSm,
                      color: AfColors.indigo800,
                    ),
                    child: const Icon(
                      Icons.playlist_play_rounded,
                      color: AfColors.indigo300,
                    ),
                  ),
                  title: Text(p.name, style: AfTypography.titleSmall),
                  subtitle: Text(
                    p.trackCountLabel,
                    style: AfTypography.bodySmall.copyWith(
                      color: AfColors.textTertiary,
                    ),
                  ),
                  tileColor: AfColors.surfaceRaised,
                  shape: const RoundedRectangleBorder(
                    borderRadius: AfRadii.borderMd,
                  ),
                  onTap: () => context.push('/playlist/${p.id}'),
                );
              },
            ),
          ),
          loading: () =>
              const LibrarySkeleton(mode: LibrarySkeletonMode.playlists),
          error: (e, _) => AsyncErrorView(
            label: 'Couldn\u2019t load playlists',
            error: e,
            onRetry: () => ref.invalidate(allPlaylistsProvider),
          ),
        );
      case LibrarySection.genres:
        final genresProvider = isLocal
            ? localGenresProvider
            : allGenresProvider;
        final genresAsync = ref.watch(genresProvider);
        return genresAsync.when(
          data: (genres) => RepaintBoundary(
            child: GridView.builder(
              padding: padding.add(
                const EdgeInsets.only(
                  bottom: AfSpacing.bottomInsetWithMiniAndNav,
                ),
              ),
              itemCount: genres.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisExtent: 96,
                crossAxisSpacing: AfSpacing.s12,
                mainAxisSpacing: AfSpacing.s12,
              ),
              itemBuilder: (context, i) {
                final g = genres[i];
                final tint = Color(int.parse(g.tint.replaceFirst('#', '0xFF')));
                return GenreTile(
                  name: g.name,
                  tint: tint,
                  imageUrl: g.imageUrl,
                  width: double.infinity,
                  height: double.infinity,
                  onTap: () => context.go('/library'),
                );
              },
            ),
          ),
          loading: () =>
              const LibrarySkeleton(mode: LibrarySkeletonMode.genres),
          error: (e, _) => AsyncErrorView(
            label: 'Couldn\u2019t load genres',
            error: e,
            onRetry: () => ref.invalidate(genresProvider),
          ),
        );
      case LibrarySection.liked:
        final likedAsync = ref.watch(favoriteTracksProvider);
        return likedAsync.when(
          data: (list) => list.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.4,
                      child: Center(
                        child: Text(
                          'No liked songs yet.\nTap the heart on any track.',
                          textAlign: TextAlign.center,
                          style: AfTypography.bodyMedium.copyWith(
                            color: AfColors.textTertiary,
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : RepaintBoundary(
                  child: ListView.builder(
                    padding: songPadding.add(
                      const EdgeInsets.only(
                        bottom: AfSpacing.bottomInsetWithMiniAndNav,
                      ),
                    ),
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final t = list[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: TrackRow(
                          track: t,
                          steelBackground: true,
                          isActive: t.id == activeId,
                          isBuffering: t.id == activeId && isBuffering,
                          activeAccent: activeAccent,
                          onTap: () => ref
                              .read(playActionsProvider)
                              .playQueue(list, startIndex: i),
                          onLongPress: () =>
                              showTrackContextMenu(context, ref, t),
                        ),
                      );
                    },
                  ),
                ),
          loading: () => const LibrarySkeleton(mode: LibrarySkeletonMode.liked),
          error: (e, _) => AsyncErrorView(
            label: 'Couldn\u2019t load liked songs',
            error: e,
            onRetry: () => ref.invalidate(favoriteTracksProvider),
          ),
        );
    }
  }
}
