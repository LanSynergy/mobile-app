import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/audio/play_actions.dart';
import '../../core/battery_opt.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/hero_album_card.dart';
import '../../widgets/section_header.dart';
import '../../widgets/tile.dart';
import '../../widgets/track_context_menu.dart';
import '../../widgets/track_row.dart';

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

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(appModeProvider);
    final isLocal = mode == AppMode.local;
    final albumsAsync = isLocal
        ? ref.watch(localAlbumsProvider)
        : ref.watch(recentlyAddedAlbumsProvider);
    final recentTracksAsync = isLocal
        ? ref.watch(localTracksProvider)
        : ref.watch(recentlyPlayedTracksProvider);
    final artistsAsync = isLocal
        ? ref.watch(localArtistsProvider)
        : ref.watch(allArtistsProvider);
    final genresAsync = isLocal
        ? ref.watch(localGenresProvider)
        : ref.watch(allGenresProvider);

    return ColoredBox(
      color: AfColors.surfaceCanvas,
      child: SafeArea(
      child: CustomScrollView(
        physics: const ClampingScrollPhysics(),
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
                  Text('Listen', style: AfTypography.display),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.cast_outlined),
                    onPressed: () => context.push('/cast'),
                    tooltip: 'Output',
                  ),
                ],
              ),
            ),
          ),

          // Hero album.
          SliverToBoxAdapter(
            child: albumsAsync.maybeWhen(
              data: (albums) => albums.isEmpty
                  ? const SizedBox.shrink()
                  : HeroAlbumCard(
                      album: albums.first,
                      onTap: () =>
                          context.push('/album/${albums.first.id}'),
                      onPlay: () async {
                        final tracks = ref
                            .read(playActionsProvider);
                        final detail = await ref.read(albumDetailProvider(albums.first.id).future);
                        if (detail != null) {
                          await tracks.playAlbum(detail.tracks);
                        }
                      },
                    ),
              orElse: () => const SizedBox(height: 168),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: AfSpacing.sectionGap)),

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
            child: recentTracksAsync.maybeWhen(
              data: (tracks) => ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding:
                    const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
                itemCount: tracks.take(5).length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: AfSpacing.s4),
                itemBuilder: (context, i) {
                  final t = tracks[i];
                  return TrackRow(
                    track: t,
                    density: TrackRowDensity.generous,
                    onTap: () =>
                        ref.read(playActionsProvider).playSingle(t),
                    onLongPress: () =>
                        showTrackContextMenu(context, ref, t),
                  );
                },
              ),
              orElse: () => const SizedBox(height: 80),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: AfSpacing.sectionGap)),

          // Artists.
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
              child: SectionHeader(
                title: 'Artists',
                actionLabel: 'See more',
                onActionTap: () => context.go('/library?section=artists'),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AfSpacing.s12)),
          SliverToBoxAdapter(
            child: artistsAsync.maybeWhen(
              data: (artists) => SizedBox(
                height: 172,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
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
                      onTap: () => context.push('/artist/${a.id}'),
                    );
                  },
                ),
              ),
              orElse: () => const SizedBox(height: 168),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: AfSpacing.sectionGap)),

          // Genres.
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
              child: SectionHeader(
                title: 'Genres',
                actionLabel: 'See more',
                onActionTap: () => context.go('/library?section=genres'),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AfSpacing.s12)),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 96,
              child: genresAsync.maybeWhen(
                data: (genres) => ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
                  itemCount: genres.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: AfSpacing.s12),
                  itemBuilder: (context, i) {
                    final g = genres[i];
                    return GenreTile(
                      name: g.name,
                      tint: _hex(g.tint),
                      onTap: () => context.push('/genre/${Uri.encodeComponent(g.name)}'),
                    );
                  },
                ),
                orElse: () => const SizedBox.shrink(),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: SizedBox(
              height: AfSpacing.bottomInsetWithMiniAndNav,
            ),
          ),
        ],
      ),
    ),
    );
  }

  Color _hex(String hex) {
    final v = int.parse(hex.replaceFirst('#', ''), radix: 16);
    return Color(0xFF000000 | v);
  }
}
