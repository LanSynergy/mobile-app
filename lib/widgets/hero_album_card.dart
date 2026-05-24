import 'package:flutter/material.dart';

import '../core/jellyfin/models/items.dart';
import '../design_tokens/tokens.dart';
import 'artwork.dart';
import 'press_scale.dart';

/// Hero album card — anchors the top of Home (§7.8).
///
/// Layout:
///   `┌────────────────────────────┬───────────┐
///    │ [pill] New Album           │           │
///    │                            │           │
///    │ Title                      │  artwork  │
///    │ Artist                     │  144×144  │
///    │                            │           │
///    │  [▶ Play]                  │           │
///    └────────────────────────────┴───────────┘`
class HeroAlbumCard extends StatelessWidget {

  const HeroAlbumCard({
    super.key,
    required this.album,
    this.pillLabel = 'New Album',
    this.onTap,
    this.onPlay,
  });
  final AfAlbum album;
  final String pillLabel;
  final VoidCallback? onTap;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      ensureHitTarget: false,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 168),
        margin: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AfColors.indigo800, AfColors.indigo700],
          ),
          borderRadius: AfRadii.borderLg,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Artwork — bleeds 8dp past the right edge.
            Positioned(
              right: -8,
              top: 12,
              bottom: 12,
              child: Artwork(
                url: album.imageUrl,
                size: 144,
                radius: AfRadii.borderMd,
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(
                AfSpacing.s16,
                AfSpacing.s16,
                160, // leave room for the artwork
                AfSpacing.s16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AfSpacing.s8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      // ignore: deprecated_member_use
                      color: AfColors.surfaceHigh.withValues(alpha: 0.24),
                      borderRadius: AfRadii.borderPill,
                    ),
                    child: Text(
                      pillLabel,
                      style: AfTypography.caption.copyWith(
                        color: AfColors.textOnPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: AfSpacing.s12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        album.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AfTypography.titleLarge.copyWith(
                          color: AfColors.textOnPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        album.artistName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AfTypography.bodyMedium.copyWith(
                          // ignore: deprecated_member_use
                          color: AfColors.textOnPrimary.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AfSpacing.s12),
                  _PlayPill(onTap: onPlay),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayPill extends StatelessWidget {
  const _PlayPill({this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      ensureHitTarget: false,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AfSpacing.s16,
          vertical: AfSpacing.s8,
        ),
        decoration: const BoxDecoration(
          color: AfColors.textOnPrimary,
          borderRadius: AfRadii.borderPill,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.play_arrow_rounded,
              color: AfColors.indigo700,
              size: 18,
            ),
            const SizedBox(width: 4),
            Text(
              'Play',
              style: AfTypography.bodyMedium.copyWith(
                color: AfColors.indigo700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
