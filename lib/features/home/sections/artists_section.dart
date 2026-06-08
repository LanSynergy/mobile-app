import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design_tokens/tokens.dart';
import '../../../state/providers.dart';
import '../../../widgets/artwork.dart';
import '../../../widgets/async_error_view.dart';
import '../../../widgets/press_scale.dart';
import '../../../widgets/section_header.dart';
import '../../../widgets/skeletons/home_skeleton.dart';
import '../../library/library_screen.dart' show SongsPill, songsPillProvider;

/// Horizontal scroll of artists with warm glow ring backdrop.
class ArtistsSection extends ConsumerWidget {
  const ArtistsSection({super.key, required this.isLocal});
  final bool isLocal;

  // Warm amber accent colors for each artist ring — sourced from spectral palette
  static List<Color> _accents(
    ({Color primary, Color secondary, Color muted}) s,
  ) => [s.primary, s.secondary, s.muted, s.primary, s.secondary, s.muted];

  static const double _artworkSize = 88;
  static const double _ringSize = 96;
  static const double _glowSize = 100;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spectral = ref.watch(
      currentSpectralProvider.select(
        (s) => (primary: s.primary, secondary: s.secondary, muted: s.muted),
      ),
    );
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
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
              itemCount: artists.length,
              // itemExtent enables layout caching for large lists.
              // Includes the trailing separator gap (12px) per item.
              itemExtent: ArtistsSection._ringSize + AfSpacing.s12,
              itemBuilder: (context, i) {
                final a = artists[i];
                final accents = _accents(spectral);
                final accent = accents[i % accents.length];
                return PressScale(
                  ensureHitTarget: false,
                  onTap: () {
                    ref.read(songsPillProvider.notifier).state =
                        SongsPill.artists;
                    context.go('/library');
                  },
                  child: SizedBox(
                    width: _ringSize,
                    child: Column(
                      children: [
                        // Artwork with warm glow ring behind it
                        SizedBox(
                          width: _ringSize,
                          height: _ringSize,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Warm glow
                              Positioned(
                                child: Container(
                                  width: _glowSize,
                                  height: _glowSize,
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
                                size: _artworkSize,
                                radius: AfRadii.borderPill,
                              ),
                              // Warm ring
                              Positioned(
                                child: Container(
                                  width: _ringSize,
                                  height: _ringSize,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: accent.withValues(alpha: 0.3),
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
