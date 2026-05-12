import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart' show Loop;

import '../../core/audio/play_actions.dart';
import '../../core/demo/demo_library.dart';
import '../../core/jellyfin/client.dart';
import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../utils/time_format.dart';
import '../../widgets/beat_pulse_artwork.dart';
import '../../widgets/press_scale.dart';
import '../../widgets/quality_chip.dart';
import '../../widgets/waveform.dart';
/// Mockup 10 — Now Playing.
class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(currentTrackProvider);
    final spectral = ref.watch(currentSpectralProvider);

    if (track == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Nothing playing yet.')),
      );
    }

    final positionAsync = ref.watch(positionStreamProvider);
    final position = positionAsync.maybeWhen(
      data: (p) => p,
      orElse: () => Duration.zero,
    );
    final isPlaying = ref.watch(playingStreamProvider).maybeWhen(
          data: (v) => v,
          orElse: () => false,
        );
    final duration = track.duration;
    final progress = duration.inMilliseconds == 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
    final peaks = track.peaks ?? DemoLibrary.peaksFor(track.id);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AfColors.surfaceCanvas,
              spectral.shadow,
            ],
            stops: const [0.4, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _TopBar(spectral: spectral, track: track),
              Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AfSpacing.gutterGenerous,
                    ),
                    child: Column(
                      children: [
                        const SizedBox(height: AfSpacing.s24),
                        Hero(
                          tag: 'now-playing-artwork',
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: AfRadii.borderLg,
                              boxShadow: [
                                // Tight inner shadow — depth.
                                BoxShadow(
                                  color: spectral.shadow.withValues(alpha: 0.6),
                                  blurRadius: 48,
                                  offset: const Offset(0, 24),
                                ),
                                // Wide ambient glow — spectral color halo.
                                BoxShadow(
                                  color: spectral.energy.withValues(alpha: 0.35),
                                  blurRadius: 72,
                                  spreadRadius: 8,
                                  offset: Offset.zero,
                                ),
                              ],
                            ),
                            child: BeatPulseArtwork(
                              imageUrl: track.imageUrl,
                              size: 320,
                              radius: AfRadii.borderLg,
                            ),
                          ),
                        ),
                        const SizedBox(height: AfSpacing.s24),
                        Row(
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
                                track.isFavorite
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                color: track.isFavorite
                                    ? AfColors.semanticError
                                    : AfColors.textPrimary,
                              ),
                              tooltip: track.isFavorite
                                  ? 'Remove from favorites'
                                  : 'Add to favorites',
                              onPressed: () =>
                                  ref.read(favoriteToggleProvider)(track),
                            ),
                            if (track.quality != null)
                              QualityChip(quality: track.quality!),
                          ],
                        ),
                        const SizedBox(height: AfSpacing.s24),
                        FftWaveform(
                          peaks: peaks,
                          progress: progress,
                          isPlaying: isPlaying,
                          playedColor: spectral.energy,
                          height: 80,
                          onScrub: (p) {
                            final newPos = Duration(
                              milliseconds:
                                  (p * duration.inMilliseconds).round(),
                            );
                            ref.read(playerServiceProvider).seek(newPos);
                          },
                          onScrubEnd: (p) {
                            final newPos = Duration(
                              milliseconds:
                                  (p * duration.inMilliseconds).round(),
                            );
                            ref.read(playerServiceProvider).seek(newPos);
                          },
                        ),
                        const SizedBox(height: AfSpacing.s8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              formatTrackDuration(position),
                              style: AfTypography.mono.copyWith(
                                color: AfColors.textSecondary,
                              ),
                            ),
                            Text(
                              formatRemaining(
                                  duration - position < Duration.zero
                                      ? Duration.zero
                                      : duration - position),
                              style: AfTypography.mono.copyWith(
                                color: AfColors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AfSpacing.s24),
                        _TransportRow(
                          isPlaying: isPlaying,
                          spectral: spectral,
                          shuffleOn: ref
                              .watch(shuffleModeProvider)
                              .maybeWhen(
                                data: (v) => v,
                                orElse: () => false,
                              ),
                          loopMode: ref
                              .watch(loopModeProvider)
                              .maybeWhen(
                                data: (v) => v,
                                orElse: () => Loop.off,
                              ),
                          accent: spectral.energy,
                          onShuffle: () {
                            final svc = ref.read(playerServiceProvider);
                            unawaited(svc.setAfShuffleMode(!svc.isShuffleEnabled));
                          },
                          onRepeat: () {
                            final svc = ref.read(playerServiceProvider);
                            final next = switch (svc.loopMode) {
                              Loop.off => Loop.playlist,
                              Loop.playlist => Loop.file,
                              Loop.file => Loop.off,
                            };
                            unawaited(svc.setAfLoopMode(next));
                          },
                          onPlayPause: () {
                            final svc =
                                ref.read(playerServiceProvider);
                            isPlaying ? svc.pause() : svc.play();
                          },
                          onPrev: () =>
                              ref.read(playerServiceProvider).skipToPrevious(),
                          onNext: () =>
                              ref.read(playerServiceProvider).skipToNext(),
                        ),
                        const SizedBox(height: AfSpacing.s32),
                        const _UtilityRow(),
                        const SizedBox(height: AfSpacing.s24),
                      ],
                    ),
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

class _TopBar extends ConsumerWidget {
  final Spectral spectral;
  final AfTrack track;
  const _TopBar({required this.spectral, required this.track});

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
            // Start radio = Jellyfin Instant Mix off this seed track.
            // Implements the user's "generate queue related song based
            // on the song played" request.
            onSelected: (action) async {
              switch (action) {
                case _NowPlayingAction.startRadio:
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Starting Instant Mix…'),
                      duration: Duration(seconds: 2),
                    ),
                  );
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
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _UtilityIcon(
          icon: Icons.bedtime_outlined,
          label: 'Sleep',
          onTap: () => context.push('/sleep'),
        ),
        _UtilityIcon(
          icon: Icons.lyrics_outlined,
          label: 'Lyrics',
          onTap: () => context.push('/lyrics'),
        ),
        _UtilityIcon(
          icon: Icons.speed_rounded,
          label: 'Speed',
          onTap: () => _showSpeedSheet(context, ref),
        ),
        _UtilityIcon(
          icon: Icons.cast_outlined,
          label: 'Output',
          onTap: () => context.push('/cast'),
        ),
        _UtilityIcon(
          icon: Icons.playlist_add_rounded,
          label: 'Save',
          onTap: () => _showSaveSheet(context, ref),
        ),
        _UtilityIcon(
          icon: Icons.queue_music_rounded,
          label: 'Queue',
          onTap: () => context.push('/queue'),
        ),
      ],
    );
  }

  void _showSaveSheet(BuildContext context, WidgetRef ref) {
    final track = ref.read(currentTrackProvider);
    if (track == null) return;
    final client = ref.read(jellyfinClientProvider);
    if (client == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to save to playlists')),
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AfColors.surfaceBase,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AfRadii.lg)),
      ),
      builder: (sheetCtx) => _SaveToPlaylistSheet(
        track: track,
        client: client,
        onInvalidate: () => ref.invalidate(allPlaylistsProvider),
      ),
    );
  }

  void _showSpeedSheet(BuildContext context, WidgetRef ref) {    const speeds = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
    final current = ref.read(playerServiceProvider).speed;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AfColors.surfaceBase,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AfRadii.lg)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AfSpacing.s12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AfColors.textTertiary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: AfSpacing.s12),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AfSpacing.gutterGenerous,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Playback speed',
                  style: AfTypography.titleSmall,
                ),
              ),
            ),
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
                  Navigator.of(sheetCtx).pop();
                },
              ),
            const SizedBox(height: AfSpacing.s12),
          ],
        ),
      ),
    );
  }
}

class _UtilityIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _UtilityIcon({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PressScale(
      ensureHitTarget: false,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AfSpacing.s8),
        child: Column(
          children: [
            Icon(icon, size: 22, color: AfColors.textSecondary),
            const SizedBox(height: 4),
            Text(
              label,
              style: AfTypography.caption.copyWith(
                color: AfColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Save to playlist sheet
// ─────────────────────────────────────────────────────────────────────────────

class _SaveToPlaylistSheet extends StatefulWidget {
  final AfTrack track;
  final JellyfinClient client;
  final VoidCallback onInvalidate;

  const _SaveToPlaylistSheet({
    required this.track,
    required this.client,
    required this.onInvalidate,
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
    setState(() => _saving = true);
    try {
      await widget.client.addToPlaylist(playlist.id, [widget.track.id]);
      widget.onInvalidate();
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
    final name = _newNameCtl.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.client.createPlaylist(name, [widget.track.id]);
      widget.onInvalidate();
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
