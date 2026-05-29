import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/audio/play_actions.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/artwork.dart';
import '../../widgets/async_error_view.dart';
import '../../widgets/section_header.dart';
import '../../widgets/track_context_menu.dart';
import '../../widgets/track_row.dart';
import '../../widgets/skeletons/artist_skeleton.dart';

class ArtistScreen extends ConsumerStatefulWidget {
  const ArtistScreen({super.key, required this.artistId});
  final String artistId;

  @override
  ConsumerState<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends ConsumerState<ArtistScreen> {
  final _scroll = ScrollController();
  late final ValueNotifier<double> _scrollOffset = ValueNotifier(0.0);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(
      () => _scrollOffset.value = _scroll.hasClients ? _scroll.offset : 0.0,
    );
  }

  @override
  void dispose() {
    _scrollOffset.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final artistAsync = ref.watch(artistDetailProvider(widget.artistId));
    final albumsAsync = ref.watch(artistAlbumsProvider(widget.artistId));
    final topTracksAsync = ref.watch(artistTopTracksProvider(widget.artistId));
    final activeId = ref.watch(currentTrackProvider)?.id;
    final isBuffering = ref.watch(isBufferingProvider);
    final activeAccent = ref.watch(currentSpectralProvider).energy;

    return Scaffold(
      backgroundColor: AfColors.surfaceCanvas,
      body: artistAsync.when(
        loading: () => const ArtistSkeleton(),
        error: (e, _) => AsyncErrorView(
          label: 'Could not load artist',
          error: e,
          onRetry: () => ref.invalidate(artistDetailProvider(widget.artistId)),
        ),
        data: (artist) {
          if (artist == null) {
            return const Center(child: Text('Artist not found'));
          }

          final topTracks = topTracksAsync.valueOrNull ?? [];
          final albums = albumsAsync.valueOrNull ?? [];
          final width = MediaQuery.of(context).size.width;
          final heroHeight = width; // 1:1

          // Use artist image or first album artwork as hero
          final heroUrl =
              artist.imageUrl ??
              (albums.isNotEmpty ? albums.first.imageUrl : null);

          return Stack(
            children: [
              // Hero artwork — parallax via Transform.translate
              ValueListenableBuilder<double>(
                valueListenable: _scrollOffset,
                builder: (context, offset, _) => Positioned(
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
                        url: heroUrl,
                        size: width,
                        height: heroHeight,
                        radius: BorderRadius.zero,
                      ),
                    ),
                  ),
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
                        horizontal: AfSpacing.gutterGenerous,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            artist.name,
                            style: AfTypography.display.copyWith(
                              color: AfColors.textPrimary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: AfSpacing.s4),
                          Text(
                            artist.statLine,
                            style: AfTypography.bodySmall.copyWith(
                              color: AfColors.textTertiary,
                            ),
                          ),
                          const SizedBox(height: AfSpacing.s16),
                          _ActionRow(
                            onPlay: topTracks.isNotEmpty
                                ? () => ref
                                      .read(playActionsProvider)
                                      .playQueue(topTracks, startIndex: 0)
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (topTracks.isNotEmpty) ...[
                    const SliverToBoxAdapter(
                      child: SizedBox(height: AfSpacing.s32),
                    ),
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: AfSpacing.gutterGenerous,
                        ),
                        child: SectionHeader(title: 'Top Songs'),
                      ),
                    ),
                    const SliverToBoxAdapter(
                      child: SizedBox(height: AfSpacing.s8),
                    ),
                    SliverList.separated(
                      itemCount: topTracks.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: AfSpacing.s4),
                      itemBuilder: (context, i) => Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AfSpacing.s16,
                        ),
                        child: TrackRow(
                          track: topTracks[i],
                          leadingNumber: i + 1,
                          isActive: topTracks[i].id == activeId,
                          isBuffering:
                              topTracks[i].id == activeId && isBuffering,
                          activeAccent: activeAccent,
                          onTap: () => ref
                              .read(playActionsProvider)
                              .playQueue(topTracks, startIndex: i),
                          onLongPress: () =>
                              showTrackContextMenu(context, ref, topTracks[i]),
                        ),
                      ),
                    ),
                  ],
                  const SliverToBoxAdapter(
                    child: SizedBox(
                      height: AfSpacing.bottomInsetWithMiniAndNav,
                    ),
                  ),
                ],
              ),

              // App bar
              ValueListenableBuilder<double>(
                valueListenable: _scrollOffset,
                builder: (context, offset, _) => Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _OpacityAppBar(
                    scrollOffset: offset,
                    threshold: heroHeight - kToolbarHeight,
                    title: artist.name,
                    onBack: () => context.pop(),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _OpacityAppBar extends StatelessWidget {
  const _OpacityAppBar({
    required this.scrollOffset,
    required this.threshold,
    required this.title,
    required this.onBack,
  });
  final double scrollOffset;
  final double threshold;
  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final t = (scrollOffset / threshold).clamp(0.0, 1.0);
    final bg = Color.lerp(
      Colors.transparent,
      AfColors.surfaceCanvas.withValues(alpha: 0.75),
      t,
    )!;
    return t > 0.01
        ? ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                color: bg,
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top,
                ),
                child: SizedBox(
                  height: kToolbarHeight,
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(
                          LucideIcons.arrowLeft,
                          color: AfColors.textPrimary,
                          size: 24,
                        ),
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
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
              ),
            ),
          )
        : Container(
            color: bg,
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
            child: SizedBox(
              height: kToolbarHeight,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      LucideIcons.arrowLeft,
                      color: AfColors.textPrimary,
                      size: 24,
                    ),
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
                  const SizedBox(width: 48),
                ],
              ),
            ),
          );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.onPlay});
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: onPlay,
            icon: const Icon(
              LucideIcons.play,
              color: AfColors.textOnPrimary,
              size: 22,
            ),
            label: const Text('Play'),
          ),
        ),
      ],
    );
  }
}
