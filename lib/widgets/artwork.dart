import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../design_tokens/tokens.dart';

/// Network artwork that gracefully degrades to a deterministic indigo
/// gradient when the URL is null or fails to load. Used everywhere we
/// need an album/playlist/track cover.
class Artwork extends StatelessWidget {
  final String? url;
  final double size;
  final double? height;
  final BorderRadius radius;
  final BoxFit fit;
  final String? semanticLabel;

  const Artwork({
    super.key,
    required this.url,
    this.size = 56,
    this.height,
    this.radius = AfRadii.borderMd,
    this.fit = BoxFit.cover,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final w = size;
    final h = height ?? size;
    final placeholder = Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AfColors.indigo800, AfColors.indigo950],
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.music_note_rounded,
          color: AfColors.indigo300,
          size: 28,
        ),
      ),
    );
    if (url == null || url!.isEmpty) {
      return Semantics(label: semanticLabel, child: placeholder);
    }
    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        width: w,
        height: h,
        child: CachedNetworkImage(
          imageUrl: url!,
          fit: fit,
          placeholder: (_, __) => placeholder,
          errorWidget: (_, __, ___) => placeholder,
          fadeInDuration: AfDurations.quick,
          memCacheWidth: (w * 2).round(),
          memCacheHeight: (h * 2).round(),
        ),
      ),
    );
  }
}

/// Circular variant for artist tiles.
class CircularArtwork extends StatelessWidget {
  final String? url;
  final double size;
  final String? semanticLabel;

  const CircularArtwork({
    super.key,
    required this.url,
    this.size = 64,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) => Artwork(
        url: url,
        size: size,
        radius: BorderRadius.circular(size / 2),
        semanticLabel: semanticLabel,
      );
}
