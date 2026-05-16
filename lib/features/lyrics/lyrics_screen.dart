import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/lyrics/lrc_parser.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';

class LyricsScreen extends ConsumerStatefulWidget {
  const LyricsScreen({super.key});

  @override
  ConsumerState<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends ConsumerState<LyricsScreen> {
  final _scrollController = ScrollController();

  /// Estimated height of a single lyric row in logical pixels.
  ///
  /// Derived from the `titleMedium` line height (~24 dp) plus the
  /// symmetric 8 dp vertical padding applied to each item = 40 dp.
  /// Used to compute the scroll target without needing a GlobalKey on
  /// every row. Lyric lines are uniform height so the estimate is
  /// accurate enough to keep the active line centred.
  static const double _rowHeight = 40.0;

  /// Index of the active line on the previous build. Used to skip the
  /// scroll animation when the index hasn't actually changed (e.g. the
  /// position stream ticks but the active line is the same).
  int _lastScrolledIndex = -1;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Scroll the list so the active line sits in the vertical centre of
  /// the viewport. Called after every build where [activeIndex] changed.
  void _scrollToActive(int activeIndex, int lineCount) {
    if (!_scrollController.hasClients) return;
    if (activeIndex < 0) return;
    if (activeIndex == _lastScrolledIndex) return;
    _lastScrolledIndex = activeIndex;

    final viewportHeight = _scrollController.position.viewportDimension;
    // Target offset: top of the active row minus half the viewport so
    // the row lands in the centre. Add half a row height to centre on
    // the row's midpoint rather than its top edge.
    final target = (activeIndex * _rowHeight) -
        (viewportHeight / 2) +
        (_rowHeight / 2);
    final clamped = target.clamp(
      _scrollController.position.minScrollExtent,
      _scrollController.position.maxScrollExtent,
    );

    _scrollController.animateTo(
      clamped,
      duration: AfDurations.standard,
      curve: AfCurves.easeStandard,
    );
  }

  @override
  Widget build(BuildContext context) {
    final track = ref.watch(currentTrackProvider);
    final spectral = ref.watch(currentSpectralProvider);

    final lrcAsync = track == null
        ? const AsyncValue<Lrc?>.data(null)
        : ref.watch(lyricsProvider(track.id));
    final lrc = lrcAsync.maybeWhen(
      data: (parsed) => parsed,
      orElse: () => null,
    );

    // Reset scroll tracking when the track changes so lyrics follow from
    // the start of the new song.
    ref.listen(currentTrackProvider, (prev, next) {
      if (prev?.id != next?.id) {
        _lastScrolledIndex = -1;
      }
    });

    // Scroll to active line only when position actually changes — not on
    // every build. Using ref.listen avoids enqueuing a post-frame callback
    // on every position tick (which was growing the callback queue unboundedly).
    ref.listen(positionStreamProvider, (_, next) {
      final position = next.maybeWhen(data: (p) => p, orElse: () => Duration.zero);
      final active = lrc?.activeIndex(position) ?? -1;
      if (lrc != null && lrc.lines.isNotEmpty) {
        _scrollToActive(active, lrc.lines.length);
      }
    });

    final positionAsync = ref.watch(positionStreamProvider);
    final position =
        positionAsync.maybeWhen(data: (p) => p, orElse: () => Duration.zero);
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
            onPressed: () => context.push('/queue'),
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
          child: lrcAsync.maybeWhen(
            loading: () => const Center(child: CircularProgressIndicator()),
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
                controller: _scrollController,
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
                    // Fixed vertical padding matches _rowHeight assumption.
                    padding: const EdgeInsets.symmetric(vertical: 8),
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
      ),
    );
  }
}
