import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../design_tokens/tokens.dart';
import '../../../state/providers.dart';
import '../../../widgets/artwork.dart';
import '../../../widgets/async_error_view.dart';
import '../../../widgets/press_scale.dart';
import '../../../widgets/section_header.dart';
import '../../../widgets/skeletons/home_skeleton.dart';
import '../../library/library_screen.dart' show SongsPill, songsPillProvider;

/// Expressive artist section — YouTube Music style.
///
/// Features:
/// - Hero artist card with gradient overlay and action buttons
/// - 3-column artist grid with gradient ring borders
/// - Spectral accent colors throughout
class ArtistsSection extends ConsumerWidget {
  const ArtistsSection({super.key, required this.isLocal});
  final bool isLocal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Spectral spectral = ref.watch(currentSpectralProvider);
    final artistsAsync = isLocal
        ? ref.watch(localArtistsProvider)
        : ref.watch(allArtistsProvider);

    return SliverList(
      delegate: SliverChildListDelegate([
        const SizedBox(height: AfSpacing.sectionGap),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
          child: SectionHeader(
            title: 'Your Artists',
            actionLabel: 'See all',
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
          data: (artists) {
            if (artists.isEmpty) {
              return SizedBox(
                height: 180,
                child: Center(
                  child: Text('No artists yet', style: AfTypography.bodySmall),
                ),
              );
            }

            // Hero artist (first) + grid (next 3)
            final hero = artists.first;
            final grid = artists.skip(1).take(3).toList();

            return Column(
              children: [
                // Hero artist card
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AfSpacing.s16,
                  ),
                  child: PressScale(
                    ensureHitTarget: false,
                    onTap: () => context.push('/artist/${hero.id}'),
                    child: _HeroArtistCard(
                      name: hero.name,
                      imageUrl: hero.imageUrl,
                      spectral: spectral,
                    ),
                  ),
                ),

                // Artist grid
                if (grid.isNotEmpty) ...[
                  const SizedBox(height: AfSpacing.s12),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AfSpacing.s16,
                    ),
                    child: GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: AfSpacing.s8,
                      crossAxisSpacing: AfSpacing.s8,
                      childAspectRatio: 0.85,
                      children: grid
                          .map(
                            (a) => PressScale(
                              ensureHitTarget: false,
                              onTap: () => context.push('/artist/${a.id}'),
                              child: _ExpressiveArtistCard(
                                name: a.name,
                                imageUrl: a.imageUrl,
                                spectral: spectral,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ]),
    );
  }
}

/// Hero artist card with gradient overlay and action buttons.
class _HeroArtistCard extends StatelessWidget {
  const _HeroArtistCard({
    required this.name,
    this.imageUrl,
    required this.spectral,
  });

  final String name;
  final String? imageUrl;
  final Spectral spectral;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        borderRadius: AfRadii.borderLg,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[spectral.primary, spectral.secondary],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background artwork
          if (imageUrl != null)
            Artwork(url: imageUrl, size: 200, radius: AfRadii.borderLg),

          // Gradient overlay
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  AfColors.surfaceCanvas.withValues(alpha: 0.95),
                ],
              ),
            ),
          ),

          // Content
          Padding(
            padding: const EdgeInsets.all(AfSpacing.s16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: AfTypography.titleLarge.copyWith(
                    color: AfColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AfSpacing.s12),

                // Action buttons
                Row(
                  children: [
                    // Play button
                    Container(
                      padding: const EdgeInsets.all(AfSpacing.s8),
                      decoration: const BoxDecoration(
                        color: AfColors.textPrimary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        LucideIcons.play,
                        size: 20,
                        color: AfColors.surfaceCanvas,
                      ),
                    ),
                    const SizedBox(width: AfSpacing.s12),

                    // Shuffle button
                    Container(
                      padding: const EdgeInsets.all(AfSpacing.s8),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AfColors.textSecondary,
                          width: 1,
                        ),
                      ),
                      child: const Icon(
                        LucideIcons.shuffle,
                        size: 20,
                        color: AfColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: AfSpacing.s12),

                    // More button
                    Container(
                      padding: const EdgeInsets.all(AfSpacing.s8),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AfColors.textSecondary,
                          width: 1,
                        ),
                      ),
                      child: const Icon(
                        LucideIcons.moreHorizontal,
                        size: 20,
                        color: AfColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Expressive artist card with gradient ring border.
class _ExpressiveArtistCard extends StatelessWidget {
  const _ExpressiveArtistCard({
    required this.name,
    this.imageUrl,
    required this.spectral,
  });

  final String name;
  final String? imageUrl;
  final Spectral spectral;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Circular artwork with gradient border
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [spectral.primary, spectral.secondary],
            ),
          ),
          padding: const EdgeInsets.all(3),
          child: Container(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AfColors.surfaceCanvas,
            ),
            child: ClipOval(
              child: imageUrl != null
                  ? Artwork(url: imageUrl, size: 94, radius: AfRadii.borderPill)
                  : const Center(
                      child: Icon(
                        LucideIcons.user,
                        size: 32,
                        color: AfColors.textTertiary,
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: AfSpacing.s8),

        // Name
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: AfTypography.bodySmall.copyWith(fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}
