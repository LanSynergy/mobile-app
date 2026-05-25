import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/audio/spectral_extractor.dart';
import '../design_tokens/colors.dart';
import '../utils/log.dart';
import '../utils/oklch.dart';
import 'music_backend_providers.dart';
import 'player_providers.dart';

final spectralExtractorProvider = Provider<SpectralExtractor>((ref) {
  return SpectralExtractor();
});

final currentSpectralProvider = Provider<Spectral>((ref) {
  final track = ref.watch(currentTrackProvider);
  final imageUrl = track?.imageUrl;
  final async = ref.watch(spectralFromUrlProvider(imageUrl));
  return async.maybeWhen(data: (s) => s, orElse: () => Spectral.fallback);
});

final spectralFromUrlProvider = FutureProvider.autoDispose
    .family<Spectral, String?>((ref, imageUrl) async {
      if (imageUrl == null) return Spectral.fallback;
      final backend = ref.watch(musicBackendProvider);
      final headers = backend?.authHeaders;
      try {
        return await ref
            .watch(spectralExtractorProvider)
            .fromImageUrl(imageUrl, headers: headers);
      } catch (e) {
        afLog('spectral', 'spectral extraction failed', error: e);
        return Spectral.fallback;
      }
    });

/// Pastel accent colour derived from the current artwork's spectral energy.
/// Converts the vibrant energy to OKLCH, then shifts it to a pastel profile
/// (lightness ~0.78, chroma ~0.08) for a soft, muted accent.
final pastelAccentColorProvider = Provider<Color>((ref) {
  final spectral = ref.watch(currentSpectralProvider);
  final energy = spectral.energy;
  final oklch = srgbToOklch(energy);
  final triple = buildPastelTriple(oklch.h);
  return triple.accent;
});
