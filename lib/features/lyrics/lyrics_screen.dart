import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/lyrics/lrc_parser.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';

class LyricsScreen extends ConsumerWidget {
  const LyricsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(currentTrackProvider);
    final positionAsync = ref.watch(positionStreamProvider);
    final position =
        positionAsync.maybeWhen(data: (p) => p, orElse: () => Duration.zero);
    final spectral = ref.watch(currentSpectralProvider);

    // Real lyrics from Jellyfin (`/Audio/{id}/Lyrics`). Returns `null` when
    // the server has none — we render a small empty state below rather
    // than fall back to the previous hard-coded demo LRC.
    final lrcAsync = track == null
        ? const AsyncValue<Lrc?>.data(null)
        : ref.watch(lyricsProvider(track.id));
    final lrc = lrcAsync.maybeWhen(
      data: (parsed) => parsed,
      orElse: () => null,
    );
    final active = lrc?.activeIndex(position) ?? -1;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Column(
          children: [
            Text(
              track?.title ?? 'Lyrics',
              style: AfTypography.titleSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (track != null)
              Text(
                track.artistName,
                style: AfTypography.caption.copyWith(
                  color: AfColors.textTertiary,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.queue_music_rounded),
            onPressed: () => context.go('/queue'),
            tooltip: 'Queue',
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AfColors.surfaceCanvas,
              // ignore: deprecated_member_use
              spectral.shadow.withValues(alpha: 0.5),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                margin: const EdgeInsets.all(AfSpacing.s16),
                padding: const EdgeInsets.symmetric(
                  horizontal: AfSpacing.s12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  // ignore: deprecated_member_use
                  color: AfColors.semanticInfo.withValues(alpha: 0.15),
                  borderRadius: AfRadii.borderPill,
                  border: Border.all(
                      color: AfColors.semanticInfo, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        size: 16, color: AfColors.semanticInfo),
                    const SizedBox(width: AfSpacing.s8),
                    Expanded(
                      child: Text(
                        'AI-fallback lyrics — accuracy not guaranteed.',
                        style: AfTypography.caption.copyWith(
                          color: AfColors.semanticInfo,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: lrcAsync.maybeWhen(
                  loading: () => const Center(
                    child: CircularProgressIndicator(),
                  ),
                  error: (e, _) => Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AfSpacing.gutterGenerous,
                      ),
                      child: Text(
                        'Could not load lyrics: $e',
                        style: AfTypography.bodySmall.copyWith(
                          color: AfColors.semanticError,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  orElse: () {
                    if (lrc == null || lrc.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AfSpacing.gutterGenerous,
                          ),
                          child: Text(
                            track == null
                                ? 'Start a track to see lyrics.'
                                : 'No lyrics available for this track.',
                            style: AfTypography.bodyMedium.copyWith(
                              color: AfColors.textTertiary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AfSpacing.gutterGenerous,
                        vertical: AfSpacing.s24,
                      ),
                      itemCount: lrc.lines.length,
                      itemBuilder: (context, i) {
                        final isActive = i == active;
                        return AnimatedContainer(
                          duration: AfDurations.quick,
                          curve: AfCurves.easeOut,
                          padding:
                              const EdgeInsets.symmetric(vertical: 8),
                          child: AnimatedScale(
                            scale: isActive ? 1.04 : 1.0,
                            duration: AfDurations.quick,
                            curve: AfCurves.easeOut,
                            alignment: Alignment.centerLeft,
                            child: AnimatedDefaultTextStyle(
                              duration: AfDurations.quick,
                              style: AfTypography.titleMedium.copyWith(
                                color: isActive
                                    ? spectral.energy
                                    : AfColors.textSecondary,
                                fontWeight: isActive
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                              child: Text(lrc.lines[i].text),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
