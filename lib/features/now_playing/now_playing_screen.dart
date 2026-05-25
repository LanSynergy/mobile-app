import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show Loop;

import '../../core/audio/play_actions.dart';
import '../../core/jellyfin/models/items.dart';
import '../../core/jellyfin/models/quality.dart';
import '../../design_tokens/tokens.dart';
import '../../features/sleep_timer/sleep_timer_screen.dart';
import '../../state/providers.dart';
import '../../utils/oklch.dart';
import '../../utils/time_format.dart';
import '../../widgets/artwork.dart';
import '../../widgets/audio_visual_scrubber.dart';
import '../../widgets/af_dialog.dart';
import '../../widgets/press_scale.dart';
import '../../widgets/quality_chip.dart';
import 'sleep_timer_dialog.dart';
import 'utility_row.dart';

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
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_downward_rounded),
            onPressed: () => Navigator.maybePop(context),
          ),
        ),
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
                const UtilityRow(),
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
  const _ReactiveBackground({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spectral = ref.watch(currentSpectralProvider);
    final oklch = srgbToOklch(spectral.energy);
    final background = OklchColor(0.35, 0.12, oklch.h).toColor();
    return AnimatedContainer(
      duration: AfDurations.expressive,
      curve: AfCurves.easeStandard,
      color: background,
      child: child,
    );
  }
}

/// Artwork with sub-bass driven scale pulse.
/// Bin 0 (kick drum / sub-bass) drives a ±8% scale bump via asymmetric lerp.
/// ValueNotifier + Transform.scale — no setState, no rebuild of parent.
class _ReactiveArtwork extends ConsumerStatefulWidget {
  const _ReactiveArtwork({required this.track});
  final AfTrack track;

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
  double _prevBass = 0.0;
  int _cooldown = 0;

  @override
  void initState() {
    super.initState();
    _ticker =
        AnimationController(
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

      _fftSub = ref.read(playerServiceProvider).spectrumStream.listen((frame) {
        if (!mounted) return;
        if (frame.bands.isEmpty) return;

        // Process every frame. At 60 fps input the pulse detector
        // is ~0.1 μs/frame (7-band sum + compare) — negligible.

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
        _bassAverage +=
            (rawBass - _bassAverage) * (rawBass < _bassAverage ? 0.12 : 0.03);

        // Transient detection — tuned for the wide 140 dB spectrum
        // range (-105..+35 dB). At that range a perceptually obvious
        // 10 dB kick only yields ~1.13× in normalised [0,1] space,
        // so the old 1.5× ratio was unreachable. Fire on either a
        // ratio spike (1.12×) or a sharp frame-to-frame delta (0.04).
        if (_cooldown > 0) {
          _cooldown--;
        } else if ((rawBass > _bassAverage * 1.12 || delta > 0.04) &&
            rawBass > 0.015) {
          _scale.value = 1.06; // +6% bump
          _cooldown = 15; // ~250ms lockout at 60 fps
          if (!_ticker.isAnimating) _ticker.repeat();
        }

        _silenceTimer?.cancel();
        if (mounted) {
          _silenceTimer = Timer(const Duration(milliseconds: 300), () {
            if (mounted) {
              _bassAverage = 0.0;
              _prevBass = 0.0;
            }
          });
        }
      });
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
  const _MetadataRow({required this.track});
  final AfTrack track;

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
              _MarqueeText(text: track.title, style: AfTypography.titleLarge),
              const SizedBox(height: 2),
              // Tap the artist name to jump to the artist. Mirrors the
              // album-label affordance in the top bar.
              InkWell(
                borderRadius: AfRadii.borderSm,
                onTap: track.artistId == null
                    ? null
                    : () => context.push('/artist/${track.artistId}'),
                child: Semantics(
                  label: track.artistId == null
                      ? null
                      : 'Go to artist ${track.artistName}',
                  button: track.artistId != null,
                  child: _MarqueeText(
                    text: track.artistName,
                    style: AfTypography.bodyMedium.copyWith(
                      color: AfColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: Icon(
            track.isFavorite ? LucideIcons.heart : LucideIcons.heart,
            color: track.isFavorite
                ? AfColors.semanticError
                : AfColors.textPrimary,
            size: 24,
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
        _NowPlayingMetaChip(quality: track.quality),
      ],
    );
  }
}

/// Scrolls [text] from right to left when it exceeds the available width.
/// Falls back to a static [Text] when the content fits.
/// Scrolls [text] from right to left when it exceeds the available width.
/// Uses [ClipRect] + [SizedBox] to constrain parent layout — unlike
/// [OverflowBox] which can break parent Row sizing.
class _MarqueeText extends StatefulWidget {
  const _MarqueeText({required this.text, required this.style});
  final String text;
  final TextStyle style;

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  double _offset = 0.0;
  bool _shouldScroll = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void didUpdateWidget(covariant _MarqueeText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _controller.stop();
      _controller.value = 0;
      _shouldScroll = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final tp = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout();

        if (tp.width <= maxWidth) {
          if (_shouldScroll) {
            _controller.stop();
            _controller.value = 0;
            _shouldScroll = false;
          }
          return Text(widget.text, maxLines: 1, style: widget.style);
        }

        if (!_shouldScroll) {
          _shouldScroll = true;
          _offset = tp.width + 32.0;
          final durationMs = (_offset / 30.0 * 1000).round().clamp(4000, 20000);
          _controller.duration = Duration(milliseconds: durationMs);
          _controller.repeat();
        }

        return ClipRect(
          child: SizedBox(
            width: maxWidth,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    return Transform.translate(
                      offset: Offset(-_offset * _controller.value, 0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(widget.text, maxLines: 1, style: widget.style),
                          const SizedBox(width: 32),
                          Text(widget.text, maxLines: 1, style: widget.style),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
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
        loopA == null ? LucideIcons.arrowLeftRight : LucideIcons.flag,
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
              ..showSnackBar(
                const SnackBar(
                  content: Text('Loop start set — tap again for end'),
                  duration: Duration(seconds: 2),
                ),
              );
          }
        } else if (loopB == null) {
          // Set B marker
          await svc.setAbLoopB(pos);
          ref.read(abLoopBProvider.notifier).state = pos;
          if (context.mounted) {
            ScaffoldMessenger.of(context)
              ..clearSnackBars()
              ..showSnackBar(
                const SnackBar(
                  content: Text('A-B loop active — tap to clear'),
                  duration: Duration(seconds: 2),
                ),
              );
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
              ..showSnackBar(
                const SnackBar(
                  content: Text('A-B loop cleared'),
                  duration: Duration(seconds: 1),
                ),
              );
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
  const _ReactiveProgress({required this.track});
  final AfTrack track;

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
    final displayProgress = _isDragging
        ? (_scrubPreview ?? engineProgress)
        : engineProgress;

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
            onScrubEnd: (p) async {
              final newPos = Duration(
                milliseconds: (p * duration.inMilliseconds).round(),
              );
              final svc = ref.read(playerServiceProvider);
              // Detect "seek after track completed" scenario:
              // when the queue ended, _userPaused=true and player is stopped.
              // Seeking alone won't resume — we need to call play() as well.
              final wasCompletedAtEnd = svc.isCompleted && svc.isUserPaused;
              try {
                await svc.seek(newPos).timeout(const Duration(seconds: 2));
                // Resume playback only when the user seeks into a completed track.
                if (wasCompletedAtEnd && mounted) {
                  await svc.play().timeout(const Duration(seconds: 2));
                }
              } catch (_) {
                // Timeout or seek error — still release the drag lock.
              }
              if (mounted) {
                setState(() {
                  _isDragging = false;
                  _scrubPreview = null;
                });
              }
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
                style: AfTypography.mono.copyWith(color: AfColors.textTertiary),
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
  const _ReactiveTransport({required this.track});
  final AfTrack track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPlaying = ref
        .watch(playingStreamProvider)
        .maybeWhen(data: (v) => v, orElse: () => false);
    final shuffleOn = ref
        .watch(shuffleModeProvider)
        .maybeWhen(data: (v) => v, orElse: () => false);
    final loopMode = ref
        .watch(loopModeProvider)
        .maybeWhen(data: (v) => v, orElse: () => Loop.off);
    final spectral = ref.watch(currentSpectralProvider);

    return _TransportRow(
      isPlaying: isPlaying,
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
          Loop.off => Loop.playlist,
          Loop.playlist => Loop.file,
          Loop.file => Loop.off,
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
  const _TopBar({required this.track});
  final AfTrack track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: AfColors.surfaceCanvas.withValues(alpha: 0.20),
            borderRadius: AfRadii.borderPill,
          ),
          margin: const EdgeInsets.symmetric(
            horizontal: AfSpacing.s8,
            vertical: 4,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AfSpacing.s8,
            vertical: 4,
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(
                  LucideIcons.chevronDown,
                  color: AfColors.textPrimary,
                  size: 24,
                ),
                onPressed: () => Navigator.maybePop(context),
              ),
              Expanded(
                // Tap the album label to jump to the album. Faster than
                // ⋯ → Go to album. The popup menu still offers the same
                // action for users who go looking for it there.
                child: InkWell(
                  borderRadius: AfRadii.borderSm,
                  onTap: track.albumId == null
                      ? null
                      : () => context.push('/album/${track.albumId}'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
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
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              PopupMenuButton<_NowPlayingAction>(
                icon: const Icon(
                  LucideIcons.ellipsis,
                  color: AfColors.textPrimary,
                  size: 24,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
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
                      leading: Icon(
                        LucideIcons.radio,
                        color: AfColors.textSecondary,
                        size: 24,
                      ),
                      title: Text('Start radio'),
                      subtitle: Text('Similar songs from your library'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  if (track.albumId != null)
                    const PopupMenuItem(
                      value: _NowPlayingAction.goToAlbum,
                      child: ListTile(
                        leading: Icon(
                          LucideIcons.disc3,
                          color: AfColors.textSecondary,
                          size: 24,
                        ),
                        title: Text('Go to album'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  if (track.artistId != null)
                    const PopupMenuItem(
                      value: _NowPlayingAction.goToArtist,
                      child: ListTile(
                        leading: Icon(
                          LucideIcons.user,
                          color: AfColors.textSecondary,
                          size: 24,
                        ),
                        title: Text('Go to artist'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _NowPlayingAction { startRadio, goToAlbum, goToArtist }

/// Combined chip rendered in the Now Playing metadata row (right of the
/// favorite + A-B-loop buttons). Replaces the old _SleepTimerBadge that
/// lived next to the ⋯ menu in the top bar — the chip slot is unified so
/// the header stays compact and the metadata row only ever shows one chip.
///
/// Visual modes:
///   • Sleep timer armed → bedtime icon + remaining time (or just the icon
///     for end-of-track timers). Tapping opens the sleep timer dialog so
///     the user can adjust or cancel without diving into the More sheet.
///   • Sleep timer off → [QualityChip] for the current track (FLAC, bit
///     depth, sample rate). The chip's warning border still surfaces
///     transcode / degradation.
///   • Neither (no timer + no quality info) → empty.
class _NowPlayingMetaChip extends ConsumerWidget {
  const _NowPlayingMetaChip({required this.quality});
  final TrackQuality? quality;

  static String _formatRemaining(Duration d) {
    if (d.isNegative) return '0:00';
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
    if (active != null) {
      final remaining = ref.watch(sleepTimerRemainingProvider);
      return Material(
        color: AfColors.surfaceHigh,
        shape: const RoundedRectangleBorder(borderRadius: AfRadii.borderPill),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            showBlurDialog<void>(
              context: context,
              child: const SleepTimerDialogContent(),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AfSpacing.s12,
              vertical: 6,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  LucideIcons.moon,
                  size: 13,
                  color: AfColors.indigo300,
                ),
                if (remaining != null) ...[
                  const SizedBox(width: AfSpacing.s4),
                  Text(
                    _formatRemaining(remaining),
                    style: AfTypography.mono.copyWith(
                      fontSize: 11,
                      color: AfColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }
    if (quality != null) {
      return QualityChip(quality: quality!);
    }
    return const SizedBox.shrink();
  }
}

class _TransportRow extends StatelessWidget {
  const _TransportRow({
    required this.isPlaying,
    required this.shuffleOn,
    required this.loopMode,
    required this.accent,
    required this.onPlayPause,
    required this.onPrev,
    required this.onNext,
    required this.onShuffle,
    required this.onRepeat,
  });
  final bool isPlaying;
  final bool shuffleOn;
  final Loop loopMode;
  final Color accent;
  final VoidCallback onPlayPause;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onShuffle;
  final VoidCallback onRepeat;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: AfRadii.borderPill,
      ),
      child: Row(
        children: [
          const SizedBox(width: 4),
          _TransportButton(
            icon: Icon(
              LucideIcons.shuffle,
              size: 20,
              color: shuffleOn ? accent : AfColors.textTertiary,
            ),
            onTap: onShuffle,
          ),
          const Spacer(),
          _TransportButton(
            icon: const Icon(
              LucideIcons.skipBack,
              size: 24,
              color: AfColors.textPrimary,
            ),
            onTap: onPrev,
          ),
          const SizedBox(width: 12),
          _PlayButton(isPlaying: isPlaying, onTap: onPlayPause),
          const SizedBox(width: 12),
          _TransportButton(
            icon: const Icon(
              LucideIcons.skipForward,
              size: 24,
              color: AfColors.textPrimary,
            ),
            onTap: onNext,
          ),
          const Spacer(),
          _TransportButton(
            icon: Icon(
              loopMode == Loop.file ? LucideIcons.repeat1 : LucideIcons.repeat,
              size: 20,
              color: loopMode == Loop.off ? AfColors.textTertiary : accent,
            ),
            onTap: onRepeat,
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _TransportButton extends StatelessWidget {
  const _TransportButton({required this.icon, required this.onTap});
  final Widget icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: SizedBox(width: 44, height: 44, child: Center(child: icon)),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.isPlaying, required this.onTap});
  final bool isPlaying;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      ensureHitTarget: false,
      onTap: onTap,
      child: Container(
        width: 60,
        height: 60,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Icon(
            isPlaying ? LucideIcons.pause : LucideIcons.play,
            color: Colors.black,
            size: 28,
          ),
        ),
      ),
    );
  }
}
