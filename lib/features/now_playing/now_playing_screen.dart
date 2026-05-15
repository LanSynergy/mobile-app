import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart'
    show
        AcompressorSettings,
        AexciterSettings,
        AgateSettings,
        AudioEffects,
        BassSettings,
        CrossfeedSettings,
        CrystalizerSettings,
        DeesserSettings,
        Device,
        LoudnormSettings,
        Loop,
        RubberbandSettings,
        StereowidenSettings,
        SuperequalizerSettings,
        TrebleSettings,
        VirtualbassSettings;

import '../../core/audio/play_actions.dart';
import '../../core/backend/music_backend.dart';
import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../features/sleep_timer/sleep_timer_screen.dart';
import '../../state/providers.dart';
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
      body: _ReactiveBackground(
        child: SafeArea(
          child: Column(
            children: [
              _TopBar(track: track),
              Expanded(
                child: CustomScrollView(
                  physics: const ClampingScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AfSpacing.gutterGenerous,
                      ),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          const SizedBox(height: AfSpacing.s24),
                          _ReactiveArtwork(track: track),
                          const SizedBox(height: AfSpacing.s24),
                          _MetadataRow(track: track),
                          const SizedBox(height: AfSpacing.s16),
                          _ReactiveProgress(track: track),
                          const SizedBox(height: AfSpacing.s24),
                          _ReactiveTransport(track: track),
                          const SizedBox(height: AfSpacing.s32),
                          const _UtilityRow(),
                          const SizedBox(height: AfSpacing.s24),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
            ],
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

          // Track running bass baseline.
          _bassAverage += (rawBass - _bassAverage) * 0.05;

          // Transient detection: fire only when bass spikes above baseline.
          if (_cooldown > 0) {
            _cooldown--;
          } else if (rawBass > _bassAverage * 1.5 && rawBass > 0.02) {
            _scale.value = 1.06;  // +6% bump
            _cooldown    = 15;    // ~250ms lockout prevents chatter
            if (!_ticker.isAnimating) _ticker.repeat();
          }

          _silenceTimer = Timer(const Duration(milliseconds: 300), () {
            if (mounted) _bassAverage = 0.0;
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
    return ValueListenableBuilder<double>(
      valueListenable: _scale,
      builder: (context, scaleVal, child) => Transform.scale(
        scale: scaleVal,
        alignment: Alignment.center,
        child: child,
      ),
      child: Center(
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
              size: 240,
              radius: AfRadii.borderLg,
            ),
          ),
        ),
      ),
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
          onPressed: () => ref.read(favoriteToggleProvider)(track),
        ),
        if (track.quality != null) QualityChip(quality: track.quality!),
      ],
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
  Widget build(BuildContext context) {
    final positionAsync = ref.watch(positionStreamProvider);
    final position = positionAsync.maybeWhen(
      data: (p) => p,
      orElse: () => Duration.zero,
    );
    final spectral = ref.watch(currentSpectralProvider);
    final duration = widget.track.duration;

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
              // hand control back to the stream.
              ref.read(playerServiceProvider).seek(newPos).then((_) {
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
                icon: Icons.equalizer_rounded,
                label: 'Equalizer & DSP',
                onTap: () {
                  Navigator.of(dialogCtx).pop();
                  _showEqDialog(context, ref);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEqDialog(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AfColors.surfaceBase,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) => _EqDialogContent(
          scrollController: controller,
        ),
      ),
    );
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
// Equalizer & DSP dialog
// ─────────────────────────────────────────────────────────────────────────────

/// ISO 18-band center frequencies for the superequalizer.
const _kEqBands = <String, String>{
  '1b': '65 Hz',
  '2b': '92 Hz',
  '3b': '131 Hz',
  '4b': '185 Hz',
  '5b': '262 Hz',
  '6b': '370 Hz',
  '7b': '523 Hz',
  '8b': '740 Hz',
  '9b': '1.0 kHz',
  '10b': '1.5 kHz',
  '11b': '2.1 kHz',
  '12b': '2.9 kHz',
  '13b': '4.2 kHz',
  '14b': '5.9 kHz',
  '15b': '8.3 kHz',
  '16b': '11.8 kHz',
  '17b': '16.7 kHz',
  '18b': '20 kHz',
};

class _EqDialogContent extends ConsumerStatefulWidget {
  const _EqDialogContent({required this.scrollController});
  final ScrollController scrollController;

  @override
  ConsumerState<_EqDialogContent> createState() => _EqDialogContentState();
}

class _EqDialogContentState extends ConsumerState<_EqDialogContent> {
  // ── Tone ──
  double _bass = 0.0;
  double _treble = 0.0;

  // ── Dynamics ──
  bool _loudnorm = false;
  bool _compressor = false;

  // ── 18-band EQ (linear gain; 1.0 = flat, range 0–20) ──
  bool _eqEnabled = false;
  final Map<String, double> _eqBands = {
    for (final k in _kEqBands.keys) k: 1.0,
  };

  // ── Pitch & tempo ──
  bool _rubberbandEnabled = false;
  double _pitch = 1.0;
  double _tempo = 1.0;

  // ── Spatial ──
  bool _crossfeed = false;
  double _crossfeedStrength = 0.2;
  bool _stereoWiden = false;
  double _stereoWidenDelay = 20.0;

  // ── Creative ──
  bool _exciter = false;
  double _exciterAmount = 1.0;
  bool _crystalizer = false;
  double _crystalizerIntensity = 2.0;
  bool _virtualBass = false;
  double _virtualBassCutoff = 250.0;

  // ── Cleanup ──
  bool _gate = false;
  bool _deesser = false;

  @override
  void initState() {
    super.initState();
    final fx = ref.read(playerServiceProvider).audioEffects;
    _bass = fx.bass.g;
    _treble = fx.treble.g;
    _loudnorm = fx.loudnorm.enabled;
    _compressor = fx.acompressor.enabled;
    _eqEnabled = fx.superequalizer.enabled;
    for (final entry in fx.superequalizer.params.entries) {
      if (_eqBands.containsKey(entry.key)) {
        _eqBands[entry.key] = entry.value;
      }
    }
    _rubberbandEnabled = fx.rubberband.enabled;
    _pitch = fx.rubberband.pitch;
    _tempo = fx.rubberband.tempo;
    _crossfeed = fx.crossfeed.enabled;
    _crossfeedStrength = fx.crossfeed.strength;
    _stereoWiden = fx.stereowiden.enabled;
    _stereoWidenDelay = fx.stereowiden.delay;
    _exciter = fx.aexciter.enabled;
    _exciterAmount = fx.aexciter.amount;
    _crystalizer = fx.crystalizer.enabled;
    _crystalizerIntensity = fx.crystalizer.i.clamp(-10.0, 10.0);
    _virtualBass = fx.virtualbass.enabled;
    _virtualBassCutoff = fx.virtualbass.cutoff;
    _gate = fx.agate.enabled;
    _deesser = fx.deesser.enabled;
  }

  void _apply() {
    final svc = ref.read(playerServiceProvider);
    unawaited(svc.updateAudioEffects((e) => e.copyWith(
          bass: BassSettings(enabled: _bass != 0, g: _bass),
          treble: TrebleSettings(enabled: _treble != 0, g: _treble),
          loudnorm: LoudnormSettings(enabled: _loudnorm),
          acompressor: AcompressorSettings(
            enabled: _compressor,
            threshold: 0.1,
            ratio: 4.0,
            attack: 20.0,
            release: 250.0,
          ),
          superequalizer: SuperequalizerSettings(
            enabled: _eqEnabled,
            params: _buildEqParams(),
          ),
          rubberband: RubberbandSettings(
            enabled: _rubberbandEnabled,
            pitch: _pitch,
            tempo: _tempo,
          ),
          crossfeed: CrossfeedSettings(
            enabled: _crossfeed,
            strength: _crossfeedStrength,
          ),
          stereowiden: StereowidenSettings(
            enabled: _stereoWiden,
            delay: _stereoWidenDelay,
          ),
          aexciter: AexciterSettings(
            enabled: _exciter,
            amount: _exciterAmount,
          ),
          crystalizer: CrystalizerSettings(
            enabled: _crystalizer,
            i: _crystalizerIntensity,
          ),
          virtualbass: VirtualbassSettings(
            enabled: _virtualBass,
            cutoff: _virtualBassCutoff,
          ),
          agate: AgateSettings(enabled: _gate),
          deesser: DeesserSettings(enabled: _deesser),
        )));
  }

  void _resetAll() {
    setState(() {
      _bass = 0;
      _treble = 0;
      _loudnorm = false;
      _compressor = false;
      _eqEnabled = false;
      for (final k in _eqBands.keys) {
        _eqBands[k] = 1.0;
      }
      _rubberbandEnabled = false;
      _pitch = 1.0;
      _tempo = 1.0;
      _crossfeed = false;
      _crossfeedStrength = 0.2;
      _stereoWiden = false;
      _stereoWidenDelay = 20.0;
      _exciter = false;
      _exciterAmount = 1.0;
      _crystalizer = false;
      _crystalizerIntensity = 2.0;
      _virtualBass = false;
      _virtualBassCutoff = 250.0;
      _gate = false;
      _deesser = false;
    });
    unawaited(ref
        .read(playerServiceProvider)
        .setAudioEffects(const AudioEffects()));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.all(AfSpacing.gutterGenerous),
      children: [
        // Drag handle.
        Center(
          child: Container(
            width: 32,
            height: 4,
            margin: const EdgeInsets.only(bottom: AfSpacing.s16),
            decoration: BoxDecoration(
              color: AfColors.textTertiary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Row(
          children: [
            Text('Equalizer & DSP', style: AfTypography.titleSmall),
            const Spacer(),
            TextButton(
              onPressed: _resetAll,
              child: Text(
                'Reset all',
                style: AfTypography.bodySmall
                    .copyWith(color: AfColors.semanticError),
              ),
            ),
          ],
        ),
        const SizedBox(height: AfSpacing.s16),

        // ── Tone shelves ───────────────────────────────────────────────
        _sectionHeader('Tone'),
        _sliderRow('Bass', _bass, -12, 12, 24, (v) {
          setState(() => _bass = v);
        }, _apply, suffix: 'dB'),
        _sliderRow('Treble', _treble, -12, 12, 24, (v) {
          setState(() => _treble = v);
        }, _apply, suffix: 'dB'),

        _divider(),

        // ── 18-band graphic EQ ─────────────────────────────────────────
        _sectionHeader('18-band Equalizer'),
        SwitchListTile.adaptive(
          value: _eqEnabled,
          onChanged: (v) {
            setState(() => _eqEnabled = v);
            _apply();
          },
          title: Text('Enable graphic EQ', style: AfTypography.bodyMedium),
          activeThumbColor: AfColors.indigo500,
          contentPadding: EdgeInsets.zero,
        ),
        if (_eqEnabled) ..._buildEqBands(),
        if (_eqEnabled)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                setState(() {
                  for (final k in _eqBands.keys) {
                    _eqBands[k] = 1.0;
                  }
                });
                _apply();
              },
              child: Text(
                'Flatten EQ',
                style: AfTypography.bodySmall
                    .copyWith(color: AfColors.textTertiary),
              ),
            ),
          ),

        _divider(),

        // ── Dynamics ───────────────────────────────────────────────────
        _sectionHeader('Dynamics'),
        _toggleTile('Loudness normalization', 'EBU R128 (-16 LUFS)',
            _loudnorm, (v) {
          setState(() => _loudnorm = v);
          _apply();
        }),
        _toggleTile(
            'Dynamic compressor', 'Reduces volume spikes', _compressor, (v) {
          setState(() => _compressor = v);
          _apply();
        }),
        _toggleTile('Noise gate', 'Silences signal below threshold', _gate,
            (v) {
          setState(() => _gate = v);
          _apply();
        }),
        _toggleTile('De-esser', 'Reduces sibilance', _deesser, (v) {
          setState(() => _deesser = v);
          _apply();
        }),

        _divider(),

        // ── Pitch & tempo ──────────────────────────────────────────────
        _sectionHeader('Pitch & Tempo'),
        SwitchListTile.adaptive(
          value: _rubberbandEnabled,
          onChanged: (v) {
            setState(() => _rubberbandEnabled = v);
            _apply();
          },
          title:
              Text('Enable pitch/tempo shift', style: AfTypography.bodyMedium),
          subtitle: Text(
            'High-quality rubberband engine',
            style: AfTypography.bodySmall
                .copyWith(color: AfColors.textTertiary),
          ),
          activeThumbColor: AfColors.indigo500,
          contentPadding: EdgeInsets.zero,
        ),
        if (_rubberbandEnabled) ...[
          _sliderRow(
            'Pitch',
            _pitch,
            0.5,
            2.0,
            30,
            (v) => setState(() => _pitch = v),
            _apply,
            suffix: '×',
            precision: 2,
          ),
          _sliderRow(
            'Tempo',
            _tempo,
            0.5,
            2.0,
            30,
            (v) => setState(() => _tempo = v),
            _apply,
            suffix: '×',
            precision: 2,
          ),
        ],

        _divider(),

        // ── Spatial ────────────────────────────────────────────────────
        _sectionHeader('Spatial'),
        SwitchListTile.adaptive(
          value: _crossfeed,
          onChanged: (v) {
            setState(() => _crossfeed = v);
            _apply();
          },
          title: Text('Crossfeed', style: AfTypography.bodyMedium),
          subtitle: Text(
            'Headphone crossfeed for natural imaging',
            style: AfTypography.bodySmall
                .copyWith(color: AfColors.textTertiary),
          ),
          activeThumbColor: AfColors.indigo500,
          contentPadding: EdgeInsets.zero,
        ),
        if (_crossfeed)
          _sliderRow(
            'Strength',
            _crossfeedStrength,
            0.0,
            1.0,
            20,
            (v) => setState(() => _crossfeedStrength = v),
            _apply,
            precision: 2,
          ),
        SwitchListTile.adaptive(
          value: _stereoWiden,
          onChanged: (v) {
            setState(() => _stereoWiden = v);
            _apply();
          },
          title: Text('Stereo widening', style: AfTypography.bodyMedium),
          subtitle: Text(
            'Expands stereo image',
            style: AfTypography.bodySmall
                .copyWith(color: AfColors.textTertiary),
          ),
          activeThumbColor: AfColors.indigo500,
          contentPadding: EdgeInsets.zero,
        ),
        if (_stereoWiden)
          _sliderRow(
            'Delay',
            _stereoWidenDelay,
            1.0,
            100.0,
            99,
            (v) => setState(() => _stereoWidenDelay = v),
            _apply,
            suffix: 'ms',
            precision: 0,
          ),

        _divider(),

        // ── Creative ───────────────────────────────────────────────────
        _sectionHeader('Creative'),
        SwitchListTile.adaptive(
          value: _exciter,
          onChanged: (v) {
            setState(() => _exciter = v);
            _apply();
          },
          title: Text('Harmonic exciter', style: AfTypography.bodyMedium),
          subtitle: Text(
            'Adds harmonic overtones',
            style: AfTypography.bodySmall
                .copyWith(color: AfColors.textTertiary),
          ),
          activeThumbColor: AfColors.indigo500,
          contentPadding: EdgeInsets.zero,
        ),
        if (_exciter)
          _sliderRow(
            'Amount',
            _exciterAmount,
            0.0,
            10.0,
            20,
            (v) => setState(() => _exciterAmount = v),
            _apply,
            precision: 1,
          ),
        SwitchListTile.adaptive(
          value: _crystalizer,
          onChanged: (v) {
            setState(() => _crystalizer = v);
            _apply();
          },
          title: Text('Crystalizer', style: AfTypography.bodyMedium),
          subtitle: Text(
            'Audio sharpener / brightener',
            style: AfTypography.bodySmall
                .copyWith(color: AfColors.textTertiary),
          ),
          activeThumbColor: AfColors.indigo500,
          contentPadding: EdgeInsets.zero,
        ),
        if (_crystalizer)
          _sliderRow(
            'Intensity',
            _crystalizerIntensity,
            -10.0,
            10.0,
            40,
            (v) => setState(() => _crystalizerIntensity = v),
            _apply,
            precision: 1,
          ),
        SwitchListTile.adaptive(
          value: _virtualBass,
          onChanged: (v) {
            setState(() => _virtualBass = v);
            _apply();
          },
          title: Text('Virtual bass', style: AfTypography.bodyMedium),
          subtitle: Text(
            'Psychoacoustic bass enhancement',
            style: AfTypography.bodySmall
                .copyWith(color: AfColors.textTertiary),
          ),
          activeThumbColor: AfColors.indigo500,
          contentPadding: EdgeInsets.zero,
        ),
        if (_virtualBass)
          _sliderRow(
            'Cutoff',
            _virtualBassCutoff,
            100.0,
            500.0,
            40,
            (v) => setState(() => _virtualBassCutoff = v),
            _apply,
            suffix: 'Hz',
            precision: 0,
          ),

        const SizedBox(height: AfSpacing.s24),
      ],
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.only(top: AfSpacing.s8, bottom: AfSpacing.s4),
        child: Text(title,
            style: AfTypography.label
                .copyWith(color: AfColors.textSecondary)),
      );

  Widget _divider() => const Padding(
        padding: EdgeInsets.symmetric(vertical: AfSpacing.s8),
        child: Divider(height: 1, color: AfColors.surfaceHigh),
      );

  Widget _toggleTile(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return SwitchListTile.adaptive(
      value: value,
      onChanged: onChanged,
      title: Text(title, style: AfTypography.bodyMedium),
      subtitle: Text(
        subtitle,
        style:
            AfTypography.bodySmall.copyWith(color: AfColors.textTertiary),
      ),
      activeThumbColor: AfColors.indigo500,
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _sliderRow(
    String label,
    double value,
    double min,
    double max,
    int divisions,
    ValueChanged<double> onChanged,
    VoidCallback onChangeEnd, {
    String? suffix,
    int precision = 0,
  }) {
    final display = value >= 0 && suffix == 'dB'
        ? '+${value.toStringAsFixed(precision)}'
        : value.toStringAsFixed(precision);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(label, style: AfTypography.bodyMedium),
            const Spacer(),
            Text(
              suffix != null ? '$display $suffix' : display,
              style:
                  AfTypography.mono.copyWith(color: AfColors.textTertiary),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          activeColor: AfColors.indigo400,
          onChanged: onChanged,
          onChangeEnd: (_) => onChangeEnd(),
        ),
      ],
    );
  }

  /// Only include bands that differ from the flat default (1.0).
  Map<String, double> _buildEqParams() {
    final params = <String, double>{};
    for (final entry in _eqBands.entries) {
      if (entry.value != 1.0) params[entry.key] = entry.value;
    }
    return params;
  }

  List<Widget> _buildEqBands() {
    return _kEqBands.entries.map((entry) {
      final bandKey = entry.key;
      final freq = entry.value;
      final gain = _eqBands[bandKey] ?? 1.0;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 58,
              child: Text(
                freq,
                style: AfTypography.mono.copyWith(
                  fontSize: 11,
                  color: AfColors.textTertiary,
                ),
              ),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 12),
                ),
                child: Slider(
                  value: gain.clamp(0.0, 4.0),
                  min: 0,
                  max: 4,
                  divisions: 40,
                  activeColor: AfColors.indigo400,
                  onChanged: (v) {
                    setState(() => _eqBands[bandKey] = v);
                  },
                  onChangeEnd: (_) => _apply(),
                ),
              ),
            ),
            SizedBox(
              width: 36,
              child: Text(
                gain.toStringAsFixed(1),
                textAlign: TextAlign.right,
                style: AfTypography.mono.copyWith(
                  fontSize: 11,
                  color: AfColors.textTertiary,
                ),
              ),
            ),
          ],
        ),
      );
    }).toList();
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
          SnackBar(content: Text('Failed: $e')),
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
          SnackBar(content: Text('Failed: $e')),
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
                    subtitle: Text('${p.trackCount} tracks',
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
