import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/local/local_backend.dart';
import '../../core/local/saf_picker.dart';
import '../../core/lyrics/lrc_parser.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/async_error_view.dart';
import '../../widgets/skeletons/lyrics_skeleton.dart';

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

  /// Whether the user has manually scrolled the lyrics. When true, auto-scrolling
  /// is paused to let the user read.
  bool _userScrolled = false;
  Timer? _userScrollTimer;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _userScrollTimer?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.userScrollDirection !=
        ScrollDirection.idle) {
      if (!_userScrolled) {
        setState(() {
          _userScrolled = true;
        });
      }
      _userScrollTimer?.cancel();
      _userScrollTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) {
          setState(() {
            _userScrolled = false;
            _lastScrolledIndex =
                -1; // Force immediate snap-back to active lyric
          });
        }
      });
    }
  }

  /// Scroll the list so the active line sits in the vertical centre of
  /// the viewport. Called after every build where [activeIndex] changed.
  void _scrollToActive(int activeIndex, int lineCount) {
    if (!_scrollController.hasClients) {
      _lastScrolledIndex = -1;
      return;
    }

    final viewportHeight = _scrollController.position.viewportDimension;
    final minScroll = _scrollController.position.minScrollExtent;
    final maxScroll = _scrollController.position.maxScrollExtent;

    // If the list is expected to be scrollable but maxScroll is 0,
    // layout is probably not complete. Reset _lastScrolledIndex and schedule
    // a rebuild on the next frame to retry.
    final expectedContentHeight = lineCount * _rowHeight;
    if (maxScroll == 0.0 && expectedContentHeight > viewportHeight) {
      _lastScrolledIndex = -1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      return;
    }

    // Target offset: top of the active row minus half the viewport so
    // the row lands in the centre. Add half a row height to centre on
    // the row's midpoint rather than its top edge.
    final target =
        (activeIndex * _rowHeight) - (viewportHeight / 2) + (_rowHeight / 2);
    final clamped = target.clamp(minScroll, maxScroll);

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

    final position = ref.watch(positionStreamProvider);
    final isSynced =
        lrc != null && lrc.lines.any((l) => l.start > Duration.zero);
    final active = isSynced ? (lrc.activeIndex(position)) : -1;

    // Reset scroll tracking when the track changes so lyrics follow from
    // the start of the new song.
    ref.listen(currentTrackProvider, (prev, next) {
      if (prev?.id != next?.id) {
        _lastScrolledIndex = -1;
        _userScrolled = false;
        _userScrollTimer?.cancel();
      }
    });

    if (lrc != null &&
        lrc.lines.isNotEmpty &&
        active >= 0 &&
        active != _lastScrolledIndex &&
        !_userScrolled) {
      _lastScrolledIndex = active;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToActive(active, lrc.lines.length);
      });
    }

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
        color: AfColors.surfaceCanvas,
        child: SafeArea(
          child: lrcAsync.maybeWhen(
            loading: () => const LyricsSkeleton(),
            error: (e, _) => AsyncErrorView(
              label: 'Could not load lyrics',
              error: e,
              onRetry: () {
                final t = ref.read(currentTrackProvider);
                if (t != null) ref.invalidate(lyricsProvider(t.id));
              },
            ),
            orElse: () {
              if (lrc == null || lrc.isEmpty) {
                final backend = ref.watch(musicBackendProvider);
                final isLocal = backend is LocalBackend;

                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AfSpacing.gutterGenerous,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          track == null
                              ? 'Start a track to see lyrics.'
                              : 'No lyrics available for this track.',
                          style: AfTypography.bodyMedium.copyWith(
                            color: AfColors.textTertiary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (track != null && isLocal) ...[
                          const SizedBox(height: AfSpacing.s16),
                          FilledButton.icon(
                            onPressed: () async {
                              final lyricsContent =
                                  await SafPicker.pickAndReadLrcFile();
                              if (lyricsContent == null ||
                                  lyricsContent.trim().isEmpty) {
                                return;
                              }

                              final success = await backend.saveSidecarLrc(
                                track.id,
                                lyricsContent,
                              );
                              if (success) {
                                ref.invalidate(lyricsProvider(track.id));
                              } else {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Failed to save lyrics'),
                                    ),
                                  );
                                }
                              }
                            },
                            icon: const Icon(
                              Icons.upload_file_rounded,
                              size: 18,
                            ),
                            label: const Text('Load LRC File'),
                            style: FilledButton.styleFrom(
                              backgroundColor: AfColors.indigo600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }
              // Tap-to-seek only makes sense for synced lyrics. An
              // unsynced LRC parses every line at Duration.zero, so all
              // taps would yank playback back to 0:00 — noise, not
              // navigation. Detect once and use it to disable the
              // gesture entirely for unsynced payloads.
              final isSynced = lrc.lines.any((l) => l.start > Duration.zero);
              return ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(
                  horizontal: AfSpacing.gutterGenerous,
                  vertical: AfSpacing.s24,
                ),
                itemCount: lrc.lines.length,
                itemBuilder: (context, i) {
                  final isActive = i == active;
                  final line = lrc.lines[i];
                  return InkWell(
                    borderRadius: AfRadii.borderSm,
                    onTap: isSynced
                        ? () {
                            unawaited(HapticFeedback.selectionClick());
                            ref.read(playerServiceProvider).seek(line.start);
                          }
                        : null,
                    child: AnimatedContainer(
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
                          child: Text(line.text),
                        ),
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
