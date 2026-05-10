import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/audio/play_actions.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/artwork.dart';
import '../../widgets/press_scale.dart';
import '../../widgets/track_row.dart';

/// Mockup 07 — Album detail.
///
///   Full-bleed 1:1 hero artwork at the top with a bottom fade ShaderMask
///   to surface.canvas. Parallax: artwork translates up at 0.5× scroll
///   speed (ScrollController-driven, not AnimationController-driven).
///   Below: title, artist, metadata line, action row, track list.
class AlbumScreen extends ConsumerStatefulWidget {
  final String albumId;
  const AlbumScreen({super.key, required this.albumId});

  @override
  ConsumerState<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends ConsumerState<AlbumScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(albumDetailProvider(widget.albumId));
    return Scaffold(
      backgroundColor: AfColors.surfaceCanvas,
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Icon(Icons.error_outline)),
        data: (detail) {
          if (detail == null) {
            return const Center(child: Text('Album not found'));
          }
          final album = detail.album;
          final tracks = detail.tracks;
          final width = MediaQuery.of(context).size.width;
          final heroHeight = width; // 1:1
          final offset = _scroll.hasClients ? _scroll.offset : 0.0;

          return Stack(
            children: [
              // Hero artwork — parallax via Transform.translate, scroll-linked.
              Positioned(
                top: -offset * 0.5,
                left: 0,
                right: 0,
                child: SizedBox(
                  height: heroHeight,
                  child: ShaderMask(
                    shaderCallback: (rect) {
                      return const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.6, 1.0],
                        colors: [Colors.white, Colors.transparent],
                      ).createShader(rect);
                    },
                    blendMode: BlendMode.dstIn,
                    child: Artwork(
                      url: album.imageUrl,
                      size: width,
                      height: heroHeight,
                      radius: BorderRadius.zero,
                    ),
                  ),
                ),
              ),

              // App bar — opacity 0→1 as artwork leaves viewport.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _OpacityAppBar(
                  scrollOffset: offset,
                  threshold: heroHeight - kToolbarHeight,
                  title: album.name,
                  onBack: () => context.pop(),
                ),
              ),

              CustomScrollView(
                controller: _scroll,
                physics: const ClampingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: SizedBox(height: heroHeight)),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AfSpacing.gutterGenerous),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            album.name,
                            style: AfTypography.display.copyWith(
                              color: AfColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: AfSpacing.s4),
                          GestureDetector(
                            onTap: album.artistId != null
                                ? () => context.push(
                                    '/artist/${album.artistId}')
                                : null,
                            child: Text(
                              album.artistName,
                              style: AfTypography.titleMedium.copyWith(
                                color: AfColors.indigo300,
                              ),
                            ),
                          ),
                          const SizedBox(height: AfSpacing.s4),
                          Text(
                            album.metadataLine,
                            style: AfTypography.bodySmall.copyWith(
                              color: AfColors.textTertiary,
                            ),
                          ),
                          const SizedBox(height: AfSpacing.s16),
                          _ActionRow(
                            onPlay: () => ref
                                .read(playActionsProvider)
                                .playAlbum(tracks),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(
                      child: SizedBox(height: AfSpacing.s24)),
                  SliverList.separated(
                    itemCount: tracks.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AfSpacing.s4),
                    itemBuilder: (context, i) => Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AfSpacing.s16),
                      child: TrackRow(
                        track: tracks[i],
                        leadingNumber: i + 1,
                        onTap: () => ref
                            .read(playActionsProvider)
                            .playQueue(tracks, startIndex: i),
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: SizedBox(
                        height: AfSpacing.bottomInsetWithMiniAndNav),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _OpacityAppBar extends StatelessWidget {
  final double scrollOffset;
  final double threshold;
  final String title;
  final VoidCallback onBack;

  const _OpacityAppBar({
    required this.scrollOffset,
    required this.threshold,
    required this.title,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final t = (scrollOffset / threshold).clamp(0.0, 1.0);
    return Container(
      color: Color.lerp(
        Colors.transparent,
        AfColors.surfaceCanvas,
        t,
      ),
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      child: SizedBox(
        height: kToolbarHeight,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: onBack,
            ),
            Expanded(
              child: Opacity(
                opacity: t,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: AfTypography.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.more_vert_rounded),
              onPressed: () {},
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final VoidCallback onPlay;
  const _ActionRow({required this.onPlay});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: onPlay,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Play'),
          ),
        ),
        const SizedBox(width: AfSpacing.s12),
        _IconCircle(icon: Icons.favorite_border, onTap: () {}),
        const SizedBox(width: AfSpacing.s8),
        _IconCircle(icon: Icons.download_outlined, onTap: () {}),
        const SizedBox(width: AfSpacing.s8),
        _IconCircle(icon: Icons.more_horiz_rounded, onTap: () {}),
      ],
    );
  }
}

class _IconCircle extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconCircle({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressScale(
      ensureHitTarget: false,
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: AfColors.surfaceBase,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 22, color: AfColors.textPrimary),
      ),
    );
  }
}
