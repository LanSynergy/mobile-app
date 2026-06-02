import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/artwork.dart';

/// Displays the current track's artwork centered on screen.
class ReactiveArtwork extends ConsumerWidget {
  const ReactiveArtwork({super.key, required this.track});

  final AfTrack track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artworkUri = ref.watch(currentArtworkUriProvider);

    return Center(
      child: Hero(
        tag: 'now-playing-artwork',
        child: Artwork(
          url: artworkUri?.toString() ?? track.imageUrl,
          size: 300,
          radius: AfRadii.borderLg,
        ),
      ),
    );
  }
}
