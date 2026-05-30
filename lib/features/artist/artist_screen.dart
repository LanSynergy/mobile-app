import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/audio/play_actions.dart';
import '../../design_tokens/tokens.dart';
import '../../state/lastfm_metadata_providers.dart';
import '../../state/providers.dart';
import '../../state/radio_providers.dart';
import '../../widgets/artwork.dart';
import '../../widgets/async_error_view.dart';
import '../../widgets/section_header.dart';
import '../../widgets/track_context_menu.dart';
import '../../widgets/track_row.dart';
import '../../widgets/af_scrollbar.dart';
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
    final wikiAsync = ref.watch(artistWikiProvider(widget.artistId));

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
                        radius: AfRadii.borderMd,
                      ),
                    ),
                  ),
                ),
              ),

              AfScrollbar(
                child: CustomScrollView(
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
                              onRadio: () => _startArtistRadio(
                                context,
                                ref,
                                artist.name,
                                widget.artistId,
                              ),
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
                            onLongPress: () => showTrackContextMenu(
                              context,
                              ref,
                              topTracks[i],
                            ),
                          ),
                        ),
                      ),
                    ],
                    wikiAsync.maybeWhen(
                      data: (wiki) {
                        if (wiki == null ||
                            wiki.bio == null ||
                            wiki.bio!.isEmpty) {
                          return const SliverToBoxAdapter(child: SizedBox());
                        }
                        return SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AfSpacing.gutterGenerous,
                              vertical: AfSpacing.s24,
                            ),
                            child: _ArtistBiographyPanel(
                              bio: wiki.bio!,
                              listeners: wiki.listeners,
                              playCount: wiki.playCount,
                            ),
                          ),
                        );
                      },
                      orElse: () => const SliverToBoxAdapter(child: SizedBox()),
                    ),
                    const SliverToBoxAdapter(
                      child: SizedBox(
                        height: AfSpacing.bottomInsetWithMiniAndNav,
                      ),
                    ),
                  ],
                ),
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

Future<void> _startArtistRadio(
  BuildContext context,
  WidgetRef ref,
  String artistName,
  String artistId,
) async {
  unawaited(
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          color: AfColors.surfaceBase,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AfColors.indigo300,
                  ),
                ),
                SizedBox(width: 16),
                Text(
                  'Generating Artist Radio...',
                  style: TextStyle(color: AfColors.textPrimary),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  try {
    final generator = ref.read(radioGeneratorProvider);
    final queue = await generator.generateArtistRadio(artistName, artistId);

    if (context.mounted) Navigator.pop(context); // Close loading HUD

    if (queue.isNotEmpty) {
      await ref.read(playActionsProvider).playQueue(queue, startIndex: 0);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not generate similar artist radio queue.'),
          ),
        );
      }
    }
  } catch (e) {
    if (context.mounted) Navigator.pop(context); // Close loading HUD
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to start radio: $e')));
    }
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.onPlay, required this.onRadio});
  final VoidCallback? onPlay;
  final VoidCallback? onRadio;

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
        if (onRadio != null) ...[
          const SizedBox(width: AfSpacing.s12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onRadio,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AfColors.indigo600, width: 1.5),
                foregroundColor: AfColors.indigo300,
              ),
              icon: const Icon(LucideIcons.radio, size: 20),
              label: const Text('Artist Radio'),
            ),
          ),
        ],
      ],
    );
  }
}

class _ArtistBiographyPanel extends StatefulWidget {
  const _ArtistBiographyPanel({
    required this.bio,
    this.listeners,
    this.playCount,
  });
  final String bio;
  final String? listeners;
  final String? playCount;

  @override
  State<_ArtistBiographyPanel> createState() => _ArtistBiographyPanelState();
}

class _ArtistBiographyPanelState extends State<_ArtistBiographyPanel> {
  bool _expanded = false;

  String _cleanHtml(String html) {
    return html.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }

  String _formatNumber(String? numStr) {
    if (numStr == null) return '';
    final n = int.tryParse(numStr);
    if (n == null) return numStr;
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    final cleanText = _cleanHtml(widget.bio);
    if (cleanText.isEmpty) return const SizedBox();

    final stats = <String>[];
    if (widget.listeners != null) {
      stats.add('${_formatNumber(widget.listeners)} listeners');
    }
    if (widget.playCount != null) {
      stats.add('${_formatNumber(widget.playCount)} plays');
    }

    return Container(
      padding: const EdgeInsets.all(AfSpacing.s16),
      decoration: const BoxDecoration(
        color: AfColors.surfaceBase,
        borderRadius: AfRadii.borderMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Biography', style: AfTypography.titleSmall),
          if (stats.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              stats.join(' · '),
              style: AfTypography.bodySmall.copyWith(
                color: AfColors.textTertiary,
                fontSize: 11,
              ),
            ),
          ],
          const SizedBox(height: AfSpacing.s12),
          Text(
            cleanText,
            maxLines: _expanded ? null : 4,
            overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            style: AfTypography.bodySmall.copyWith(
              color: AfColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Text(
              _expanded ? 'Show less' : 'Read more',
              style: AfTypography.bodySmall.copyWith(
                color: AfColors.indigo300,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
