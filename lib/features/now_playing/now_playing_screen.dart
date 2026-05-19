import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart'
    show
        Device,
        Loop;

import '../../core/audio/play_actions.dart';
import '../../core/backend/music_backend.dart';
import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../features/sleep_timer/sleep_timer_screen.dart';
import '../../state/providers.dart';
import '../../utils/display_error.dart';
import '../../utils/time_format.dart';
import '../../widgets/artwork.dart';
import '../../widgets/audio_visual_scrubber.dart';
import '../../widgets/press_scale.dart';
import '../../widgets/quality_chip.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NowPlayingScreen — Reactive Islands architecture
//
// Rebuild topology:
//   NowPlayingScreen    watches: currentTrackProvider (changes on skip only)
//   _ReactiveBackground watches: currentSpectralProvider (color extraction)
//   _ReactiveArtwork    watches: currentSpectralProvider (artwork + visualizer)
//   _ReactiveProgress   watches: positionStreamProvider (high-frequency)
//   _ReactiveTransport  watches: playingStreamProvider, shuffle, loop
//
// High-frequency streams (position, FFT) are isolated to leaf widgets
// so they never trigger rebuilds of the artwork, gradient, or metadata.
// ─────────────────────────────────────────────────────────────────────────────

class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only watches track identity — rebuilds on skip, not on position tick.
    final track = ref.watch(currentTrackProvider);

    if (track == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Nothing playing yet.')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      body: _ReactiveBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AfSpacing.gutterGenerous,
            ),
            child: Column(
              children: [
                _TopBar(track: track),
                const Spacer(),
                UnconstrainedBox(
                  clipBehavior: Clip.none,
                  child: _ReactiveArtwork(track: track),
                ),
                const Spacer(),
                _MetadataRow(track: track),
                const SizedBox(height: AfSpacing.s16),
                _ReactiveProgress(track: track),
                const SizedBox(height: AfSpacing.s24),
                _ReactiveTransport(track: track),
                const SizedBox(height: AfSpacing.s24),
                const _UtilityRow(),
                const SizedBox(height: AfSpacing.s16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reactive islands
// ─────────────────────────────────────────────────────────────────────────────

/// Watches spectral for the background gradient only.
/// Rebuilds when artwork color changes — not on position ticks.
class _ReactiveBackground extends ConsumerWidget {
  final Widget child;
  const _ReactiveBackground({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spectral = ref.watch(currentSpectralProvider);
    return AnimatedContainer(
      duration: AfDurations.expressive,
      curve: AfCurves.easeStandard,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AfColors.surfaceCanvas, spectral.shadow],
          stops: const [0.4, 1.0],
        ),
      ),
      child: child,
    );
  }
}

/// Artwork with sub-bass driven scale pulse.
/// Bin 0 (kick drum / sub-bass) drives a ±8% scale bump via asymmetric lerp.
/// ValueNotifier + Transform.scale — no setState, no rebuild of parent.
class _ReactiveArtwork extends ConsumerStatefulWidget {
  final AfTrack track;
  const _ReactiveArtwork({required this.track});

  @override
  ConsumerState<_ReactiveArtwork> createState() => _ReactiveArtworkState();
}

class _ReactiveArtworkState extends ConsumerState<_ReactiveArtwork>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<double> _scale = ValueNotifier(1.0);
  late final AnimationController _ticker;
  StreamSubscription<dynamic>? _fftSub;
  Timer? _silenceTimer;

  double _bassAverage = 0.0;
  double _prevBass    = 0.0;
  int    _cooldown    = 0;

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(() {
        if (_scale.value > 1.001) {
          // Exponential spring decay back to 1.0.
          _scale.value = 1.0 + (_scale.value - 1.0) * 0.85;
        } else {
          _scale.value = 1.0;
          _ticker.stop();
        }
      });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Don't subscribe to FFT if pulse animation is disabled.
      final pulseEnabled = ref.read(artworkPulseEnabledProvider);
      if (!pulseEnabled) return;

      _fftSub = ref.read(playerServiceProvider).spectrumStream.listen(
        (frame) {
          if (frame.bands.isEmpty) return;
          _silenceTimer?.cancel();

          // Kick / low-bass pool. With the player configured for 64
          // log-spaced bands over 20 Hz..20 kHz, the geometric ratio
          // is ~1.114/band, so band 0 ≈ 20–22 Hz (mostly room rumble)
          // and bands 1..6 span ≈ 22–45 Hz — the kick-drum fundamental
          // region on most music. Pool the peak of that window.
          final int hi = frame.bands.length < 7 ? frame.bands.length : 7;
          double rawBass = 0.0;
          for (var i = 1; i < hi; i++) {
            final v = frame.bands[i].abs();
            if (v > rawBass) rawBass = v;
          }

          final delta = rawBass - _prevBass;
          _prevBass = rawBass;

          // Asymmetric baseline: drops fast (0.12) so quiet passages
          // lower the floor quickly; rises slow (0.03) so kick peaks
          // stay well above the running average.
          _bassAverage += (rawBass - _bassAverage) *
              (rawBass < _bassAverage ? 0.12 : 0.03);

          // Transient detection — tuned for the wide 140 dB spectrum
          // range (-105..+35 dB). At that range a perceptually obvious
          // 10 dB kick only yields ~1.13× in normalised [0,1] space,
          // so the old 1.5× ratio was unreachable. Fire on either a
          // ratio spike (1.12×) or a sharp frame-to-frame delta (0.04).
          if (_cooldown > 0) {
            _cooldown--;
          } else if ((rawBass > _bassAverage * 1.12 || delta > 0.04) &&
                     rawBass > 0.015) {
            _scale.value = 1.06;  // +6% bump
            _cooldown    = 15;    // ~125ms lockout at 120 fps
            if (!_ticker.isAnimating) _ticker.repeat();
          }

          _silenceTimer = Timer(const Duration(milliseconds: 300), () {
            if (mounted) {
              _bassAverage = 0.0;
              _prevBass = 0.0;
            }
          });
        },
      );
    });
  }

  @override
  void dispose() {
    _silenceTimer?.cancel();
    _fftSub?.cancel();
    _ticker.dispose();
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spectral = ref.watch(currentSpectralProvider);
    final pulseEnabled = ref.watch(artworkPulseEnabledProvider);

    final artworkWidget = Center(
      child: Hero(
        tag: 'now-playing-artwork',
        child: Container(
          decoration: BoxDecoration(
            borderRadius: AfRadii.borderLg,
            boxShadow: [
              BoxShadow(
                color: spectral.glow.withValues(alpha: 0.30),
                blurRadius: 40,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Artwork(
            url: widget.track.imageUrl,
            size: 300,
            radius: AfRadii.borderLg,
          ),
        ),
      ),
    );

    if (!pulseEnabled) return artworkWidget;

    return ValueListenableBuilder<double>(
      valueListenable: _scale,
      builder: (context, scaleVal, child) => Transform.scale(
        scale: scaleVal,
        alignment: Alignment.center,
        child: child,
      ),
      child: artworkWidget,
    );
  }
}

/// Static metadata row — only rebuilds when track changes (on skip).
class _MetadataRow extends ConsumerWidget {
  final AfTrack track;
  const _MetadataRow({required this.track});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AfTypography.titleLarge,
              ),
              const SizedBox(height: 2),
              Text(
                track.artistName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AfTypography.bodyMedium.copyWith(
                  color: AfColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: Icon(
            track.isFavorite ? Icons.favorite : Icons.favorite_border,
            color: track.isFavorite
                ? AfColors.semanticError
                : AfColors.textPrimary,
          ),
          tooltip: track.isFavorite
              ? 'Remove from favorites'
              : 'Add to favorites',
          onPressed: () async {
            try {
              await ref.read(favoriteToggleProvider)(track);
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Could not update favorite'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            }
          },
        ),
        _AbLoopButton(),
        if (track.quality != null) QualityChip(quality: track.quality!),
      ],
    );
  }
}

class _AbLoopButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loopA = ref.watch(abLoopAProvider);
    final loopB = ref.watch(abLoopBProvider);
    final active = loopA != null;
    final fullyActive = loopA != null && loopB != null;

    return IconButton(
      icon: Icon(
        Icons.replay_rounded,
        color: fullyActive
            ? ref.watch(currentSpectralProvider).energy
            : active
                ? AfColors.semanticWarning
                : AfColors.textTertiary,
        size: 22,
      ),
      tooltip: 'A-B Loop',
      onPressed: () async {
        final svc = ref.read(playerServiceProvider);
        final pos = await svc.getRawPosition();

        if (loopA == null) {
          // Set A marker
          await svc.setAbLoopA(pos);
          ref.read(abLoopAProvider.notifier).state = pos;
          if (context.mounted) {
            ScaffoldMessenger.of(context)
              ..clearSnackBars()
              ..showSnackBar(const SnackBar(
                content: Text('Loop start set — tap again for end'),
                duration: Duration(seconds: 2),
              ));
          }
        } else if (loopB == null) {
          // Set B marker
          await svc.setAbLoopB(pos);
          ref.read(abLoopBProvider.notifier).state = pos;
          if (context.mounted) {
            ScaffoldMessenger.of(context)
              ..clearSnackBars()
              ..showSnackBar(const SnackBar(
                content: Text('A-B loop active — tap to clear'),
                duration: Duration(seconds: 2),
              ));
          }
        } else {
          // Clear both
          await svc.setAbLoopA(null);
          await svc.setAbLoopB(null);
          ref.read(abLoopAProvider.notifier).state = null;
          ref.read(abLoopBProvider.notifier).state = null;
          if (context.mounted) {
            ScaffoldMessenger.of(context)
              ..clearSnackBars()
              ..showSnackBar(const SnackBar(
                content: Text('A-B loop cleared'),
                duration: Duration(seconds: 1),
              ));
          }
        }
      },
    );
  }
}

/// Watches positionStreamProvider — the only widget that does.
/// Rebuilds at position tick rate; everything above is unaffected.
///
/// Scrub architecture:
///   onScrub    → local preview only (no seek, no audio pipeline churn)
///   onScrubEnd → single committed seek
class _ReactiveProgress extends ConsumerStatefulWidget {
  final AfTrack track;
  const _ReactiveProgress({required this.track});

  @override
  ConsumerState<_ReactiveProgress> createState() => _ReactiveProgressState();
}

class _ReactiveProgressState extends ConsumerState<_ReactiveProgress> {
  // Local scrub preview — updated during drag without seeking.
  double? _scrubPreview;
  bool _isDragging = false;

  @override
  void didUpdateWidget(covariant _ReactiveProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id) {
      _isDragging = false;
      _scrubPreview = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final position = ref.watch(positionStreamProvider);
    final spectral = ref.watch(currentSpectralProvider);
    final mpvDuration = ref.watch(durationStreamProvider);
    // Use mpv's reported duration as source of truth. Fall back to
    // track metadata only if mpv hasn't probed the file yet.
    final duration = mpvDuration > Duration.zero
        ? mpvDuration
        : widget.track.duration;

    // Only use engine position if NOT dragging — prevents the playhead
    // from stuttering between the drag position and the engine's real
    // position (which keeps advancing during the gesture).
    final engineProgress = duration.inMilliseconds == 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
    final displayProgress =
        _isDragging ? (_scrubPreview ?? engineProgress) : engineProgress;

    final displayPosition = _isDragging && _scrubPreview != null
        ? Duration(
            milliseconds: (_scrubPreview! * duration.inMilliseconds).round(),
          )
        : position;
    final remaining = duration > displayPosition
        ? duration - displayPosition
        : Duration.zero;

    return RepaintBoundary(
      child: Column(
        children: [
          AudioVisualScrubber(
            progress: displayProgress,
            playedColor: spectral.energy,
            height: 120,
            onScrub: (p) => setState(() {
              _isDragging = true;
              _scrubPreview = p;
            }),
            onScrubEnd: (p) {
              final newPos = Duration(
                milliseconds: (p * duration.inMilliseconds).round(),
              );
              // Hold the drag lock until the seek resolves so the engine's
              // new position matches the scrubber's drop point before we
              // hand control back to the stream. Timeout after 2s to prevent
              // permanent lock if seek hangs (e.g. during buffering).
              ref.read(playerServiceProvider).seek(newPos).timeout(
                const Duration(seconds: 2),
                onTimeout: () {},
              ).then((_) {
                if (mounted) {
                  setState(() {
                    _isDragging = false;
                    _scrubPreview = null;
                  });
                }
              });
            },
          ),
          const SizedBox(height: AfSpacing.s4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatTrackDuration(displayPosition),
                style: AfTypography.mono.copyWith(
                  color: AfColors.textSecondary,
                ),
              ),
              Text(
                formatRemaining(remaining),
                style: AfTypography.mono.copyWith(
                  color: AfColors.textTertiary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Watches playing/shuffle/loop — rebuilds on transport state changes only.
class _ReactiveTransport extends ConsumerWidget {
  final AfTrack track;
  const _ReactiveTransport({required this.track});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPlaying = ref.watch(playingStreamProvider).maybeWhen(
      data: (v) => v,
      orElse: () => false,
    );
    final shuffleOn = ref.watch(shuffleModeProvider).maybeWhen(
      data: (v) => v,
      orElse: () => false,
    );
    final loopMode = ref.watch(loopModeProvider).maybeWhen(
      data: (v) => v,
      orElse: () => Loop.off,
    );
    final spectral = ref.watch(currentSpectralProvider);

    return _TransportRow(
      isPlaying: isPlaying,
      spectral: spectral,
      shuffleOn: shuffleOn,
      loopMode: loopMode,
      accent: spectral.energy,
      onShuffle: () {
        final svc = ref.read(playerServiceProvider);
        unawaited(
          svc.setAfShuffleMode(!svc.isShuffleEnabled).catchError((_) {}),
        );
      },
      onRepeat: () {
        final svc = ref.read(playerServiceProvider);
        final next = switch (svc.loopMode) {
          Loop.off      => Loop.playlist,
          Loop.playlist => Loop.file,
          Loop.file     => Loop.off,
        };
        unawaited(svc.setAfLoopMode(next).catchError((_) {}));
      },
      onPlayPause: () {
        final svc = ref.read(playerServiceProvider);
        isPlaying ? svc.pause() : svc.play();
      },
      onPrev: () => ref.read(playerServiceProvider).skipToPrevious(),
      onNext: () => ref.read(playerServiceProvider).skipToNext(),
    );
  }
}

class _TopBar extends ConsumerWidget {
  final AfTrack track;
  const _TopBar({required this.track});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AfSpacing.s8,
        vertical: 4,
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
            onPressed: () => Navigator.maybePop(context),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  'Playing from album',
                  style: AfTypography.caption.copyWith(
                    color: AfColors.textTertiary,
                  ),
                ),
                Text(
                  track.albumName,
                  style: AfTypography.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const _SleepTimerBadge(),
          PopupMenuButton<_NowPlayingAction>(
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: (action) async {
              switch (action) {
                case _NowPlayingAction.startRadio:
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Starting Instant Mix…'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                  await ref.read(playActionsProvider).playInstantMix(track);
                  // Guard navigation after async gap.
                  if (!context.mounted) return;
                  break;
                case _NowPlayingAction.goToAlbum:
                  if (track.albumId != null) {
                    unawaited(context.push('/album/${track.albumId}'));
                  }
                  break;
                case _NowPlayingAction.goToArtist:
                  if (track.artistId != null) {
                    unawaited(context.push('/artist/${track.artistId}'));
                  }
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: _NowPlayingAction.startRadio,
                child: ListTile(
                  leading: Icon(Icons.radio_rounded),
                  title: Text('Start radio'),
                  subtitle: Text('Similar songs from your library'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (track.albumId != null)
                const PopupMenuItem(
                  value: _NowPlayingAction.goToAlbum,
                  child: ListTile(
                    leading: Icon(Icons.album_outlined),
                    title: Text('Go to album'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              if (track.artistId != null)
                const PopupMenuItem(
                  value: _NowPlayingAction.goToArtist,
                  child: ListTile(
                    leading: Icon(Icons.person_outline_rounded),
                    title: Text('Go to artist'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _NowPlayingAction { startRadio, goToAlbum, goToArtist }

/// Compact chip rendered next to the Now Playing popup menu when a
/// sleep timer is armed. Two visual modes:
///   • Numeric timer: bedtime icon + MM:SS (or H:MM if > 1 h remaining).
///   • End-of-track timer: bedtime icon only (no numeric countdown).
///
/// Tapping the chip opens the sleep timer dialog directly so the user
/// can cancel or change the duration without diving into the ⋯ menu.
class _SleepTimerBadge extends ConsumerWidget {
  const _SleepTimerBadge();

  static String _formatRemaining(Duration d) {
    // Round up so the user never sees 0:00 while the timer is still
    // technically running.
    final totalSeconds = d.inSeconds + (d.inMilliseconds % 1000 > 0 ? 1 : 0);
    if (totalSeconds >= 3600) {
      final h = totalSeconds ~/ 3600;
      final m = ((totalSeconds % 3600) / 60).ceil();
      return '$h:${m.toString().padLeft(2, '0')}';
    }
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(sleepTimerProvider);
    if (active == null) return const SizedBox.shrink();

    final remaining = ref.watch(sleepTimerRemainingProvider);

    return Padding(
      padding: const EdgeInsets.only(right: AfSpacing.s4),
      child: Material(
        color: AfColors.surfaceRaised,
        shape: RoundedRectangleBorder(borderRadius: AfRadii.borderSm),
        child: InkWell(
          borderRadius: AfRadii.borderSm,
          onTap: () {
            showDialog<void>(
              context: context,
              builder: (_) => Dialog(
                backgroundColor: AfColors.surfaceBase,
                shape:
                    RoundedRectangleBorder(borderRadius: AfRadii.borderLg),
                child: const _SleepTimerDialogContent(),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AfSpacing.s8,
              vertical: AfSpacing.s4,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.bedtime_rounded,
                  size: 16,
                  color: AfColors.indigo300,
                ),
                if (remaining != null) ...[
                  const SizedBox(width: AfSpacing.s4),
                  Text(
                    _formatRemaining(remaining),
                    style: AfTypography.mono.copyWith(
                      fontSize: 12,
                      color: AfColors.textPrimary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TransportRow extends StatelessWidget {
  final bool isPlaying;
  final Spectral spectral;
  final bool shuffleOn;
  final Loop loopMode;
  final Color accent;
  final VoidCallback onPlayPause;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onShuffle;
  final VoidCallback onRepeat;

  const _TransportRow({
    required this.isPlaying,
    required this.spectral,
    required this.shuffleOn,
    required this.loopMode,
    required this.accent,
    required this.onPlayPause,
    required this.onPrev,
    required this.onNext,
    required this.onShuffle,
    required this.onRepeat,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _TransportButton(
          icon: Icons.shuffle_rounded,
          size: 28,
          color: shuffleOn ? accent : AfColors.textPrimary,
          onTap: onShuffle,
        ),
        _TransportButton(
          icon: Icons.skip_previous_rounded,
          size: 40,
          onTap: onPrev,
        ),
        _PlayButton(
          isPlaying: isPlaying,
          color: spectral.energy,
          onTap: onPlayPause,
        ),
        _TransportButton(
          icon: Icons.skip_next_rounded,
          size: 40,
          onTap: onNext,
        ),
        _TransportButton(
          icon: loopMode == Loop.file
              ? Icons.repeat_one_rounded
              : Icons.repeat_rounded,
          size: 28,
          color: loopMode == Loop.off
              ? AfColors.textPrimary
              : accent,
          onTap: onRepeat,
        ),
      ],
    );
  }
}

class _TransportButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final VoidCallback onTap;
  final Color? color;
  const _TransportButton({
    required this.icon,
    required this.size,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: SizedBox(
        width: AfSpacing.minHitTarget,
        height: AfSpacing.minHitTarget,
        child: Icon(icon, size: size, color: color ?? AfColors.textPrimary),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  final bool isPlaying;
  final Color color;
  final VoidCallback onTap;

  const _PlayButton({
    required this.isPlaying,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PressScale(
      ensureHitTarget: false,
      onTap: onTap,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              // ignore: deprecated_member_use
              color: color.withValues(alpha: 0.4),
              blurRadius: 32,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Icon(
          isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          color: AfColors.textOnPrimary,
          size: 32,
        ),
      ),
    );
  }
}

class _UtilityRow extends ConsumerWidget {
  const _UtilityRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _UtilityIcon(
          icon: Icons.lyrics_outlined,
          label: 'Lyrics',
          onTap: () => context.push('/lyrics'),
        ),
        _UtilityIcon(
          icon: Icons.equalizer_rounded,
          label: 'EQ',
          onTap: () => context.push('/eq-dsp'),
        ),
        Consumer(builder: (context, ref, _) {
          final track = ref.watch(currentTrackProvider);
          final savedIds = ref.watch(savedTrackIdsProvider);
          final serverIds = ref.watch(playlistTrackIdsProvider).maybeWhen(
                data: (ids) => ids,
                orElse: () => const <String>{},
              );
          final isSaved = track != null &&
              (savedIds.contains(track.id) || serverIds.contains(track.id));
          return _UtilityIcon(
            icon: isSaved
                ? Icons.playlist_add_check_rounded
                : Icons.playlist_add_rounded,
            label: isSaved ? 'Saved' : 'Save',
            onTap: () => _showSaveDialog(context, ref),
            color: isSaved ? AfColors.indigo300 : null,
          );
        }),
        _UtilityIcon(
          icon: Icons.queue_music_rounded,
          label: 'Queue',
          onTap: () => context.push('/queue'),
        ),
        _UtilityIcon(
          icon: Icons.more_horiz_rounded,
          label: 'More',
          onTap: () => _showMoreSheet(context, ref),
        ),
      ],
    );
  }

  void _showMoreSheet(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => Dialog(
        backgroundColor: AfColors.surfaceBase,
        shape: RoundedRectangleBorder(borderRadius: AfRadii.borderLg),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AfSpacing.s16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _MoreItem(
                icon: Icons.bedtime_outlined,
                label: 'Sleep timer',
                onTap: () {
                  Navigator.of(dialogCtx).pop();
                  _showSleepDialog(context, ref);
                },
              ),
              _MoreItem(
                icon: Icons.speed_rounded,
                label: 'Playback speed',
                onTap: () {
                  Navigator.of(dialogCtx).pop();
                  _showSpeedDialog(context, ref);
                },
              ),
              _MoreItem(
                icon: Icons.cast_outlined,
                label: 'Audio output',
                onTap: () {
                  Navigator.of(dialogCtx).pop();
                  _showOutputDialog(context, ref);
                },
              ),
              _MoreItem(
                icon: Icons.volume_up_rounded,
                label: 'Volume',
                onTap: () {
                  Navigator.of(dialogCtx).pop();
                  _showVolumeDialog(context, ref);
                },
              ),
              _MoreItem(
                icon: Icons.bluetooth_audio_rounded,
                label: 'Audio delay',
                onTap: () {
                  Navigator.of(dialogCtx).pop();
                  _showAudioDelayDialog(context, ref);
                },
              ),
              _MoreItem(
                icon: Icons.repeat_one_rounded,
                label: 'A-B Loop',
                onTap: () {
                  Navigator.of(dialogCtx).pop();
                  _showAbLoopDialog(context, ref);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showVolumeDialog(BuildContext context, WidgetRef ref) {
    final svc = ref.read(playerServiceProvider);
    double volume = svc.volume;
    bool muted = svc.isMuted;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AfColors.surfaceBase,
          title: Row(
            children: [
              const Text('Volume'),
              const Spacer(),
              IconButton(
                icon: Icon(muted ? Icons.volume_off_rounded : Icons.volume_up_rounded),
                onPressed: () {
                  muted = !muted;
                  svc.setMute(muted);
                  setDialogState(() {});
                },
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Slider(
                value: volume.clamp(0, 150),
                min: 0,
                max: 150,
                divisions: 30,
                activeColor: AfColors.indigo400,
                label: '${volume.round()}%',
                onChanged: (v) {
                  volume = v;
                  svc.setVolume(v);
                  setDialogState(() {});
                },
              ),
              Text(
                '${volume.round()}%',
                style: AfTypography.mono.copyWith(color: AfColors.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAudioDelayDialog(BuildContext context, WidgetRef ref) {
    final svc = ref.read(playerServiceProvider);
    double delayMs = svc.audioDelay.inMilliseconds.toDouble();
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AfColors.surfaceBase,
          title: const Text('Audio delay'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Shift audio timing for Bluetooth sync',
                style: AfTypography.bodySmall.copyWith(color: AfColors.textTertiary),
              ),
              const SizedBox(height: AfSpacing.s16),
              Slider(
                value: delayMs.clamp(-500, 500),
                min: -500,
                max: 500,
                divisions: 20,
                activeColor: AfColors.indigo400,
                label: '${delayMs.round()} ms',
                onChanged: (v) {
                  delayMs = v;
                  svc.setAudioDelay(Duration(milliseconds: v.round()));
                  setDialogState(() {});
                },
              ),
              Text(
                '${delayMs.round()} ms',
                style: AfTypography.mono.copyWith(color: AfColors.textTertiary),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                delayMs = 0;
                svc.setAudioDelay(Duration.zero);
                setDialogState(() {});
              },
              child: const Text('Reset'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAbLoopDialog(BuildContext context, WidgetRef ref) {
    final svc = ref.read(playerServiceProvider);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AfColors.surfaceBase,
        title: const Text('A-B Loop'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Set markers to loop a section of the track.',
              style: AfTypography.bodySmall.copyWith(color: AfColors.textTertiary),
            ),
            const SizedBox(height: AfSpacing.s16),
            FilledButton.icon(
              onPressed: () async {
                final pos = await svc.getRawPosition();
                await svc.setAbLoopA(pos);
                ref.read(abLoopAProvider.notifier).state = pos;
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Loop start: ${_fmtDuration(pos)}')),
                  );
                }
              },
              icon: const Icon(Icons.flag_rounded, size: 18),
              label: const Text('Set A (start)'),
              style: FilledButton.styleFrom(backgroundColor: AfColors.indigo600),
            ),
            const SizedBox(height: AfSpacing.s8),
            FilledButton.icon(
              onPressed: () async {
                final pos = await svc.getRawPosition();
                await svc.setAbLoopB(pos);
                ref.read(abLoopBProvider.notifier).state = pos;
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Loop end: ${_fmtDuration(pos)}')),
                  );
                }
              },
              icon: const Icon(Icons.flag_outlined, size: 18),
              label: const Text('Set B (end)'),
              style: FilledButton.styleFrom(backgroundColor: AfColors.indigo600),
            ),
            const SizedBox(height: AfSpacing.s8),
            OutlinedButton.icon(
              onPressed: () async {
                await svc.setAbLoopA(null);
                await svc.setAbLoopB(null);
                ref.read(abLoopAProvider.notifier).state = null;
                ref.read(abLoopBProvider.notifier).state = null;
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('A-B loop cleared')),
                  );
                }
              },
              icon: const Icon(Icons.clear_rounded, size: 18),
              label: const Text('Clear loop'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AfColors.semanticError,
                side: const BorderSide(color: AfColors.surfaceHigh),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _showSaveDialog(BuildContext context, WidgetRef ref) {
    final track = ref.read(currentTrackProvider);
    if (track == null) return;
    final backend = ref.read(musicBackendProvider);
    if (backend == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to save to playlists')),
      );
      return;
    }

    showDialog<void>(
      context: context,
      builder: (dialogCtx) => Dialog(
        backgroundColor: AfColors.surfaceBase,
        shape: RoundedRectangleBorder(borderRadius: AfRadii.borderLg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360, maxHeight: 480),
          child: _SaveToPlaylistSheet(
            track: track,
            client: backend,
            onInvalidate: () => ref.invalidate(allPlaylistsProvider),
            onSaved: () {
              ref.read(savedTrackIdsProvider.notifier).update(
                    (ids) => {...ids, track.id},
                  );
              ref.invalidate(playlistTrackIdsProvider);
            },
          ),
        ),
      ),
    );
  }

  void _showSpeedDialog(BuildContext context, WidgetRef ref) {
    const speeds = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
    final current = ref.read(playerServiceProvider).speed;
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => Dialog(
        backgroundColor: AfColors.surfaceBase,
        shape: RoundedRectangleBorder(borderRadius: AfRadii.borderLg),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AfSpacing.s16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AfSpacing.gutterGenerous,
                ),
                child: Text('Playback speed', style: AfTypography.titleSmall),
              ),
              const SizedBox(height: AfSpacing.s8),
              for (final s in speeds)
                ListTile(
                  title: Text(
                    '${s.toStringAsFixed(s == s.roundToDouble() ? 1 : 2)}×',
                    style: AfTypography.bodyMedium,
                  ),
                  trailing: (s - current).abs() < 0.001
                      ? const Icon(Icons.check_rounded, size: 20)
                      : null,
                  onTap: () {
                    unawaited(ref.read(playerServiceProvider).setAfSpeed(s));
                    Navigator.of(dialogCtx).pop();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSleepDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => Dialog(
        backgroundColor: AfColors.surfaceBase,
        shape: RoundedRectangleBorder(borderRadius: AfRadii.borderLg),
        child: const _SleepTimerDialogContent(),
      ),
    );
  }

  void _showOutputDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => Dialog(
        backgroundColor: AfColors.surfaceBase,
        shape: RoundedRectangleBorder(borderRadius: AfRadii.borderLg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360, maxHeight: 480),
          child: const _OutputDialogContent(),
        ),
      ),
    );
  }
}

class _UtilityIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  const _UtilityIcon({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    // ensureHitTarget: true ensures 48×48 dp minimum touch area.
    return PressScale(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AfSpacing.s8),
        child: Column(
          children: [
            Icon(icon, size: 22, color: color ?? AfColors.textSecondary),
            const SizedBox(height: 4),
            Text(
              label,
              style: AfTypography.caption.copyWith(
                color: color ?? AfColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoreItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MoreItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AfSpacing.gutterGenerous,
          vertical: AfSpacing.s12,
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: AfColors.textSecondary),
            const SizedBox(width: AfSpacing.s16),
            Text(label, style: AfTypography.bodyMedium),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sleep timer dialog
// ─────────────────────────────────────────────────────────────────────────────

class _SleepTimerDialogContent extends ConsumerStatefulWidget {
  const _SleepTimerDialogContent();

  @override
  ConsumerState<_SleepTimerDialogContent> createState() =>
      _SleepTimerDialogContentState();
}

class _SleepTimerDialogContentState
    extends ConsumerState<_SleepTimerDialogContent> {
  static const _presets = [5, 10, 15, 30, 45, 60];
  int? _selectedMinutes;
  bool _showCustomInput = false;
  final _customController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Pre-select the currently active timer duration so the chip is
    // highlighted when re-opening the dialog.
    final activeTimer = ref.read(sleepTimerProvider);
    if (activeTimer != null) {
      final isEndOfTrack =
          activeTimer.difference(DateTime.now()).inHours > 12;
      if (isEndOfTrack) {
        _selectedMinutes = 0;
      } else {
        final remaining = activeTimer.difference(DateTime.now()).inMinutes;
        // Find the closest preset, or keep the raw remaining value.
        final closest = _presets.cast<int?>().firstWhere(
          (p) => (p! - remaining).abs() <= 2,
          orElse: () => null,
        );
        _selectedMinutes = closest ?? remaining;
      }
    }
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  void _setTimer() {
    if (_selectedMinutes == null) return;
    if (_selectedMinutes == 0) {
      ref.read(sleepTimerProvider.notifier).state =
          DateTime.now().add(const Duration(days: 1));
      ref.read(sleepTimerRemainingProvider.notifier).state = null;
    } else {
      final target = DateTime.now().add(Duration(minutes: _selectedMinutes!));
      ref.read(sleepTimerProvider.notifier).state = target;
      ref.read(sleepTimerRemainingProvider.notifier).state =
          Duration(minutes: _selectedMinutes!);
    }
    Navigator.of(context).pop();
  }

  void _cancelTimer() {
    ref.read(sleepTimerProvider.notifier).state = null;
    ref.read(sleepTimerRemainingProvider.notifier).state = null;
    Navigator.of(context).pop();
  }

  void _applyCustom() {
    final text = _customController.text.trim();
    final mins = int.tryParse(text);
    if (mins == null || mins <= 0) return;
    setState(() {
      _selectedMinutes = mins;
      _showCustomInput = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final activeTimer = ref.watch(sleepTimerProvider);
    final isActive = activeTimer != null;

    return Padding(
      padding: const EdgeInsets.all(AfSpacing.gutterGenerous),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Sleep timer', style: AfTypography.titleSmall),
          const SizedBox(height: AfSpacing.s16),
          if (isActive) ...[
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AfSpacing.s12,
                vertical: AfSpacing.s8,
              ),
              decoration: BoxDecoration(
                color: AfColors.indigo800.withValues(alpha: 0.4),
                borderRadius: AfRadii.borderMd,
              ),
              child: Row(
                children: [
                  const Icon(Icons.bedtime_rounded,
                      color: AfColors.indigo300, size: 18),
                  const SizedBox(width: AfSpacing.s8),
                  Expanded(
                    child: Text(
                      'Timer active',
                      style: AfTypography.bodySmall
                          .copyWith(color: AfColors.indigo300),
                    ),
                  ),
                  TextButton(
                    onPressed: _cancelTimer,
                    child: Text(
                      'Cancel',
                      style: AfTypography.bodySmall
                          .copyWith(color: AfColors.semanticError),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AfSpacing.s16),
          ],
          Wrap(
            spacing: AfSpacing.s8,
            runSpacing: AfSpacing.s8,
            children: [
              for (final m in _presets)
                ChoiceChip(
                  label: Text('$m min'),
                  selected: _selectedMinutes == m,
                  onSelected: (_) => setState(() {
                    _selectedMinutes = m;
                    _showCustomInput = false;
                  }),
                  selectedColor: AfColors.indigo600,
                  backgroundColor: AfColors.surfaceRaised,
                  labelStyle: AfTypography.bodySmall.copyWith(
                    color: _selectedMinutes == m
                        ? AfColors.textOnPrimary
                        : AfColors.textPrimary,
                  ),
                ),
              ChoiceChip(
                label: const Text('End of track'),
                selected: _selectedMinutes == 0,
                onSelected: (_) => setState(() {
                  _selectedMinutes = 0;
                  _showCustomInput = false;
                }),
                selectedColor: AfColors.indigo600,
                backgroundColor: AfColors.surfaceRaised,
                labelStyle: AfTypography.bodySmall.copyWith(
                  color: _selectedMinutes == 0
                      ? AfColors.textOnPrimary
                      : AfColors.textPrimary,
                ),
              ),
              ChoiceChip(
                label: Text(_showCustomInput ||
                        (_selectedMinutes != null &&
                            _selectedMinutes != 0 &&
                            !_presets.contains(_selectedMinutes))
                    ? '${_selectedMinutes ?? "?"} min'
                    : 'Custom'),
                selected: _showCustomInput ||
                    (_selectedMinutes != null &&
                        _selectedMinutes != 0 &&
                        !_presets.contains(_selectedMinutes)),
                onSelected: (_) => setState(() => _showCustomInput = true),
                selectedColor: AfColors.indigo600,
                backgroundColor: AfColors.surfaceRaised,
                labelStyle: AfTypography.bodySmall.copyWith(
                  color: _showCustomInput ||
                          (_selectedMinutes != null &&
                              _selectedMinutes != 0 &&
                              !_presets.contains(_selectedMinutes))
                      ? AfColors.textOnPrimary
                      : AfColors.textPrimary,
                ),
              ),
            ],
          ),
          if (_showCustomInput) ...[
            const SizedBox(height: AfSpacing.s16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _customController,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      hintText: 'Minutes',
                      isDense: true,
                    ),
                    onSubmitted: (_) => _applyCustom(),
                  ),
                ),
                const SizedBox(width: AfSpacing.s8),
                TextButton(
                  onPressed: _applyCustom,
                  child: const Text('Set'),
                ),
              ],
            ),
          ],
          const SizedBox(height: AfSpacing.s24),
          ElevatedButton(
            onPressed: _selectedMinutes == null ? null : _setTimer,
            child: Text(_selectedMinutes == null ? 'Pick a time' : 'Set timer'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Output dialog
// ─────────────────────────────────────────────────────────────────────────────

class _OutputDialogContent extends ConsumerWidget {
  const _OutputDialogContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final svc = ref.watch(playerServiceProvider);

    return StreamBuilder<List<Device>>(
      stream: svc.audioDevicesStream,
      initialData: svc.audioDevices,
      builder: (context, devicesSnap) {
        return StreamBuilder<Device>(
          stream: svc.audioDeviceStream,
          initialData: svc.audioDevice,
          builder: (context, activeSnap) {
            final devices = devicesSnap.data ?? [];
            final active = activeSnap.data;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: AfSpacing.s16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AfSpacing.gutterGenerous),
                    child: Text('Output', style: AfTypography.titleSmall),
                  ),
                  const SizedBox(height: AfSpacing.s8),
                  if (devices.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(AfSpacing.gutterGenerous),
                      child: Text(
                        'No audio devices found.\nStart playback first.',
                        style: AfTypography.bodyMedium
                            .copyWith(color: AfColors.textTertiary),
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    ...devices.map((device) {
                      final isActive = active?.name == device.name;
                      return ListTile(
                        leading: Icon(
                          _iconForDevice(device.description.isNotEmpty
                              ? device.description
                              : device.name),
                          color: isActive
                              ? AfColors.indigo300
                              : AfColors.textSecondary,
                        ),
                        title: Text(
                          device.description.isNotEmpty
                              ? device.description
                              : device.name,
                          style: AfTypography.bodyMedium,
                        ),
                        trailing: isActive
                            ? const Icon(Icons.check_rounded,
                                color: AfColors.indigo300, size: 20)
                            : null,
                        onTap: () async {
                          await svc.setAudioDevice(device);
                          if (context.mounted) Navigator.of(context).pop();
                        },
                      );
                    }),
                ],
              ),
            );
          },
        );
      },
    );
  }

  IconData _iconForDevice(String name) {
    final n = name.toLowerCase();
    if (n.contains('bluetooth') || n.contains('bt')) {
      return Icons.bluetooth_audio_rounded;
    }
    if (n.contains('headphone') || n.contains('headset') ||
        n.contains('earphone') || n.contains('airpod')) {
      return Icons.headphones_rounded;
    }
    if (n.contains('speaker')) return Icons.speaker_rounded;
    if (n.contains('hdmi')) return Icons.tv_rounded;
    if (n.contains('usb')) return Icons.usb_rounded;
    return Icons.smartphone_rounded;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Save to playlist sheet
// ─────────────────────────────────────────────────────────────────────────────

class _SaveToPlaylistSheet extends StatefulWidget {
  final AfTrack track;
  final MusicBackend client;
  final VoidCallback onInvalidate;
  final VoidCallback? onSaved;

  const _SaveToPlaylistSheet({
    required this.track,
    required this.client,
    required this.onInvalidate,
    this.onSaved,
  });

  @override
  State<_SaveToPlaylistSheet> createState() => _SaveToPlaylistSheetState();
}

class _SaveToPlaylistSheetState extends State<_SaveToPlaylistSheet> {
  List<AfPlaylist>? _playlists;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  final _newNameCtl = TextEditingController();
  bool _showNewPlaylist = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _newNameCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final playlists = await widget.client.playlists();
      if (mounted) setState(() { _playlists = playlists; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _addTo(AfPlaylist playlist) async {
    // Guard against concurrent taps.
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.client.addToPlaylist(playlist.id, [widget.track.id]);
      widget.onInvalidate();
      widget.onSaved?.call();
      if (mounted) {
        unawaited(Navigator.maybePop(context));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added to ${playlist.name}')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(displayError(e, prefix: 'Failed'))),
        );
      }
    }
  }

  Future<void> _createAndAdd() async {
    // Guard against concurrent taps.
    if (_saving) return;
    final name = _newNameCtl.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.client.createPlaylist(name, [widget.track.id]);
      widget.onInvalidate();
      widget.onSaved?.call();
      if (mounted) {
        unawaited(Navigator.maybePop(context));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Created "$name" and added track')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(displayError(e, prefix: 'Failed'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AfSpacing.s12),
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: AfColors.textTertiary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: AfSpacing.s12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AfSpacing.gutterGenerous),
            child: Text('Save to playlist', style: AfTypography.titleSmall),
          ),
          const SizedBox(height: AfSpacing.s8),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(AfSpacing.s24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(AfSpacing.gutterGenerous),
              child: Text(_error!, style: AfTypography.bodySmall.copyWith(color: AfColors.semanticError)),
            )
          else ...[
            // New playlist row.
            if (_showNewPlaylist)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AfSpacing.gutterGenerous, 0, AfSpacing.gutterGenerous, AfSpacing.s8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _newNameCtl,
                        autofocus: true,
                        decoration: const InputDecoration(hintText: 'Playlist name'),
                        onSubmitted: (_) => _createAndAdd(),
                      ),
                    ),
                    const SizedBox(width: AfSpacing.s8),
                    TextButton(
                      onPressed: _saving ? null : _createAndAdd,
                      child: const Text('Create'),
                    ),
                  ],
                ),
              )
            else
              ListTile(
                leading: const Icon(Icons.add_rounded, color: AfColors.indigo300),
                title: Text('New playlist', style: AfTypography.bodyMedium.copyWith(color: AfColors.indigo300)),
                onTap: () => setState(() => _showNewPlaylist = true),
              ),
            // Existing playlists.
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _playlists?.length ?? 0,
                itemBuilder: (context, i) {
                  final p = _playlists![i];
                  return ListTile(
                    leading: const Icon(Icons.playlist_play_rounded, color: AfColors.indigo300),
                    title: Text(p.name, style: AfTypography.bodyMedium),
                    subtitle: Text(p.trackCountLabel,
                        style: AfTypography.bodySmall.copyWith(color: AfColors.textTertiary)),
                    onTap: _saving ? null : () => _addTo(p),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: AfSpacing.s12),
        ],
      ),
    );
  }
}
