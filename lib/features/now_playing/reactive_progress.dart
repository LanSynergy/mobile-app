import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../utils/time_format.dart';
import '../../widgets/audio_visual_scrubber.dart';

class ReactiveProgress extends ConsumerStatefulWidget {
  const ReactiveProgress({super.key, required this.track});

  final AfTrack track;

  @override
  ConsumerState<ReactiveProgress> createState() => _ReactiveProgressState();
}

class _ReactiveProgressState extends ConsumerState<ReactiveProgress> {
  double _sliderValue = 0;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    final pos = ref.read(positionStreamProvider);
    final dur = ref.read(durationStreamProvider);
    _sliderValue = _computeSliderValue(pos, dur);
  }

  double _computeSliderValue(Duration pos, Duration dur) {
    return dur.inMilliseconds > 0
        ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
  }

  String _format(Duration d) => formatTrackDuration(d);

  @override
  Widget build(BuildContext context) {
    final pos = ref.watch(positionStreamProvider);
    final dur = ref.watch(durationStreamProvider);
    final isBuffering = ref.watch(isBufferingProvider);
    // Freeze scrubber at 0 while buffering — mpv's position isn't
    // meaningful until playback actually starts.
    final effectivePos = isBuffering ? Duration.zero : pos;
    if (!_isDragging) {
      _sliderValue = _computeSliderValue(effectivePos, dur);
    }

    return Column(
      children: [
        AudioVisualScrubber(
          progress: _sliderValue,
          onScrub: (double v) {
            setState(() {
              _isDragging = true;
              _sliderValue = v;
            });
          },
          onScrubEnd: (double v) {
            final seekPos = Duration(
              milliseconds: (dur.inMilliseconds * v).round(),
            );
            ref.read(playerServiceProvider).seek(seekPos);
            setState(() => _isDragging = false);
          },
        ),
        const SizedBox(height: AfSpacing.s4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _format(effectivePos),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              Text(
                _format(dur),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
