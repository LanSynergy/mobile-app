import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_tokens/tokens.dart';
import '../state/providers.dart';
import '../utils/url.dart';

/// Network artwork that gracefully degrades to a deterministic indigo
/// gradient when the URL is null or fails to load. Used everywhere we
/// need an album/playlist/track cover.
///
/// The widget reads `jellyfinClientProvider` so it can send the active
/// `Authorization` header alongside the image fetch. The token used to
/// ride in the URL as `?api_key=…`; review S2 moved it to a header,
/// which means Jellyfin servers with auth-required image endpoints
/// would 401 here without this wiring.
class Artwork extends ConsumerWidget {

  const Artwork({
    super.key,
    required this.url,
    this.size = 56,
    this.height,
    this.radius = AfRadii.borderMd,
    this.fit = BoxFit.cover,
    this.semanticLabel,
  });
  final String? url;
  final double size;
  final double? height;
  final BorderRadius radius;
  final BoxFit fit;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = size;
    final h = height ?? size;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double layoutW = w.isFinite ? w : (constraints.maxWidth.isFinite ? constraints.maxWidth : 152.0);
        final double layoutH = h.isFinite ? h : (constraints.maxHeight.isFinite ? constraints.maxHeight : layoutW);

        final placeholder = Container(
          width: w.isFinite ? w : null,
          height: h.isFinite ? h : null,
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

        final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 2.0;
        int? clampedCachePx(double logicalPx) {
          final physical = (logicalPx * dpr).round();
          if (physical <= 0) return null;
          return physical > 1024 ? 1024 : physical;
        }

        final cacheW = clampedCachePx(layoutW);
        final cacheH = clampedCachePx(layoutH);

        final backend = ref.watch(musicBackendProvider);
        final headers = backend?.authHeaders;

        // Local files: load from disk directly.
        if (url!.startsWith('file://')) {
          final filePath = url!.substring('file://'.length);
          return ClipRRect(
            borderRadius: radius,
            child: SizedBox(
              width: w.isFinite ? w : null,
              height: h.isFinite ? h : null,
              child: Image.file(
                File(filePath),
                fit: fit,
                width: w.isFinite ? w : null,
                height: h.isFinite ? h : null,
                errorBuilder: (context, error, stack) => placeholder,
                cacheWidth: cacheW,
                cacheHeight: cacheH,
              ),
            ),
          );
        }

        return ClipRRect(
          borderRadius: radius,
          child: SizedBox(
            width: w.isFinite ? w : null,
            height: h.isFinite ? h : null,
            child: CachedNetworkImage(
              // `cacheKey` strips Subsonic per-request salt/token (`u`, `t`,
              // `s`) and Jellyfin `api_key` from the URL so the disk cache
              // hits across requests. Without this, every list refresh
              // regenerates the auth params and re-downloads the same
              // bytes. The unsanitized URL is still used for `imageUrl` so
              // the actual HTTP fetch carries the live auth.
              cacheKey: stableImageCacheKey(url!),
              imageUrl: url!,
              httpHeaders: headers,
              fit: fit,
              placeholder: (context, url) => placeholder,
              errorWidget: (context, url, error) => placeholder,
              fadeInDuration: AfDurations.quick,
              memCacheWidth: cacheW,
              memCacheHeight: cacheH,
            ),
          ),
        );
      },
    );
  }
}

/// Circular variant for artist tiles.
class CircularArtwork extends StatelessWidget {

  const CircularArtwork({
    super.key,
    required this.url,
    this.size = 64,
    this.semanticLabel,
  });
  final String? url;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Artwork(
        url: url,
        size: size,
        radius: BorderRadius.circular(size / 2),
        semanticLabel: semanticLabel,
      );
}
