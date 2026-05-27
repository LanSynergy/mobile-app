import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:go_router/go_router.dart';

import '../../core/audio/play_actions.dart';
import '../../core/battery_opt.dart';
import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/async_error_view.dart';
import '../../widgets/hero_album_card.dart';
import '../../widgets/section_header.dart';
import '../../widgets/tile.dart';
import '../../widgets/track_context_menu.dart';
import '../../widgets/track_row.dart';
import '../../widgets/skeletons/home_skeleton.dart';
import '../library/songs_screen.dart' show SongsPill, songsPillProvider;

/// Mockup 04 — Home.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Request battery-optimization exemption on first visit.
    // Required for reliable auto-advance when the screen is off —
    // without this, Doze can freeze the Dart isolate between tracks
    // on Samsung, Xiaomi, and other aggressive OEMs.
    // The system shows its own dialog; we only fire it if not already exempt.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestBatteryExemptionIfNeeded();
    });
  }

  Future<void> _requestBatteryExemptionIfNeeded() async {
    final alreadyIgnoring = await BatteryOpt.isIgnoring();
    if (!alreadyIgnoring && mounted) {
      await BatteryOpt.requestIgnore();
    }
  }

  /// Pull-to-refresh handler. Invalidates every provider the Home
  /// screen reads, then awaits each one's next value so the spinner
  /// stays visible until the refetch actually completes.
  Future<void> _onRefresh() async {
    final isLocal = ref.read(appModeProvider) == AppMode.local;
    ref.invalidate(recentlyAddedAlbumsProvider);
    if (isLocal) {
      ref.invalidate(localTracksProvider);
      ref.invalidate(localArtistsProvider);
      ref.invalidate(localGenresProvider);
    } else {
      ref.invalidate(recentlyPlayedTracksProvider);
      ref.invalidate(allArtistsProvider);
      ref.invalidate(allGenresProvider);
    }
    await Future.wait<Object?>([
      ref.read(recentlyAddedAlbumsProvider.future),
      ref.read(
        (isLocal ? localTracksProvider : recentlyPlayedTracksProvider).future,
      ),
      ref.read((isLocal ? localArtistsProvider : allArtistsProvider).future),
      ref.read((isLocal ? localGenresProvider : allGenresProvider).future),
    ]).catchError((_) => const <Object?>[]);
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(appModeProvider);
    final isLocal = mode == AppMode.local;
    // Both modes route through the MusicBackend abstraction here.
    // LocalBackend.recentlyAddedAlbums sorts by MAX(last_modified)
    // so the hero card reflects newly-imported music. (The Library
    // screen still uses localAlbumsProvider for its alphabetical
    // "Albums" listing.)
    final albumsAsync = ref.watch(recentlyAddedAlbumsProvider);
    final recentTracksAsync = isLocal
        ? ref.watch(localTracksProvider)
        : ref.watch(recentlyPlayedTracksProvider);
    final artistsAsync = isLocal
        ? ref.watch(localArtistsProvider)
        : ref.watch(allArtistsProvider);
    final genresAsync = isLocal
        ? ref.watch(localGenresProvider)
        : ref.watch(allGenresProvider);

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _onRefresh,
        color: AfColors.indigo300,
        backgroundColor: AfColors.surfaceBase,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: ClampingScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AfSpacing.s16,
                  AfSpacing.s8,
                  AfSpacing.s16,
                  AfSpacing.s16,
                ),
                child: Row(
                  children: [
                    Text('Listen', style: AfTypography.titleLarge),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(LucideIcons.cast),
                      onPressed: () => context.push('/cast'),
                      tooltip: 'Output',
                    ),
                  ],
                ),
              ),
            ),

            // Hero album carousel.
            SliverToBoxAdapter(
              child: albumsAsync.when(
                data: (albums) => albums.isEmpty
                    ? const SizedBox.shrink()
                    : _HeroAlbumCarousel(albums: albums),
                loading: () => const HomeCarouselSkeleton(),
                error: (e, _) => AsyncErrorView.compact(
                  label: 'Couldn\u2019t load recent albums',
                  error: e,
                  height: 192,
                  onRetry: () => ref.invalidate(recentlyAddedAlbumsProvider),
                ),
              ),
            ),

            // Recently played.
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
                child: SectionHeader(
                  title: 'Recently played',
                  actionLabel: 'See more',
                  onActionTap: () => context.go('/library'),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: AfSpacing.s12)),
            SliverToBoxAdapter(
              child: recentTracksAsync.when(
                data: (tracks) => ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AfSpacing.s16,
                  ),
                  itemCount: tracks.take(5).length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: AfSpacing.s4),
                  itemBuilder: (context, i) {
                    final t = tracks[i];
                    return TrackRow(
                      track: t,
                      density: TrackRowDensity.generous,
                      onTap: () => ref.read(playActionsProvider).playSingle(t),
                      onLongPress: () => showTrackContextMenu(context, ref, t),
                    );
                  },
                ),
                loading: () => const HomeRecentSkeleton(),
                error: (e, _) => AsyncErrorView.compact(
                  label: 'Couldn\u2019t load recently played',
                  error: e,
                  height: 80,
                  onRetry: () => ref.invalidate(
                    isLocal
                        ? localTracksProvider
                        : recentlyPlayedTracksProvider,
                  ),
                ),
              ),
            ),

            const SliverToBoxAdapter(
              child: SizedBox(height: AfSpacing.sectionGap),
            ),

            // Artists.
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
                child: SectionHeader(
                  title: 'Artists',
                  actionLabel: 'See more',
                  onActionTap: () {
                    ref.read(songsPillProvider.notifier).state =
                        SongsPill.artists;
                    context.go('/library');
                  },
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: AfSpacing.s12)),
            SliverToBoxAdapter(
              child: artistsAsync.when(
                loading: () => const HomeArtistsSkeleton(),
                error: (e, _) => AsyncErrorView.compact(
                  label: 'Couldn\u2019t load artists',
                  error: e,
                  height: 172,
                  onRetry: () => ref.invalidate(
                    isLocal ? localArtistsProvider : allArtistsProvider,
                  ),
                ),
                data: (artists) => SizedBox(
                  height: 172,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AfSpacing.s16,
                    ),
                    itemCount: artists.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: AfSpacing.s12),
                    itemBuilder: (context, i) {
                      final a = artists[i];
                      return Tile(
                        title: a.name,
                        subtitle: '${a.albumCount} albums',
                        variant: TileVariant.artist,
                        imageUrl: a.imageUrl,
                        size: 100,
                        onTap: () {
                          ref.read(songsPillProvider.notifier).state =
                              SongsPill.artists;
                          context.go('/library');
                        },
                      );
                    },
                  ),
                ),
              ),
            ),

            const SliverToBoxAdapter(
              child: SizedBox(height: AfSpacing.sectionGap),
            ),

            // Genres.
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
                child: SectionHeader(
                  title: 'Genres',
                  actionLabel: 'See more',
                  onActionTap: () {
                    ref.read(songsPillProvider.notifier).state =
                        SongsPill.genres;
                    context.go('/library');
                  },
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: AfSpacing.s12)),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 96,
                child: genresAsync.when(
                  data: (genres) => ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AfSpacing.s16,
                    ),
                    itemCount: genres.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: AfSpacing.s12),
                    itemBuilder: (context, i) {
                      final g = genres[i];
                      return GenreTile(
                        name: g.name,
                        tint: _hex(g.tint),
                        imageUrl: g.imageUrl,
                        onTap: () {
                          ref.read(songsPillProvider.notifier).state =
                              SongsPill.genres;
                          context.go('/library');
                        },
                      );
                    },
                  ),
                  loading: () => const SizedBox.shrink(),
                  error: (e, _) => AsyncErrorView.compact(
                    label: 'Couldn\u2019t load genres',
                    error: e,
                    height: 96,
                    onRetry: () => ref.invalidate(
                      isLocal ? localGenresProvider : allGenresProvider,
                    ),
                  ),
                ),
              ),
            ),

            const SliverToBoxAdapter(
              child: SizedBox(height: AfSpacing.bottomInsetWithMiniAndNav),
            ),
          ],
        ),
      ),
    );
  }

  Color _hex(String hex) {
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

/// Swipeable carousel of hero album cards with a dot indicator.
///
/// Uses `viewportFraction: 0.92` so the next card peeks in from the
/// right edge — gives the user a clear affordance that the section is
/// swipeable without needing explicit "swipe" hints.
class _HeroAlbumCarousel extends ConsumerStatefulWidget {
  const _HeroAlbumCarousel({required this.albums});
  final List<AfAlbum> albums;

  @override
  ConsumerState<_HeroAlbumCarousel> createState() => _HeroAlbumCarouselState();
}

class _HeroAlbumCarouselState extends ConsumerState<_HeroAlbumCarousel> {
  int _currentPage = 0;
  final PageController _pageController = PageController(viewportFraction: 0.92);

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final albums = widget.albums.take(5).toList();
    if (albums.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        SizedBox(
          // Must match HeroAlbumCard's minHeight (192) so the PageView
          // allocates enough vertical space for two-line titles.
          height: 192,
          child: PageView.builder(
            controller: _pageController,
            itemCount: albums.length,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemBuilder: (context, i) {
              final album = albums[i];
              return Consumer(
                builder: (context, ref, _) {
                  return HeroAlbumCard(
                    album: album,
                    onTap: () => context.push('/album/${album.id}'),
                    onPlay: () async {
                      final tracks = ref.read(playActionsProvider);
                      final detail = await ref.read(
                        albumDetailProvider(album.id).future,
                      );
                      if (detail != null) {
                        await tracks.playAlbum(detail.tracks);
                      }
                    },
                  );
                },
              );
            },
          ),
        ),
        if (albums.length > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              albums.length,
              (i) => AnimatedContainer(
                duration: AfDurations.quick,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: _currentPage == i ? 16 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: _currentPage == i
                      ? AfColors.indigo400
                      : AfColors.surfaceMax,
                  borderRadius: AfRadii.borderPill,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
