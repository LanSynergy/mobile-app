import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/models/items.dart';
import '../../state/providers.dart';
import '../../widgets/artwork.dart';

/// Card-style artwork for the now-playing screen.
///
/// Displays the album art as a centered, rounded-corner card with a spectral
/// shadow/glow beneath it. The card floats over the reactive background
/// gradient rather than filling the screen edge-to-edge.
///
/// Layout:
///   ┌─────────────────────────────┐
///   │         (top padding)       │
///   │   ┌───────────────────┐     │
///   │   │                   │     │
///   │   │    Album Artwork   │     │
///   │   │   (rounded card)   │     │
///   │   │                   │     │
///   │   └───────────────────┘     │
///   │      ↕ spectral glow        │
///   │                             │
///   └─────────────────────────────┘
class ReactiveArtwork extends ConsumerWidget {
  const ReactiveArtwork({super.key, required this.track});

  final AfTrack track;

  /// Horizontal padding around the artwork card.
  static const double _cardHorizontalPadding = 32;

  /// Top padding above the artwork card.
  static const double _cardTopPadding = 16;

  /// Aspect ratio of the artwork card (1.0 = square).
  static const double _cardAspectRatio = 1.0;

  /// Border radius of the artwork card.
  static const double _cardRadius = 24;

  /// Blur radius of the spectral glow beneath the card.
  static const double _glowBlur = 48;

  /// Spread radius of the spectral glow.
  static const double _glowSpread = 8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artworkUri = ref.watch(currentArtworkUriProvider);
    final spectral = ref.watch(currentSpectralProvider);
    final screenW = MediaQuery.of(context).size.width;

    final cardW = screenW - (_cardHorizontalPadding * 2);

    return Padding(
      padding: const EdgeInsets.only(
        top: _cardTopPadding,
        left: _cardHorizontalPadding,
        right: _cardHorizontalPadding,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: cardW),
          child: AspectRatio(
            aspectRatio: _cardAspectRatio,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cardH = constraints.maxHeight;
                final cardSize = cardH > 0 ? cardH : cardW;

                return Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    // ── Spectral glow beneath the card ──
                    Positioned(
                      top: cardSize * 0.15,
                      child: Container(
                        width: cardSize * 0.85,
                        height: cardSize * 0.85,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: spectral.energy.withValues(alpha: 0.30),
                              blurRadius: _glowBlur,
                              spreadRadius: _glowSpread,
                            ),
                            BoxShadow(
                              color: spectral.glow.withValues(alpha: 0.12),
                              blurRadius: _glowBlur * 1.5,
                              spreadRadius: _glowSpread * 1.5,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ── Artwork card ──
                    Hero(
                      tag: 'now-playing-artwork',
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(_cardRadius),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 0.5, sigmaY: 0.5),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(_cardRadius),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.4),
                                  blurRadius: 32,
                                  offset: const Offset(0, 12),
                                ),
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(_cardRadius),
                              child: Artwork(
                                url: artworkUri?.toString() ?? track.imageUrl,
                                size: double.infinity,
                                radius: BorderRadius.zero,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
