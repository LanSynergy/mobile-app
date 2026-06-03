import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/models/items.dart';
import '../../state/providers.dart';
import '../../widgets/artwork.dart';

/// Full-bleed artwork background for the now-playing screen.
class ReactiveArtwork extends ConsumerWidget {
  const ReactiveArtwork({super.key, required this.track});

  final AfTrack track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artworkUri = ref.watch(currentArtworkUriProvider);

    return Hero(
      tag: 'now-playing-artwork',
      child: Artwork(
        url: artworkUri?.toString() ?? track.imageUrl,
        size: double.infinity,
        radius: BorderRadius.zero,
      ),
    );
  }
}
