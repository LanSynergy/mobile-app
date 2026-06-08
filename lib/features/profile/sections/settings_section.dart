import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/jellyfin/models/items.dart';
import '../../../design_tokens/tokens.dart';
import '../../../widgets/artwork.dart';
import '../../../widgets/section_header.dart';

/// Displays the user's track and album counts.
class ProfileStatCards extends StatelessWidget {
  const ProfileStatCards({
    super.key,
    required this.trackCount,
    required this.albumCount,
  });

  final String trackCount;
  final String albumCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: AfSpacing.s24),
        Row(
          children: [
            StatCard(label: 'Tracks', value: trackCount),
            const SizedBox(width: AfSpacing.s12),
            StatCard(label: 'Albums', value: albumCount),
          ],
        ),
      ],
    );
  }
}

/// A single stat card showing a label and value.
class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(AfSpacing.s16),
        decoration: const BoxDecoration(
          color: AfColors.surfaceRaised,
          borderRadius: AfRadii.borderMd,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: AfTypography.titleLarge),
            const SizedBox(height: AfSpacing.s2),
            Text(
              label,
              style: AfTypography.bodySmall.copyWith(
                color: AfColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Section header for the "Pinned" albums row.
class PinnedSectionHeader extends StatelessWidget {
  const PinnedSectionHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(
        AfSpacing.s16,
        AfSpacing.s24,
        AfSpacing.s16,
        0,
      ),
      child: SectionHeader(title: 'Pinned', uppercase: true),
    );
  }
}

/// Horizontal row of pinned/favorite albums.
class PinnedAlbumsRow extends StatelessWidget {
  const PinnedAlbumsRow({super.key, required this.albums});

  final List<AfAlbum> albums;

  @override
  Widget build(BuildContext context) {
    if (albums.isEmpty) {
      return SizedBox(
        height: 120,
        child: Center(
          child: Text(
            'Heart an album to pin it here.',
            style: AfTypography.bodySmall.copyWith(
              color: AfColors.textTertiary,
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: albums.length,
        separatorBuilder: (context, index) =>
            const SizedBox(width: AfSpacing.s12),
        itemBuilder: (context, i) {
          final a = albums[i];
          return GestureDetector(
            onTap: () => context.push('/album/${a.id}'),
            child: SizedBox(
              width: 120,
              child: Stack(
                children: [
                  Artwork(url: a.imageUrl, size: 120, radius: AfRadii.borderMd),
                  Positioned.fill(
                    child: Container(
                      decoration: const BoxDecoration(
                        borderRadius: AfRadii.borderMd,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, AfColors.surfaceScrim],
                          stops: [0.5, 1.0],
                        ),
                      ),
                      alignment: Alignment.bottomLeft,
                      padding: const EdgeInsets.all(AfSpacing.s8),
                      child: Text(
                        a.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AfTypography.bodySmall.copyWith(
                          color: AfColors.textOnPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
