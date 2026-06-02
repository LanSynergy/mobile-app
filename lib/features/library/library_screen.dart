import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/audio/play_actions.dart';
import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/af_scrollbar.dart';
import '../../widgets/artwork.dart';
import '../../widgets/async_error_view.dart';
import '../../widgets/press_scale.dart';
import '../../widgets/tile.dart';
import '../../widgets/track_context_menu.dart';
import '../../widgets/track_row.dart';
import '../../widgets/skeletons/library_skeleton.dart';

enum SongsPill { songs, artists, albums, genres }

extension on SongsPill {
  String get label => switch (this) {
    SongsPill.songs => 'Songs',
    SongsPill.artists => 'Artists',
    SongsPill.albums => 'Albums',
    SongsPill.genres => 'Genres',
  };
}

final songsPillProvider = StateProvider<SongsPill?>((ref) => null);

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  SongsPill _pill = SongsPill.songs;

  @override
  void initState() {
    super.initState();
    final pill = ref.read(songsPillProvider);
    if (pill != null && mounted) {
      _pill = pill;
      ref.read(songsPillProvider.notifier).state = null;
    }
  }

  void _openSearch(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CommandPaletteSearch(),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<SongsPill?>(songsPillProvider, (prev, next) {
      if (next != null && next != _pill && mounted) {
        setState(() {
          _pill = next;
          ref.read(songsPillProvider.notifier).state = null;
        });
      }
    });

    final mode = ref.watch(appModeProvider);
    final isLocal = mode == AppMode.local;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header row: gradient title + search icon ──
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AfSpacing.s16,
              AfSpacing.s8,
              AfSpacing.s16,
              AfSpacing.s12,
            ),
            child: Row(
              children: [
                Expanded(
                  child: ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [
                        AfColors.accentPrimary,
                        AfColors.accentSecondary,
                      ],
                    ).createShader(bounds),
                    child: Text(
                      'Library',
                      style: AfTypography.display.copyWith(
                        color: AfColors.textPrimary,
                      ),
                    ),
                  ),
                ),
                PressScale(
                  onTap: () => _openSearch(context),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: AfColors.surfaceRaised,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      LucideIcons.search,
                      color: AfColors.textSecondary,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Recently Added ──
          _RecentlyAddedSection(isLocal: isLocal),

          const SizedBox(height: AfSpacing.s12),

          // ── Pill Bar ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
            child: _PillBar(
              selected: _pill,
              onChanged: (v) => setState(() => _pill = v),
            ),
          ),
          const SizedBox(height: AfSpacing.s12),

          // ── Section Content ──
          Expanded(child: _PillContent(pill: _pill)),
        ],
      ),
    );
  }
}

/// Command Palette — full-screen overlay search
class _CommandPaletteSearch extends ConsumerStatefulWidget {
  const _CommandPaletteSearch();

  @override
  ConsumerState<_CommandPaletteSearch> createState() =>
      _CommandPaletteSearchState();
}

class _CommandPaletteSearchState extends ConsumerState<_CommandPaletteSearch> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(appModeProvider);
    final isLocal = mode == AppMode.local;

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AfColors.surfaceCanvas,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AfRadii.xl),
            ),
          ),
          child: Column(
            children: [
              // ── Handle + Close ──
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AfSpacing.s16,
                  AfSpacing.s8,
                  AfSpacing.s16,
                  0,
                ),
                child: Row(
                  children: [
                    // Handle bar
                    Expanded(
                      child: Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: const BoxDecoration(
                            color: AfColors.accentPrimary,
                            borderRadius: AfRadii.borderPill,
                          ),
                        ),
                      ),
                    ),
                    // Close button
                    IconButton(
                      icon: const Icon(
                        LucideIcons.x,
                        color: AfColors.textTertiary,
                        size: 20,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // ── Search Input ──
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AfSpacing.s16,
                  AfSpacing.s8,
                  AfSpacing.s16,
                  AfSpacing.s12,
                ),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  style: AfTypography.bodyLarge.copyWith(
                    color: AfColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search songs, artists, albums\u2026',
                    hintStyle: AfTypography.bodyLarge.copyWith(
                      color: AfColors.textDisabled,
                    ),
                    prefixIcon: const Padding(
                      padding: EdgeInsets.only(left: AfSpacing.s4),
                      child: Icon(
                        LucideIcons.search,
                        color: AfColors.textTertiary,
                        size: 20,
                      ),
                    ),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(
                              LucideIcons.x,
                              color: AfColors.textTertiary,
                              size: 18,
                            ),
                            onPressed: () {
                              _controller.clear();
                              setState(() => _query = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: AfColors.surfaceBase,
                    border: const OutlineInputBorder(
                      borderRadius: AfRadii.borderPill,
                      borderSide: BorderSide(color: AfColors.surfaceHigh),
                    ),
                    enabledBorder: const OutlineInputBorder(
                      borderRadius: AfRadii.borderPill,
                      borderSide: BorderSide(color: AfColors.surfaceHigh),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: AfRadii.borderPill,
                      borderSide: BorderSide(color: AfColors.accentPrimary),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AfSpacing.s16,
                      vertical: AfSpacing.s12,
                    ),
                  ),
                  onChanged: (v) =>
                      setState(() => _query = v.trim().toLowerCase()),
                ),
              ),

              // ── Results ──
              Expanded(
                child: _query.isEmpty
                    ? _RecentAndSuggestions(isLocal: isLocal)
                    : _LiveResults(query: _query, isLocal: isLocal),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Recent searches + suggestions when query is empty
class _RecentAndSuggestions extends ConsumerWidget {
  const _RecentAndSuggestions({required this.isLocal});
  final bool isLocal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albumsAsync = ref.watch(
      isLocal ? localAlbumsProvider : allAlbumsProvider,
    );
    final genresAsync = ref.watch(
      isLocal ? localGenresProvider : allGenresProvider,
    );

    return AfScrollbar(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
        children: [
          // Quick suggestions
          Text(
            'QUICK PICKS',
            style: AfTypography.label.copyWith(color: AfColors.textTertiary),
          ),
          const SizedBox(height: AfSpacing.s12),
          albumsAsync.when(
            data: (list) {
              final recent = list.take(6).toList();
              if (recent.isEmpty) return const SizedBox.shrink();
              return Column(
                children: recent.map((a) {
                  return PressScale(
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/album/${a.id}');
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: AfSpacing.s4),
                      child: Row(
                        children: [
                          Artwork(
                            url: a.imageUrl,
                            size: 44,
                            radius: AfRadii.borderSm,
                          ),
                          const SizedBox(width: AfSpacing.s12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  a.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AfTypography.bodyMedium.copyWith(
                                    color: AfColors.textPrimary,
                                  ),
                                ),
                                Text(
                                  a.artistName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AfTypography.bodySmall.copyWith(
                                    color: AfColors.textTertiary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            LucideIcons.arrowUpLeft,
                            color: AfColors.textDisabled,
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(AfSpacing.s32),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            error: (_, _) => const SizedBox.shrink(),
          ),

          const SizedBox(height: AfSpacing.s24),

          // Genre chips
          Text(
            'GENRES',
            style: AfTypography.label.copyWith(color: AfColors.textTertiary),
          ),
          const SizedBox(height: AfSpacing.s12),
          genresAsync.when(
            data: (list) {
              if (list.isEmpty) return const SizedBox.shrink();
              return Wrap(
                spacing: AfSpacing.s8,
                runSpacing: AfSpacing.s8,
                children: list.take(8).map((g) {
                  final tint = _parseGenreTint(g.tint);
                  return PressScale(
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/genre/${g.name}');
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AfSpacing.s16,
                        vertical: AfSpacing.s8,
                      ),
                      decoration: BoxDecoration(
                        color: tint.withValues(alpha: 0.25),
                        borderRadius: AfRadii.borderPill,
                      ),
                      child: Text(
                        g.name,
                        style: AfTypography.bodySmall.copyWith(
                          color: AfColors.textOnPrimary,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

/// Live search results across all sections
class _LiveResults extends ConsumerWidget {
  const _LiveResults({required this.query, required this.isLocal});
  final String query;
  final bool isLocal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeId = ref.watch(currentTrackProvider)?.id;
    final isBuffering = ref.watch(isBufferingProvider);
    final accent = ref.watch(currentSpectralProvider).energy;

    final albumsAsync = ref.watch(
      isLocal ? localAlbumsProvider : allAlbumsProvider,
    );
    final artistsAsync = ref.watch(
      isLocal ? localArtistsProvider : allArtistsProvider,
    );

    return AfScrollbar(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
        children: [
          // Albums
          albumsAsync.when(
            data: (list) {
              final filtered = list
                  .where(
                    (a) =>
                        a.name.toLowerCase().contains(query) ||
                        a.artistName.toLowerCase().contains(query),
                  )
                  .take(4)
                  .toList();
              if (filtered.isEmpty) return const SizedBox.shrink();
              return _ResultSection(
                title: 'Albums',
                child: Column(
                  children: filtered.map((a) {
                    return PressScale(
                      onTap: () {
                        Navigator.pop(context);
                        context.push('/album/${a.id}');
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: AfSpacing.s4),
                        child: Row(
                          children: [
                            Artwork(
                              url: a.imageUrl,
                              size: 44,
                              radius: AfRadii.borderSm,
                            ),
                            const SizedBox(width: AfSpacing.s12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    a.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AfTypography.bodyMedium.copyWith(
                                      color: AfColors.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    a.artistName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AfTypography.bodySmall.copyWith(
                                      color: AfColors.textTertiary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),

          // Artists
          artistsAsync.when(
            data: (list) {
              final filtered = list
                  .where((a) => a.name.toLowerCase().contains(query))
                  .take(4)
                  .toList();
              if (filtered.isEmpty) return const SizedBox.shrink();
              return _ResultSection(
                title: 'Artists',
                child: Column(
                  children: filtered.map((a) {
                    return PressScale(
                      onTap: () {
                        Navigator.pop(context);
                        context.push('/artist/${a.id}');
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: AfSpacing.s4),
                        child: Row(
                          children: [
                            Artwork(
                              url: a.imageUrl,
                              size: 44,
                              radius: BorderRadius.circular(22),
                            ),
                            const SizedBox(width: AfSpacing.s12),
                            Expanded(
                              child: Text(
                                a.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AfTypography.bodyMedium.copyWith(
                                  color: AfColors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),

          // Songs
          Builder(
            builder: (context) {
              if (isLocal) {
                final tracks = ref.watch(localTracksProvider);
                return tracks.when(
                  data: (list) {
                    final filtered = list
                        .where(
                          (t) =>
                              t.title.toLowerCase().contains(query) ||
                              t.artistName.toLowerCase().contains(query),
                        )
                        .take(10)
                        .toList();
                    if (filtered.isEmpty) return const SizedBox.shrink();
                    return _buildTrackResults(
                      filtered,
                      activeId,
                      isBuffering,
                      accent,
                      ref,
                      context,
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                );
              } else {
                final state = ref.watch(tracksPaginationProvider);
                final filtered = state.items
                    .where(
                      (t) =>
                          t.title.toLowerCase().contains(query) ||
                          t.artistName.toLowerCase().contains(query),
                    )
                    .take(10)
                    .toList();
                if (filtered.isEmpty) return const SizedBox.shrink();
                return _buildTrackResults(
                  filtered,
                  activeId,
                  isBuffering,
                  accent,
                  ref,
                  context,
                );
              }
            },
          ),
        ],
      ),
    );
  }

  static Widget _buildTrackResults(
    List<AfTrack> filtered,
    String? activeId,
    bool isBuffering,
    Color accent,
    WidgetRef ref,
    BuildContext context,
  ) {
    return _ResultSection(
      title: 'Songs',
      child: Column(
        children: filtered.map((t) {
          return TrackRow(
            track: t,
            isActive: t.id == activeId,
            isBuffering: t.id == activeId && isBuffering,
            activeAccent: accent,
            onTap: () {
              Navigator.pop(context);
              ref.read(playActionsProvider).playSmartQueue(t, filtered);
            },
            onLongPress: () => showTrackContextMenu(context, ref, t),
          );
        }).toList(),
      ),
    );
  }
}

class _ResultSection extends StatelessWidget {
  const _ResultSection({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AfSpacing.s20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: AfTypography.label.copyWith(color: AfColors.textTertiary),
          ),
          const SizedBox(height: AfSpacing.s8),
          child,
        ],
      ),
    );
  }
}

// ── Recently Added Section ──

class _RecentlyAddedSection extends ConsumerWidget {
  const _RecentlyAddedSection({required this.isLocal});
  final bool isLocal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = isLocal ? localAlbumsProvider : allAlbumsProvider;
    final albums = ref.watch(provider);

    return albums.when(
      data: (list) {
        final recent = list.take(10).toList();
        if (recent.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
              child: Text(
                'RECENTLY ADDED',
                style: AfTypography.label.copyWith(
                  color: AfColors.textTertiary,
                ),
              ),
            ),
            const SizedBox(height: AfSpacing.s12),
            SizedBox(
              height: 180,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
                itemCount: recent.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: AfSpacing.s12),
                itemBuilder: (context, i) {
                  final a = recent[i];
                  return PressScale(
                    onTap: () => context.push('/album/${a.id}'),
                    child: SizedBox(
                      width: 140,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Artwork(
                            url: a.imageUrl,
                            size: 140,
                            radius: AfRadii.borderMd,
                          ),
                          const SizedBox(height: AfSpacing.s8),
                          Text(
                            a.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AfTypography.bodyMedium.copyWith(
                              color: AfColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            a.artistName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AfTypography.bodySmall.copyWith(
                              color: AfColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
      loading: () => const SizedBox(height: 180),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

// ── Pill Bar (animated with easeOutBack) ──

class _PillBar extends StatefulWidget {
  const _PillBar({required this.selected, required this.onChanged});
  final SongsPill selected;
  final ValueChanged<SongsPill> onChanged;

  @override
  State<_PillBar> createState() => _PillBarState();
}

class _PillBarState extends State<_PillBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  int _fromIndex = 0;
  int _toIndex = 0;

  @override
  void initState() {
    super.initState();
    _toIndex = SongsPill.values.indexOf(widget.selected);
    _fromIndex = _toIndex;
    _ctrl = AnimationController(vsync: this, duration: AfDurations.long)
      ..value = 1.0;
  }

  @override
  void didUpdateWidget(_PillBar old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected) {
      _fromIndex = _toIndex;
      _toIndex = SongsPill.values.indexOf(widget.selected);
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = SongsPill.values.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final segWidth = constraints.maxWidth / count;

        return ClipRRect(
          borderRadius: AfRadii.borderPill,
          child: DecoratedBox(
            decoration: const BoxDecoration(color: AfColors.surfaceRaised),
            child: SizedBox(
              height: 44,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedBuilder(
                    animation: _ctrl,
                    builder: (context, _) {
                      final curved = Curves.easeOutBack.transform(_ctrl.value);
                      final damped = curved > 1.0
                          ? 1.0 + (curved - 1.0) * 0.15
                          : curved;
                      final idx = _fromIndex + (_toIndex - _fromIndex) * damped;
                      return Positioned(
                        left: 4 + segWidth * idx,
                        top: 4,
                        bottom: 4,
                        width: segWidth - 8,
                        child: const IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: AfColors.indigo600,
                              borderRadius: AfRadii.borderPill,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  Row(
                    children: List.generate(count, (i) {
                      final pill = SongsPill.values[i];
                      return Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => widget.onChanged(pill),
                          child: Container(
                            height: 44,
                            alignment: Alignment.center,
                            child: Text(
                              pill.label,
                              style: AfTypography.bodyMedium.copyWith(
                                color: pill == widget.selected
                                    ? AfColors.textOnPrimary
                                    : AfColors.textSecondary,
                                fontWeight: pill == widget.selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PillContent extends ConsumerWidget {
  const _PillContent({required this.pill});
  final SongsPill pill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(appModeProvider);
    final isLocal = mode == AppMode.local;

    switch (pill) {
      case SongsPill.songs:
        return _SongsList(isLocal: isLocal);
      case SongsPill.artists:
        return _ArtistsGrid(isLocal: isLocal);
      case SongsPill.albums:
        return _AlbumsGrid(isLocal: isLocal);
      case SongsPill.genres:
        return _GenresGrid(isLocal: isLocal);
    }
  }
}

/// ─────────────────────────────────────────────────────────────────────────────
///
/// Songs list — local mode (SQL) or server mode (paginated).
///
/// ─────────────────────────────────────────────────────────────────────────────
class _SongsList extends ConsumerWidget {
  const _SongsList({required this.isLocal});
  final bool isLocal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeId = ref.watch(currentTrackProvider)?.id;

    if (isLocal) {
      final tracks = ref.watch(localTracksProvider);
      return tracks.when(
        data: (list) => _buildList(list, activeId, ref),
        loading: () => const LibrarySkeleton(mode: LibrarySkeletonMode.songs),
        error: (e, _) => AsyncErrorView(
          label: 'Couldn\u2019t load songs',
          error: e,
          onRetry: () => ref.invalidate(localTracksProvider),
        ),
      );
    }

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

    return _buildList(tracksState.items, activeId, ref);
  }

  Widget _buildList(List<AfTrack> tracks, String? activeId, WidgetRef ref) {
    const padding = EdgeInsets.symmetric(horizontal: AfSpacing.s8);

    if (tracks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AfColors.surfaceRaised,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                LucideIcons.music,
                size: 40,
                color: AfColors.textTertiary,
              ),
            ),
            const SizedBox(height: AfSpacing.s12),
            Text('No songs yet', style: AfTypography.titleSmall),
            const SizedBox(height: AfSpacing.s8),
            Text(
              'Songs from your library will appear here',
              style: AfTypography.bodySmall.copyWith(
                color: AfColors.textTertiary,
              ),
            ),
          ],
        ),
      );
    }

    return RepaintBoundary(
      child: AfScrollbar(
        child: ListView.builder(
          padding: padding.add(
            const EdgeInsets.only(bottom: AfSpacing.bottomInsetWithMiniAndNav),
          ),
          itemCount: tracks.length,
          itemBuilder: (context, i) {
            final t = tracks[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: TrackRow(
                track: t,
                isActive: t.id == activeId,
                isBuffering: t.id == activeId && ref.watch(isBufferingProvider),
                activeAccent: ref.watch(currentSpectralProvider).energy,
                onTap: () =>
                    ref.read(playActionsProvider).playSmartQueue(t, tracks),
                onLongPress: () => showTrackContextMenu(context, ref, t),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────────
///
/// Artists grid — local or server.
///
/// ─────────────────────────────────────────────────────────────────────────────
class _ArtistsGrid extends ConsumerWidget {
  const _ArtistsGrid({required this.isLocal});
  final bool isLocal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = isLocal ? localArtistsProvider : allArtistsProvider;
    final async = ref.watch(provider);
    return async.when(
      data: (list) {
        if (list.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    color: AfColors.surfaceRaised,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    LucideIcons.users,
                    size: 40,
                    color: AfColors.textTertiary,
                  ),
                ),
                const SizedBox(height: AfSpacing.s12),
                Text('No artists found', style: AfTypography.titleSmall),
                const SizedBox(height: AfSpacing.s8),
                Text(
                  'Artists from your library will appear here',
                  style: AfTypography.bodySmall.copyWith(
                    color: AfColors.textTertiary,
                  ),
                ),
              ],
            ),
          );
        }
        const padding = EdgeInsets.symmetric(horizontal: AfSpacing.s16);
        return RepaintBoundary(
          child: GridView.builder(
            padding: padding.add(
              const EdgeInsets.only(
                bottom: AfSpacing.bottomInsetWithMiniAndNav,
              ),
            ),
            itemCount: list.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisExtent: 180,
              crossAxisSpacing: AfSpacing.s12,
              mainAxisSpacing: AfSpacing.s12,
            ),
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
        );
      },
      loading: () => const LibrarySkeleton(mode: LibrarySkeletonMode.artists),
      error: (e, _) => AsyncErrorView(
        label: 'Couldn\u2019t load artists',
        error: e,
        onRetry: () => ref.invalidate(provider),
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────────
///
/// Albums grid — local or server.
///
/// ─────────────────────────────────────────────────────────────────────────────
class _AlbumsGrid extends ConsumerWidget {
  const _AlbumsGrid({required this.isLocal});
  final bool isLocal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = isLocal ? localAlbumsProvider : allAlbumsProvider;
    final async = ref.watch(provider);
    return async.when(
      data: (list) {
        if (list.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    color: AfColors.surfaceRaised,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    LucideIcons.disc,
                    size: 40,
                    color: AfColors.textTertiary,
                  ),
                ),
                const SizedBox(height: AfSpacing.s12),
                Text('No albums found', style: AfTypography.titleSmall),
                const SizedBox(height: AfSpacing.s8),
                Text(
                  'Albums from your library will appear here',
                  style: AfTypography.bodySmall.copyWith(
                    color: AfColors.textTertiary,
                  ),
                ),
              ],
            ),
          );
        }
        const padding = EdgeInsets.symmetric(horizontal: AfSpacing.s16);
        return RepaintBoundary(
          child: GridView.builder(
            padding: padding.add(
              const EdgeInsets.only(
                bottom: AfSpacing.bottomInsetWithMiniAndNav,
              ),
            ),
            itemCount: list.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisExtent: 220,
              crossAxisSpacing: AfSpacing.s16,
              mainAxisSpacing: AfSpacing.s16,
            ),
            itemBuilder: (context, i) {
              final a = list[i];
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
      loading: () => const LibrarySkeleton(mode: LibrarySkeletonMode.albums),
      error: (e, _) => AsyncErrorView(
        label: 'Couldn\u2019t load albums',
        error: e,
        onRetry: () => ref.invalidate(provider),
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────────
///
/// Genres grid — local or server.
///
/// ─────────────────────────────────────────────────────────────────────────────
class _GenresGrid extends ConsumerWidget {
  const _GenresGrid({required this.isLocal});
  final bool isLocal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = isLocal ? localGenresProvider : allGenresProvider;
    final async = ref.watch(provider);
    return async.when(
      data: (list) {
        if (list.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    color: AfColors.surfaceRaised,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    LucideIcons.music2,
                    size: 40,
                    color: AfColors.textTertiary,
                  ),
                ),
                const SizedBox(height: AfSpacing.s12),
                Text('No genres found', style: AfTypography.titleSmall),
                const SizedBox(height: AfSpacing.s8),
                Text(
                  'Genres from your library will appear here',
                  style: AfTypography.bodySmall.copyWith(
                    color: AfColors.textTertiary,
                  ),
                ),
              ],
            ),
          );
        }
        const padding = EdgeInsets.symmetric(horizontal: AfSpacing.s16);
        return RepaintBoundary(
          child: GridView.builder(
            padding: padding.add(
              const EdgeInsets.only(
                bottom: AfSpacing.bottomInsetWithMiniAndNav,
              ),
            ),
            itemCount: list.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisExtent: 96,
              crossAxisSpacing: AfSpacing.s12,
              mainAxisSpacing: AfSpacing.s12,
            ),
            itemBuilder: (context, i) {
              final g = list[i];
              final tint = _parseGenreTint(g.tint);
              return GenreTile(
                name: g.name,
                tint: tint,
                imageUrl: g.imageUrl,
                width: double.infinity,
                height: double.infinity,
                onTap: () => context.push('/genre/${g.name}'),
              );
            },
          ),
        );
      },
      loading: () => const LibrarySkeleton(mode: LibrarySkeletonMode.genres),
      error: (e, _) => AsyncErrorView(
        label: 'Couldn\u2019t load genres',
        error: e,
        onRetry: () => ref.invalidate(provider),
      ),
    );
  }
}

/// Parse a hex color string from the server, falling back to indigo on error.
Color _parseGenreTint(String hex) {
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
