import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:go_router/go_router.dart';

import '../../core/audio/play_actions.dart';
import '../../core/battery_opt.dart';
import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/artwork.dart';
import '../../widgets/async_error_view.dart';
import '../../widgets/press_scale.dart';
import '../../widgets/section_header.dart';
import '../../widgets/stagger_reveal.dart';
import '../../widgets/tile.dart';
import '../../widgets/track_context_menu.dart';
import '../../widgets/skeletons/home_skeleton.dart';
import '../library/library_screen.dart' show SongsPill, songsPillProvider;

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
    ref.invalidate(lostMemoriesProvider);
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
      ref.read(lostMemoriesProvider.future),
      ref.read(
        (isLocal ? localTracksProvider : recentlyPlayedTracksProvider).future,
      ),
      ref.read((isLocal ? localArtistsProvider : allArtistsProvider).future),
      ref.read((isLocal ? localGenresProvider : allGenresProvider).future),
    ]).catchError((_) => const <Object?>[]);
  }

  @override
  Widget build(BuildContext context) {
    final isLocal = ref.watch(appModeProvider) == AppMode.local;
    final albumsAsync = ref.watch(recentlyAddedAlbumsProvider);

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
                  AfSpacing.s32,
                ),
                child: Row(
                  children: [
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [AfColors.indigo300, AfColors.indigo500],
                      ).createShader(bounds),
                      child: Text(
                        'Listen',
                        style: AfTypography.display.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const Spacer(),
                    _GlassCastButton(onTap: () => context.push('/cast')),
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
                  height: 240,
                  onRetry: () => ref.invalidate(recentlyAddedAlbumsProvider),
                ),
              ),
            ),

            _RecentTracksSection(isLocal: isLocal),

            const _LostMemoriesSection(),

            const SliverToBoxAdapter(
              child: SizedBox(height: AfSpacing.sectionGap),
            ),

            _ArtistsSection(isLocal: isLocal),

            const SliverToBoxAdapter(
              child: SizedBox(height: AfSpacing.sectionGap),
            ),

            _GenresSection(isLocal: isLocal),

            const SliverToBoxAdapter(
              child: SizedBox(height: AfSpacing.bottomInsetWithMiniAndNav),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Extracted section widgets
// ---------------------------------------------------------------------------

/// Top-5 recently played tracks with glass-morphism cards.
class _RecentTracksSection extends ConsumerWidget {
  const _RecentTracksSection({required this.isLocal});
  final bool isLocal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracksAsync = isLocal
        ? ref.watch(localTracksProvider)
        : ref.watch(recentlyPlayedTracksProvider);
    return SliverList(
      delegate: SliverChildListDelegate([
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
          child: SectionHeader(
            title: 'Recently played',
            actionLabel: 'See more',
            onActionTap: () => context.go('/library'),
          ),
        ),
        const SizedBox(height: AfSpacing.s12),
        tracksAsync.when(
          data: (tracks) => StaggerReveal(
            children: [
              for (final t in tracks.take(5))
                _GlassTrackRow(
                  track: t,
                  onTap: () => ref.read(playActionsProvider).playSingle(t),
                  onLongPress: () => showTrackContextMenu(context, ref, t),
                ),
            ],
          ),
          loading: () => const HomeRecentSkeleton(),
          error: (e, _) => AsyncErrorView.compact(
            label: 'Couldn\'t load recently played',
            error: e,
            height: 80,
            onRetry: () => ref.invalidate(
              isLocal ? localTracksProvider : recentlyPlayedTracksProvider,
            ),
          ),
        ),
      ]),
    );
  }
}

/// Glass-morphism track row — translucent background with subtle border.
class _GlassTrackRow extends StatelessWidget {
  const _GlassTrackRow({
    required this.track,
    required this.onTap,
    required this.onLongPress,
  });
  final AfTrack track;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      ensureHitTarget: true,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.symmetric(
          horizontal: AfSpacing.s16,
          vertical: AfSpacing.s2,
        ),
        padding: const EdgeInsets.all(AfSpacing.s12),
        decoration: BoxDecoration(
          borderRadius: AfRadii.borderMd,
          gradient: LinearGradient(
            colors: [
              Colors.white.withValues(alpha: 0.04),
              Colors.white.withValues(alpha: 0.02),
            ],
          ),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.06),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Artwork(
              url: track.imageUrl,
              size: 48,
              radius: BorderRadius.circular(AfRadii.sm),
            ),
            const SizedBox(width: AfSpacing.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AfTypography.bodyMedium.copyWith(
                      color: AfColors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: AfSpacing.s4),
                  Text(
                    track.artistName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AfTypography.bodySmall.copyWith(
                      color: AfColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              LucideIcons.heart,
              size: 16,
              color: track.isFavorite
                  ? AfColors.indigo400
                  : AfColors.surfaceMax,
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal scroll of recently played-but-old tracks (lost memories).
class _LostMemoriesSection extends ConsumerWidget {
  const _LostMemoriesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracksAsync = ref.watch(lostMemoriesProvider);
    return tracksAsync.when(
      data: (tracks) {
        if (tracks.isEmpty) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }
        return SliverList(
          delegate: SliverChildListDelegate([
            const SizedBox(height: AfSpacing.sectionGap),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
              child: SectionHeader(
                title: 'Lost memories',
                actionLabel: 'Play all',
                onActionTap: () =>
                    ref.read(playActionsProvider).playQueue(tracks),
              ),
            ),
            const SizedBox(height: AfSpacing.s12),
            SizedBox(
              height: 172,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
                itemCount: tracks.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(width: AfSpacing.s12),
                itemBuilder: (context, i) {
                  final t = tracks[i];
                  return Tile(
                    title: t.title,
                    subtitle: t.artistName,
                    variant: TileVariant.album,
                    imageUrl: t.imageUrl,
                    size: 100,
                    onTap: () => ref.read(playActionsProvider).playSingle(t),
                    onLongPress: () => showTrackContextMenu(context, ref, t),
                  );
                },
              ),
            ),
          ]),
        );
      },
      loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
      error: (e, _) => const SliverToBoxAdapter(child: SizedBox.shrink()),
    );
  }
}

/// Horizontal scroll of artists with radial glow backdrop.
class _ArtistsSection extends ConsumerWidget {
  const _ArtistsSection({required this.isLocal});
  final bool isLocal;

  // Indigo scale accent colors for each artist ring
  static const _accents = [
    AfColors.indigo400,
    AfColors.indigo300,
    AfColors.indigo500,
    AfColors.indigo600,
    AfColors.indigo700,
    AfColors.indigo200,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artistsAsync = isLocal
        ? ref.watch(localArtistsProvider)
        : ref.watch(allArtistsProvider);
    return SliverList(
      delegate: SliverChildListDelegate([
        const SizedBox(height: AfSpacing.sectionGap),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
          child: SectionHeader(
            title: 'Artists',
            actionLabel: 'See more',
            onActionTap: () {
              ref.read(songsPillProvider.notifier).state = SongsPill.artists;
              context.go('/library');
            },
          ),
        ),
        const SizedBox(height: AfSpacing.s12),
        artistsAsync.when(
          loading: () => const HomeArtistsSkeleton(),
          error: (e, _) => AsyncErrorView.compact(
            label: 'Couldn\'t load artists',
            error: e,
            height: 180,
            onRetry: () => ref.invalidate(
              isLocal ? localArtistsProvider : allArtistsProvider,
            ),
          ),
          data: (artists) => SizedBox(
            height: 180,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
              itemCount: artists.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(width: AfSpacing.s12),
              itemBuilder: (context, i) {
                final a = artists[i];
                final accent = _accents[i % _accents.length];
                return PressScale(
                  ensureHitTarget: false,
                  onTap: () {
                    ref.read(songsPillProvider.notifier).state =
                        SongsPill.artists;
                    context.go('/library');
                  },
                  child: SizedBox(
                    width: 108,
                    child: Column(
                      children: [
                        // Artwork with radial glow behind it
                        SizedBox(
                          width: 108,
                          height: 108,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Glow
                              Positioned(
                                child: Container(
                                  width: 100,
                                  height: 100,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: RadialGradient(
                                      colors: [
                                        accent.withValues(alpha: 0.2),
                                        accent.withValues(alpha: 0.0),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              // Artwork
                              Artwork(
                                url: a.imageUrl,
                                size: 88,
                                radius: BorderRadius.circular(44),
                              ),
                              // Ring
                              Positioned(
                                child: Container(
                                  width: 96,
                                  height: 96,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: accent.withValues(alpha: 0.2),
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AfSpacing.s8),
                        Text(
                          a.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: AfTypography.bodySmall.copyWith(
                            color: AfColors.textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ]),
    );
  }
}

/// Horizontal scroll of large genre cards with gradient overlay.
class _GenresSection extends ConsumerWidget {
  const _GenresSection({required this.isLocal});
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
            data: (genres) => ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
              itemCount: genres.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(width: AfSpacing.s12),
              itemBuilder: (context, i) {
                final g = genres[i];
                final tint = _hex(g.tint);
                return PressScale(
                  ensureHitTarget: false,
                  onTap: () {
                    ref.read(songsPillProvider.notifier).state =
                        SongsPill.genres;
                    context.go('/library');
                  },
                  child: Container(
                    width: 140,
                    height: 100,
                    decoration: BoxDecoration(
                      borderRadius: AfRadii.borderLg,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          tint.withValues(alpha: 0.3),
                          tint.withValues(alpha: 0.1),
                        ],
                      ),
                      border: Border.all(
                        color: tint.withValues(alpha: 0.2),
                        width: 1,
                      ),
                    ),
                    child: Stack(
                      children: [
                        // Artwork background
                        if (g.imageUrl != null)
                          Positioned.fill(
                            child: ClipRRect(
                              borderRadius: AfRadii.borderLg,
                              child: Artwork(
                                url: g.imageUrl,
                                size: 140,
                                radius: BorderRadius.zero,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        // Gradient overlay
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: AfRadii.borderLg,
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  tint.withValues(alpha: 0.3),
                                  AfColors.surfaceCanvas.withValues(
                                    alpha: 0.85,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Label
                        Positioned(
                          left: AfSpacing.s12,
                          bottom: AfSpacing.s12,
                          child: Text(
                            g.name,
                            style: AfTypography.titleSmall.copyWith(
                              color: AfColors.textOnPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            loading: () => const SizedBox.shrink(),
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

/// Swipeable carousel of hero album cards with a dot indicator.
class _HeroAlbumCarousel extends ConsumerStatefulWidget {
  const _HeroAlbumCarousel({required this.albums});
  final List<AfAlbum> albums;

  @override
  ConsumerState<_HeroAlbumCarousel> createState() => _HeroAlbumCarouselState();
}

class _HeroAlbumCarouselState extends ConsumerState<_HeroAlbumCarousel> {
  int _currentPage = 0;
  final PageController _pageController = PageController(viewportFraction: 1.0);

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final albums = widget.albums.take(5).toList();
    if (albums.isEmpty) return const SizedBox.shrink();

    return StaggerReveal(
      children: [
        Column(
          children: [
            SizedBox(
              height: 240,
              child: PageView.builder(
                controller: _pageController,
                itemCount: albums.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (context, i) {
                  final album = albums[i];
                  return Consumer(
                    builder: (context, ref, _) {
                      return PressScale(
                        ensureHitTarget: false,
                        onTap: () => context.push('/album/${album.id}'),
                        child: Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: AfSpacing.s16,
                          ),
                          decoration: const BoxDecoration(
                            borderRadius: AfRadii.borderXl,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              // Artwork
                              Artwork(
                                url: album.imageUrl,
                                size: double.infinity,
                                radius: BorderRadius.zero,
                                fit: BoxFit.cover,
                              ),
                              // Spectral glow accent
                              Positioned(
                                left: -40,
                                bottom: -40,
                                width: 160,
                                height: 160,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: RadialGradient(
                                      colors: [
                                        AfColors.indigo500.withValues(
                                          alpha: 0.3,
                                        ),
                                        Colors.transparent,
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              // Content
                              Padding(
                                padding: const EdgeInsets.all(AfSpacing.s20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Spacer(),
                                    // Album title — dramatic sizing
                                    Text(
                                      album.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: AfTypography.titleLarge.copyWith(
                                        color: AfColors.textOnPrimary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: AfSpacing.s4),
                                    Text(
                                      album.artistName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AfTypography.bodyLarge.copyWith(
                                        color: AfColors.indigo300,
                                      ),
                                    ),
                                    const SizedBox(height: AfSpacing.s16),
                                    // Play button with glow
                                    PressScale(
                                      ensureHitTarget: false,
                                      onTap: () async {
                                        final tracks = ref.read(
                                          playActionsProvider,
                                        );
                                        final detail = await ref.read(
                                          albumDetailProvider(album.id).future,
                                        );
                                        if (detail != null) {
                                          await tracks.playAlbum(detail.tracks);
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: AfSpacing.s20,
                                          vertical: AfSpacing.s8,
                                        ),
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [
                                              AfColors.indigo500,
                                              AfColors.indigo600,
                                            ],
                                          ),
                                          borderRadius: AfRadii.borderPill,
                                          boxShadow: [
                                            BoxShadow(
                                              color: AfColors.indigo500
                                                  .withValues(alpha: 0.35),
                                              blurRadius: 16,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              LucideIcons.play,
                                              color: AfColors.textOnPrimary,
                                              size: 20,
                                            ),
                                            const SizedBox(width: AfSpacing.s8),
                                            Text(
                                              'Play',
                                              style: AfTypography.bodyMedium
                                                  .copyWith(
                                                    color:
                                                        AfColors.textOnPrimary,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            // Dot indicators
            if (albums.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: AfSpacing.s12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    albums.length,
                    (i) => AnimatedContainer(
                      duration: AfDurations.quick,
                      margin: const EdgeInsets.symmetric(
                        horizontal: AfSpacing.s4,
                      ),
                      width: _currentPage == i ? 20 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        gradient: _currentPage == i
                            ? const LinearGradient(
                                colors: [
                                  AfColors.indigo400,
                                  AfColors.indigo600,
                                ],
                              )
                            : null,
                        color: _currentPage == i ? null : AfColors.surfaceMax,
                        borderRadius: AfRadii.borderPill,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Parses a hex colour string (6 or 8 digits with optional #) into a [Color].
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

// ---------------------------------------------------------------------------
// Glass morphism helpers
// ---------------------------------------------------------------------------

/// Glass pill button for the cast icon in the header.
class _GlassCastButton extends StatelessWidget {
  const _GlassCastButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      ensureHitTarget: false,
      onTap: onTap,
      child: ClipRRect(
        borderRadius: AfRadii.borderPill,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.all(AfSpacing.s12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: AfRadii.borderPill,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
                width: 1,
              ),
            ),
            child: const Icon(
              LucideIcons.cast,
              size: 18,
              color: AfColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
