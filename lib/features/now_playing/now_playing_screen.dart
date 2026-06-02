import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show Loop;

import '../../core/audio/play_actions.dart';
import '../../core/audio/af_loop_mode.dart';
import '../../core/audio/shuffle_mode.dart';
import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../utils/oklch.dart';
import '../../utils/time_format.dart';
import '../../widgets/audio_visual_scrubber.dart';
import '../../widgets/af_dialog.dart';
import '../../widgets/press_scale.dart';
import '../../widgets/empty_state.dart';
import 'utility_row.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NowPlayingScreen — "Dark Moody" immersive rebuild
//
// Design system: Deep blacks (#0A0A0A), warm amber accents (#D4A574),
//   Playfair Display headlines, Inter body.
//
// Rebuild topology (reactive islands):
//   NowPlayingScreen    watches: currentTrackProvider (changes on skip only)
//   _ReactiveBackground watches: currentSpectralProvider (gradient color)
//   _ReactiveArtwork    watches: currentSpectralProvider + FFT (bass pulse)
//   _ReactiveProgress   watches: positionStreamProvider (high-frequency)
//   _ReactiveTransport  watches: playingStreamProvider, shuffle, loop
//
// High-frequency streams (position, FFT) are isolated to leaf widgets
// so they never trigger rebuilds of the artwork, gradient, or metadata.
//
// Layout: Full-bleed immersive Stack.
//   Stack(fit: StackFit.expand)
//   ├── _ReactiveBackground (spectral-derived color fill)
//   ├── Artwork (Positioned.fill, BoxFit.cover, Hero, bass pulse)
//   ├── Gradient scrim (bottom 65%: transparent → surfaceCanvas)
//   ├── Vignette overlay (depth + edge darkening)
//   ├── _FrostedTopBar (top, minimal)
//   ├── _MetadataOverlay (bottom-left, over artwork)
//   ├── _ReactiveProgress (AudioVisualScrubber)
//   ├── _ReactiveTransport (play/pause/skip/shuffle/repeat)
//   └── UtilityRow (like, lyrics, queue, more)
// ─────────────────────────────────────────────────────────────────────────────

class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(currentTrackProvider);

    if (track == null) {
      return _EmptyState();
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      body: _ReactiveBackground(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Full-bleed artwork ──
            _ReactiveArtwork(track: track),

            // ── Scrim (bottom 65%) — blur, no gradient ──
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: MediaQuery.of(context).size.height * 0.65,
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: ColoredBox(
                    color: AfColors.surfaceCanvas.withValues(alpha: 0.65),
                  ),
                ),
              ),
            ),

            // ── Vignette overlay for depth ──
            const _Vignette(),

            // ── Top bar ──
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: _FrostedTopBar(track: track),
              ),
            ),

            // ── Bottom content zone ──
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(top: false, child: _BottomContent(track: track)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AfColors.surfaceCanvas,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronDown),
          onPressed: () => Navigator.maybePop(context),
        ),
      ),
      body: const EmptyState(
        icon: LucideIcons.music,
        title: 'Nothing playing yet',
        body: 'Start playing to see your music here',
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
    final luminance = background.computeLuminance();
    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: luminance > 0.5
          ? Brightness.dark
          : Brightness.light,
      statusBarBrightness: luminance > 0.5 ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: luminance > 0.5
          ? Brightness.dark
          : Brightness.light,
      systemNavigationBarDividerColor: Colors.transparent,
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: AnimatedContainer(
        duration: AfDurations.expressive,
        curve: AfCurves.easeStandard,
        color: background,
        child: child,
      ),
    );
  }
}

/// Artwork with sub-bass driven scale pulse.
/// Bin 0 (kick drum / sub-bass) drives a ±6% scale bump via asymmetric lerp.
/// ValueNotifier + Transform.scale — no setState, no rebuild of parent.
/// Full-bleed: Positioned.fill + BoxFit.cover.
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
            _scale.value = 1.0 + (_scale.value - 1.0) * 0.85;
          } else {
            _scale.value = 1.0;
            _ticker.stop();
          }
        });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pulseEnabled = ref.read(artworkPulseEnabledProvider);
      if (!pulseEnabled) return;

      _fftSub = ref.read(playerServiceProvider).spectrumStream.listen((frame) {
        if (!mounted) return;
        if (frame.bands.isEmpty) return;

        _silenceTimer?.cancel();

        final int hi = frame.bands.length < 7 ? frame.bands.length : 7;
        double rawBass = 0.0;
        for (var i = 1; i < hi; i++) {
          final v = frame.bands[i].abs();
          if (v > rawBass) rawBass = v;
        }

        final delta = rawBass - _prevBass;
        _prevBass = rawBass;

        _bassAverage +=
            (rawBass - _bassAverage) * (rawBass < _bassAverage ? 0.12 : 0.03);

        if (_cooldown > 0) {
          _cooldown--;
        } else if ((rawBass > _bassAverage * 1.12 || delta > 0.04) &&
            rawBass > 0.015) {
          _scale.value = 1.06;
          _cooldown = 15;
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
    final artworkUri = ref.watch(currentArtworkUriProvider);

    final artworkWidget = Hero(
      tag: 'now-playing-artwork',
      child: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: spectral.glow.withValues(alpha: 0.30),
              blurRadius: 40,
              spreadRadius: 4,
            ),
          ],
        ),
        child: ClipRect(
          child: Image.network(
            artworkUri?.toString() ?? widget.track.imageUrl ?? '',
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          ),
        ),
      ),
    );

    if (!pulseEnabled) {
      return Positioned.fill(child: artworkWidget);
    }

    return Positioned.fill(
      child: ValueListenableBuilder<double>(
        valueListenable: _scale,
        builder: (context, scaleVal, child) => Transform.scale(
          scale: scaleVal,
          alignment: Alignment.center,
          child: child,
        ),
        child: artworkWidget,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Vignette overlay — radial gradient from transparent center to dark edges
// ─────────────────────────────────────────────────────────────────────────────

class _Vignette extends StatelessWidget {
  const _Vignette();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
            child: ColoredBox(
              color: AfColors.surfaceCanvas.withValues(alpha: 0.3),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Frosted top bar — minimal, transparent backdrop
// ─────────────────────────────────────────────────────────────────────────────

class _FrostedTopBar extends ConsumerWidget {
  const _FrostedTopBar({required this.track});
  final AfTrack track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AfSpacing.s16,
        vertical: AfSpacing.s8,
      ),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: AfRadii.borderPill,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
                width: 0.5,
              ),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AfSpacing.s8,
              vertical: AfSpacing.s4,
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(
                    LucideIcons.chevronDown,
                    color: AfColors.textPrimary,
                    size: 22,
                  ),
                  onPressed: () => Navigator.maybePop(context),
                ),
                const SizedBox(width: AfSpacing.s8),
                Expanded(
                  child: InkWell(
                    borderRadius: AfRadii.borderSm,
                    onTap: track.albumId == null
                        ? null
                        : () => context.push('/album/${track.albumId}'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AfSpacing.s4,
                      ),
                      child: Column(
                        children: [
                          Text(
                            'PLAYING FROM ALBUM',
                            style: AfTypography.overline.copyWith(
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
                const SizedBox(width: AfSpacing.s8),
                PopupMenuButton<_NowPlayingAction>(
                  icon: const Icon(
                    LucideIcons.ellipsis,
                    color: AfColors.textPrimary,
                    size: 20,
                  ),
                  shape: const RoundedRectangleBorder(
                    borderRadius: AfRadii.borderLg,
                  ),
                  onSelected: (action) async {
                    switch (action) {
                      case _NowPlayingAction.startRadio:
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Starting Instant Mix…'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                        await ref
                            .read(playActionsProvider)
                            .playInstantMix(track);
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
      ),
    );
  }
}

enum _NowPlayingAction { startRadio, goToAlbum, goToArtist }

// ─────────────────────────────────────────────────────────────────────────────
// Bottom content zone — metadata overlay + controls
// ─────────────────────────────────────────────────────────────────────────────

/// Houses all bottom-aligned content: metadata overlay, visualizer scrubber,
/// transport controls, and utility row. Separated from artwork so the
/// gradient scrim provides enough contrast.
class _BottomContent extends StatelessWidget {
  const _BottomContent({required this.track});
  final AfTrack track;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Metadata overlay (title + artist) ──
        _MetadataOverlay(track: track),
        const SizedBox(height: AfSpacing.s16),

        // ── Visualizer scrubber ──
        _ReactiveProgress(track: track),
        const SizedBox(height: AfSpacing.s8),

        // ── Transport controls ──
        _ReactiveTransport(track: track),
        const SizedBox(height: AfSpacing.s8),

        // ── Utility row ──
        const UtilityRow(),
        const SizedBox(height: AfSpacing.s4),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Metadata overlay — title + artist, bottom-left over artwork
// ─────────────────────────────────────────────────────────────────────────────

class _MetadataOverlay extends ConsumerWidget {
  const _MetadataOverlay({required this.track});
  final AfTrack track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFav = ref.watch(isFavoriteProvider(track.id));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AfSpacing.gutterGenerous),
      child: Row(
        children: [
          // Title + artist
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  track.title,
                  style: AfTypography.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AfSpacing.s4),
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
                    child: Text(
                      track.artistName,
                      style: AfTypography.bodySmall.copyWith(
                        color: AfColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AfSpacing.s12),
          // Heart toggle
          IconButton(
            icon: Icon(
              isFav ? LucideIcons.heart : LucideIcons.heart,
              color: isFav ? AfColors.semanticError : AfColors.textSecondary,
              size: 22,
            ),
            tooltip: isFav ? 'Remove from favorites' : 'Add to favorites',
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
          // Quality badge
          if (track.quality != null)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AfSpacing.s8,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                color: AfColors.accentMuted.withValues(alpha: 0.2),
                borderRadius: AfRadii.borderPill,
              ),
              child: Text(
                track.quality!.chipLabel,
                style: AfTypography.caption.copyWith(
                  color: AfColors.textPrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reactive progress — AudioVisualScrubber integration
// ─────────────────────────────────────────────────────────────────────────────

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
    final isBuffering = ref.watch(isBufferingProvider);
    final duration = mpvDuration > Duration.zero
        ? mpvDuration
        : widget.track.duration;

    final effectivePosition = isBuffering ? Duration.zero : position;

    final engineProgress = duration.inMilliseconds == 0
        ? 0.0
        : (effectivePosition.inMilliseconds / duration.inMilliseconds).clamp(
            0.0,
            1.0,
          );
    final displayProgress = _isDragging
        ? (_scrubPreview ?? engineProgress)
        : engineProgress;

    final displayPosition = _isDragging && _scrubPreview != null
        ? Duration(
            milliseconds: (_scrubPreview! * duration.inMilliseconds).round(),
          )
        : effectivePosition;
    final remaining = duration > displayPosition
        ? duration - displayPosition
        : Duration.zero;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AfSpacing.gutterGenerous),
      child: Column(
        children: [
          AudioVisualScrubber(
            progress: displayProgress,
            playedColor: spectral.energy,
            height: 100.0,
            onScrub: (p) => setState(() {
              _isDragging = true;
              _scrubPreview = p;
            }),
            onScrubEnd: (p) async {
              final newPos = Duration(
                milliseconds: (p * duration.inMilliseconds).round(),
              );
              final svc = ref.read(playerServiceProvider);
              final wasCompletedAtEnd = svc.isCompleted && svc.isUserPaused;
              try {
                await svc.seek(newPos).timeout(const Duration(seconds: 2));
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s4),
            child: Row(
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
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reactive transport — play/pause/skip/shuffle/repeat
// ─────────────────────────────────────────────────────────────────────────────

/// Watches playing/shuffle/loop — rebuilds on transport state changes only.
class _ReactiveTransport extends ConsumerWidget {
  const _ReactiveTransport({required this.track});
  final AfTrack track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPlaying = ref
        .watch(playingStreamProvider)
        .maybeWhen(data: (v) => v, orElse: () => false);
    final shuffleMode = ref
        .watch(shuffleModeProvider)
        .maybeWhen(data: (v) => v, orElse: () => ShuffleMode.off);
    final loopMode = ref
        .watch(loopModeProvider)
        .maybeWhen(data: (v) => v, orElse: () => AfLoopMode.off);
    final spectral = ref.watch(currentSpectralProvider);

    return _TransportRow(
      isPlaying: isPlaying,
      shuffleOn: shuffleMode != ShuffleMode.off,
      shuffleMode: shuffleMode,
      loopMode: loopMode,
      repeatCount: ref.watch(repeatCountProvider),
      accent: spectral.energy,
      onShuffle: () {
        final svc = ref.read(playerServiceProvider);
        unawaited(
          svc.setAfShuffleMode(!svc.isShuffleEnabled).catchError((_) {}),
        );
      },
      onShuffleLongPress: () => _showShuffleOptions(context, ref),
      onRepeat: () {
        final svc = ref.read(playerServiceProvider);
        final currentMode = ref
            .read(loopModeProvider)
            .maybeWhen(data: (v) => v, orElse: () => AfLoopMode.off);
        switch (currentMode) {
          case AfLoopMode.off:
            unawaited(svc.setAfLoopMode(Loop.playlist).catchError((_) {}));
            break;
          case AfLoopMode.playlist:
            unawaited(svc.setAfLoopMode(Loop.file).catchError((_) {}));
            break;
          case AfLoopMode.file:
            ref.read(forNtimesModeProvider.notifier).state = true;
            unawaited(svc.setAfForNtimes(true).catchError((_) {}));
            break;
          case AfLoopMode.forNtimes:
            ref.read(forNtimesModeProvider.notifier).state = false;
            svc.setLoopModeOffSync();
            unawaited(svc.setAfForNtimes(false).catchError((_) {}));
            break;
        }
      },
      onPlayPause: () {
        final svc = ref.read(playerServiceProvider);
        isPlaying ? svc.pause() : svc.play();
      },
      onPrev: () => ref.read(playerServiceProvider).skipToPrevious(),
      onNext: () => ref.read(playerServiceProvider).skipToNext(),
    );
  }

  void _showShuffleOptions(BuildContext context, WidgetRef ref) {
    showBlurDialog(
      context: context,
      builder: (context, dismiss) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Shuffle options', style: AfTypography.titleMedium),
          const SizedBox(height: AfSpacing.s16),
          ListTile(
            leading: const Icon(LucideIcons.shuffle),
            title: const Text('Shuffle all'),
            onTap: () {
              dismiss();
              ref.read(playerServiceProvider).setAfShuffleMode(true);
            },
          ),
          ListTile(
            leading: const Icon(LucideIcons.arrowDownWideNarrow),
            title: const Text('Shuffle next'),
            subtitle: const Text('Only upcoming tracks'),
            onTap: () {
              dismiss();
              ref.read(playerServiceProvider).setAfShuffleTail();
            },
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Transport row
// ─────────────────────────────────────────────────────────────────────────────

class _TransportRow extends StatelessWidget {
  const _TransportRow({
    required this.isPlaying,
    required this.shuffleOn,
    required this.shuffleMode,
    required this.loopMode,
    required this.repeatCount,
    required this.accent,
    required this.onPlayPause,
    required this.onPrev,
    required this.onNext,
    required this.onShuffle,
    required this.onShuffleLongPress,
    required this.onRepeat,
  });
  final bool isPlaying;
  final bool shuffleOn;
  final ShuffleMode shuffleMode;
  final AfLoopMode loopMode;
  final int repeatCount;
  final Color accent;
  final VoidCallback onPlayPause;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onShuffle;
  final VoidCallback onShuffleLongPress;
  final VoidCallback onRepeat;

  static IconData _loopIcon(AfLoopMode mode) {
    return switch (mode) {
      AfLoopMode.file => LucideIcons.repeat1,
      AfLoopMode.playlist => LucideIcons.repeat,
      AfLoopMode.off => LucideIcons.repeat,
      AfLoopMode.forNtimes => LucideIcons.repeat,
    };
  }

  static Color _loopColor(AfLoopMode mode, Color accent) {
    return mode == AfLoopMode.off ? AfColors.textTertiary : accent;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Shuffle
          GestureDetector(
            onLongPress: onShuffleLongPress,
            child: _TransportButton(
              icon: Icon(
                shuffleMode == ShuffleMode.tail
                    ? LucideIcons.arrowDownWideNarrow
                    : LucideIcons.shuffle,
                size: 20,
                color: shuffleOn ? accent : AfColors.textTertiary,
              ),
              onTap: onShuffle,
            ),
          ),
          const SizedBox(width: AfSpacing.s12),
          // Previous
          _TransportButton(
            icon: const Icon(
              LucideIcons.skipBack,
              size: 26,
              color: AfColors.textPrimary,
            ),
            onTap: onPrev,
          ),
          const SizedBox(width: AfSpacing.s16),
          // Play / Pause — spectral glow
          _PlayButton(isPlaying: isPlaying, accent: accent, onTap: onPlayPause),
          const SizedBox(width: AfSpacing.s16),
          // Next
          _TransportButton(
            icon: const Icon(
              LucideIcons.skipForward,
              size: 26,
              color: AfColors.textPrimary,
            ),
            onTap: onNext,
          ),
          const SizedBox(width: AfSpacing.s12),
          // Repeat
          _TransportButton(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  _loopIcon(loopMode),
                  size: 20,
                  color: _loopColor(loopMode, accent),
                ),
                if (loopMode == AfLoopMode.forNtimes)
                  Positioned(
                    right: -6,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: AfColors.indigo400,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$repeatCount',
                        style: AfTypography.caption.copyWith(
                          color: AfColors.textOnPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            onTap: onRepeat,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared transport widgets
// ─────────────────────────────────────────────────────────────────────────────

class _TransportButton extends StatelessWidget {
  const _TransportButton({required this.icon, required this.onTap});
  final Widget icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: SizedBox(
        width: AfSpacing.minHitTarget,
        height: AfSpacing.minHitTarget,
        child: Center(child: icon),
      ),
    );
  }
}

/// Play/pause button with spectral ambient glow.
/// 60dp circle with [accent] background and a pulsing outer glow shadow
/// driven by the spectral energy color.
class _PlayButton extends ConsumerWidget {
  const _PlayButton({
    required this.isPlaying,
    required this.accent,
    required this.onTap,
  });
  final bool isPlaying;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isBuffering = ref.watch(isBufferingProvider);
    return PressScale(
      ensureHitTarget: false,
      onTap: onTap,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: accent,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.40),
              blurRadius: 24,
              spreadRadius: 2,
            ),
            BoxShadow(
              color: accent.withValues(alpha: 0.15),
              blurRadius: 48,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Center(
          child: isBuffering
              ? SizedBox(
                  width: AfSpacing.s24,
                  height: AfSpacing.s24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: _contrastColor(accent),
                  ),
                )
              : Icon(
                  isPlaying ? LucideIcons.pause : LucideIcons.play,
                  color: _contrastColor(accent),
                  size: 28,
                ),
        ),
      ),
    );
  }

  /// Returns black or white depending on the accent color luminance
  /// for maximum contrast on the spectral background.
  static Color _contrastColor(Color accent) {
    return accent.computeLuminance() > 0.45
        ? AfColors.surfaceCanvas
        : AfColors.textOnPrimary;
  }
}
