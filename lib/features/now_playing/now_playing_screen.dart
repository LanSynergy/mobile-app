import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import 'bottom_content.dart';
import 'empty_state.dart';
import 'reactive_artwork.dart';
import 'reactive_background.dart';
import 'top_bar.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NowPlayingScreen — thin orchestrator
//
// Layout: Full-bleed immersive Stack.
//   Stack(fit: StackFit.expand)
//   ├── ReactiveBackground  (spectral-derived color fill)
//   ├── ReactiveArtwork     (centered card, Hero)
//   ├── Gradient scrim      (bottom 65%: transparent → surfaceCanvas)
//   ├── FrostedTopBar       (top, minimal, expandable lyrics)
//   └── BottomContent       (metadata, scrubber, transport, queue)
//
// High-frequency streams (position, FFT) are isolated to leaf widgets
// so they never trigger rebuilds of the artwork, gradient, or metadata.
// ─────────────────────────────────────────────────────────────────────────────

class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> {
  final _expandedNotifier = ValueNotifier<bool>(false);
  final _lyricsExpandedNotifier = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _expandedNotifier.dispose();
    _lyricsExpandedNotifier.dispose();
    super.dispose();
  }

  /// Collapse queue, then expand lyrics (or toggle if already expanded).
  void _toggleLyrics() {
    if (_expandedNotifier.value) {
      _expandedNotifier.value = false;
    }
    _lyricsExpandedNotifier.value = !_lyricsExpandedNotifier.value;
  }

  @override
  Widget build(BuildContext context) {
    final track = ref.watch(currentTrackProvider);

    if (track == null) {
      return const NowPlayingEmptyState();
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // If the bottom bar is expanded, collapse it instead of popping.
        if (_expandedNotifier.value) {
          _expandedNotifier.value = false;
        } else if (_lyricsExpandedNotifier.value) {
          _lyricsExpandedNotifier.value = false;
        } else {
          Navigator.maybePop(context);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        body: ReactiveBackground(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── Centered artwork card (swipe up to expand queue) ──
              Positioned.fill(
                child: GestureDetector(
                  onVerticalDragEnd: (details) {
                    if ((details.primaryVelocity ?? 0) < -200) {
                      _expandedNotifier.value = true;
                    }
                  },
                  child: ReactiveArtwork(track: track),
                ),
              ),

              // ── Gradient scrim (bottom portion) ──
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: MediaQuery.of(context).size.height * 0.65,
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          AfColors.surfaceCanvas.withValues(alpha: 0.6),
                          AfColors.surfaceCanvas,
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),
                ),
              ),

              // ── Top bar ──
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: FrostedTopBar(
                    track: track,
                    lyricsExpanded: _lyricsExpandedNotifier,
                    onToggleLyrics: _toggleLyrics,
                  ),
                ),
              ),

              // ── Bottom content zone ──
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: BottomContent(
                    track: track,
                    expandedNotifier: _expandedNotifier,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
