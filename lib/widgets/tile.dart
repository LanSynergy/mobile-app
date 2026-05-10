import 'package:flutter/material.dart';

import '../design_tokens/tokens.dart';
import 'artwork.dart';
import 'press_scale.dart';

enum TileVariant { album, playlist, artist }

/// Square-artwork tile — used everywhere we render a horizontal-scroll
/// row of albums/playlists/artists, or in 2-col grids on Library / Search.
class Tile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? imageUrl;
  final double size;
  final TileVariant variant;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const Tile({
    super.key,
    required this.title,
    required this.variant,
    this.subtitle,
    this.imageUrl,
    this.size = 152,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final art = variant == TileVariant.artist
        ? CircularArtwork(url: imageUrl, size: size)
        : Artwork(
            url: imageUrl,
            size: size,
            radius: BorderRadius.circular(AfRadii.md),
          );

    return PressScale(
      ensureHitTarget: false,
      onTap: onTap,
      onLongPress: onLongPress,
      child: SizedBox(
        width: size,
        child: Column(
          crossAxisAlignment: variant == TileVariant.artist
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            art,
            const SizedBox(height: AfSpacing.s8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: variant == TileVariant.artist
                  ? TextAlign.center
                  : TextAlign.left,
              style: AfTypography.titleSmall.copyWith(
                color: AfColors.textPrimary,
              ),
            ),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: variant == TileVariant.artist
                      ? TextAlign.center
                      : TextAlign.left,
                  style: AfTypography.bodySmall.copyWith(
                    color: AfColors.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Genre tile — solid color block, no artwork. Used on Home's Genres row.
class GenreTile extends StatelessWidget {
  final String name;
  final Color tint;
  final VoidCallback? onTap;
  final double width;
  final double height;

  const GenreTile({
    super.key,
    required this.name,
    required this.tint,
    this.onTap,
    this.width = 152,
    this.height = 96,
  });

  @override
  Widget build(BuildContext context) {
    return PressScale(
      ensureHitTarget: false,
      onTap: onTap,
      child: Container(
        width: width,
        height: height,
        padding: const EdgeInsets.all(AfSpacing.s12),
        decoration: BoxDecoration(
          color: tint,
          borderRadius: AfRadii.borderMd,
        ),
        alignment: Alignment.bottomLeft,
        child: Text(
          name,
          style: AfTypography.titleSmall.copyWith(
            color: AfColors.textOnPrimary,
          ),
        ),
      ),
    );
  }
}
