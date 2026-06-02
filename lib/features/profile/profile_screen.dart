import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/audio/play_actions.dart';
import '../../core/backend/music_backend.dart';
import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/lastfm_stats_providers.dart';
import '../../state/providers.dart';
import '../../utils/display_error.dart';
import '../../widgets/artwork.dart';
import '../../widgets/af_dialog.dart';
import '../../widgets/bottom_sheet.dart';
import '../../widgets/press_scale.dart';
import '../../widgets/section_header.dart';

/// Mockup 09 — Profile.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final name = auth?.userName ?? 'You';
    final serverName = auth?.server.name ?? 'Local library';
    final profilePhoto = ref.watch(profilePhotoProvider);

    final mode = ref.watch(appModeProvider);
    final isLocal = mode == AppMode.local;
    final tracksAsync = isLocal
        ? ref.watch(localTracksProvider)
        : ref.watch(allTracksProvider);
    final albumsAsync = isLocal
        ? ref.watch(localAlbumsProvider)
        : ref.watch(allAlbumsProvider);
    final favAlbumsAsync = ref.watch(favoriteAlbumsProvider);
    final recentAlbumsAsync = ref.watch(recentlyAddedAlbumsProvider);

    String fmtCount<T>(AsyncValue<List<T>> async) =>
        async.maybeWhen(data: (list) => _fmt(list.length), orElse: () => '—');

    // Favourites first, else most-recently-added so the row is never empty.
    final pinned = favAlbumsAsync.maybeWhen(
      data: (favs) => favs.isNotEmpty
          ? favs.take(8).toList()
          : recentAlbumsAsync.maybeWhen(
              data: (recent) => recent.take(8).toList(),
              orElse: () => const <AfAlbum>[],
            ),
      orElse: () => const <AfAlbum>[],
    );

    // Last.fm connection state.
    final lastFmSession = ref.watch(lastfmSessionKeyProvider);
    final lastFmUser = ref.watch(lastfmUsernameProvider);
    final isLastFmConnected = lastFmSession.isNotEmpty && lastFmUser.isNotEmpty;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
        children: [
          const SizedBox(height: AfSpacing.s24),
          Center(
            child: Column(
              children: [
                _AvatarImagePicker(
                  name: name,
                  isUploading: profilePhoto.isUploading,
                  localPath: profilePhoto.localPath,
                  networkUrl: profilePhoto.networkUrl,
                  authHeaders: ref.watch(musicBackendProvider)?.authHeaders,
                  onPickPhoto: (source) async {
                    final picker = ImagePicker();
                    try {
                      final image = await picker.pickImage(
                        source: source,
                        maxWidth: 512,
                        maxHeight: 512,
                        imageQuality: 85,
                      );
                      if (image != null) {
                        final bytes = await image.readAsBytes();
                        final mimeType = image.mimeType ?? 'image/jpeg';
                        await ref
                            .read(profilePhotoProvider.notifier)
                            .updatePhoto(bytes, mimeType);
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Failed to update profile photo: $e'),
                            backgroundColor: AfColors.semanticError,
                          ),
                        );
                      }
                    }
                  },
                  onRemovePhoto: () async {
                    try {
                      await ref
                          .read(profilePhotoProvider.notifier)
                          .removePhoto();
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Failed to remove profile photo: $e'),
                            backgroundColor: AfColors.semanticError,
                          ),
                        );
                      }
                    }
                  },
                ),
                const SizedBox(height: AfSpacing.s12),
                Text(name, style: AfTypography.titleLarge),
                const SizedBox(height: AfSpacing.s2),
                Text(
                  serverName,
                  style: AfTypography.bodySmall.copyWith(
                    color: AfColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AfSpacing.s24),
          Row(
            children: [
              _StatCard(label: 'Tracks', value: fmtCount(tracksAsync)),
              const SizedBox(width: AfSpacing.s12),
              _StatCard(label: 'Albums', value: fmtCount(albumsAsync)),
            ],
          ),
          const SizedBox(height: AfSpacing.s24),
          const SectionHeader(title: 'Pinned', uppercase: true),
          const SizedBox(height: AfSpacing.s8),
          _PinnedRow(albums: pinned),
          const SizedBox(height: AfSpacing.s24),

          // ── Listening Stats Dashboard ──────────────────────────────────────
          const SectionHeader(title: 'Listening Stats', uppercase: true),
          const SizedBox(height: AfSpacing.s12),
          if (!isLastFmConnected) _LastFmConnectionCTA(),
          _StatsDashboard(isLastFmConnected: isLastFmConnected),
          const SizedBox(height: AfSpacing.s24),

          const SectionHeader(title: 'Account', uppercase: true),
          const SizedBox(height: AfSpacing.s8),
          PressScale(
            onTap: () => context.push('/settings'),
            child: const ListTile(
              leading: Icon(LucideIcons.settings),
              title: Text('Settings'),
              tileColor: AfColors.surfaceBase,
              shape: RoundedRectangleBorder(borderRadius: AfRadii.borderMd),
            ),
          ),
          const SizedBox(height: AfSpacing.bottomInsetWithMiniAndNav),
        ],
      ),
    );
  }

  /// Format a count with thousands separators ("2,247").
  String _fmt(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(AfSpacing.s16),
        decoration: const BoxDecoration(
          color: AfColors.surfaceBase,
          borderRadius: AfRadii.borderMd,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: AfTypography.titleLarge),
            const SizedBox(height: AfSpacing.s2),
            Text(
              label,
              style: AfTypography.bodySmall.copyWith(
                color: AfColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PinnedRow extends StatelessWidget {
  const _PinnedRow({required this.albums});
  final List<AfAlbum> albums;

  @override
  Widget build(BuildContext context) {
    if (albums.isEmpty) {
      return SizedBox(
        height: 120,
        child: Center(
          child: Text(
            'Heart an album to pin it here.',
            style: AfTypography.bodySmall.copyWith(
              color: AfColors.textTertiary,
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: albums.length,
        separatorBuilder: (context, index) =>
            const SizedBox(width: AfSpacing.s12),
        itemBuilder: (context, i) {
          final a = albums[i];
          return GestureDetector(
            onTap: () => context.push('/album/${a.id}'),
            child: SizedBox(
              width: 120,
              child: Stack(
                children: [
                  Artwork(url: a.imageUrl, size: 120, radius: AfRadii.borderMd),
                  Positioned.fill(
                    child: Container(
                      decoration: const BoxDecoration(
                        borderRadius: AfRadii.borderMd,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, AfColors.surfaceScrim],
                          stops: [0.5, 1.0],
                        ),
                      ),
                      alignment: Alignment.bottomLeft,
                      padding: const EdgeInsets.all(AfSpacing.s8),
                      child: Text(
                        a.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AfTypography.bodySmall.copyWith(
                          color: AfColors.textOnPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AvatarImagePicker extends StatelessWidget {
  const _AvatarImagePicker({
    required this.name,
    required this.isUploading,
    this.localPath,
    this.networkUrl,
    this.authHeaders,
    required this.onPickPhoto,
    required this.onRemovePhoto,
  });

  final String name;
  final bool isUploading;
  final String? localPath;
  final String? networkUrl;
  final Map<String, String>? authHeaders;
  final ValueChanged<ImageSource> onPickPhoto;
  final VoidCallback onRemovePhoto;

  @override
  Widget build(BuildContext context) {
    final hasPhoto =
        (localPath != null && File(localPath!).existsSync()) ||
        networkUrl != null;

    Widget avatarContent;
    if (localPath != null && File(localPath!).existsSync()) {
      avatarContent = Image.file(
        File(localPath!),
        width: 96,
        height: 96,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _initialsAvatar(),
      );
    } else if (networkUrl != null) {
      avatarContent = CachedNetworkImage(
        imageUrl: networkUrl!,
        httpHeaders: authHeaders,
        width: 96,
        height: 96,
        fit: BoxFit.cover,
        placeholder: (context, url) => _initialsAvatar(),
        errorWidget: (context, url, error) => _initialsAvatar(),
      );
    } else {
      avatarContent = _initialsAvatar();
    }

    return GestureDetector(
      onTap: isUploading
          ? null
          : () {
  showBlurBottomSheet(
    context: context,
    child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: const Icon(
                        LucideIcons.camera,
                        color: AfColors.textPrimary,
                      ),
                      title: Text(
                        'Take Photo',
                        style: AfTypography.bodyMedium.copyWith(
                          color: AfColors.textPrimary,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        onPickPhoto(ImageSource.camera);
                      },
                    ),
                    ListTile(
                      leading: const Icon(
                        LucideIcons.image,
                        color: AfColors.textPrimary,
                      ),
                      title: Text(
                        'Choose from Gallery',
                        style: AfTypography.bodyMedium.copyWith(
                          color: AfColors.textPrimary,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        onPickPhoto(ImageSource.gallery);
                      },
                    ),
                    if (hasPhoto)
                      ListTile(
                        leading: const Icon(
                          LucideIcons.trash2,
                          color: AfColors.semanticError,
                        ),
                        title: Text(
                          'Remove Photo',
                          style: AfTypography.bodyMedium.copyWith(
                            color: AfColors.semanticError,
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          onRemovePhoto();
                        },
                      ),
                    const SizedBox(height: AfSpacing.s12),
                  ],
                ),
              );
            },
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AfColors.accentSecondary, width: 2),
            ),
            child: ClipOval(child: avatarContent),
          ),
          if (!isUploading)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AfColors.accentSecondary,
                ),
                child: const Icon(
                  LucideIcons.camera,
                  size: 14,
                  color: AfColors.textOnPrimary,
                ),
              ),
            ),
          if (isUploading)
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AfColors.surfaceScrim,
                ),
                child: const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AfColors.accentPrimary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _initialsAvatar() {
    return Container(
      width: 96,
      height: 96,
      color: AfColors.accentMuted,
      alignment: Alignment.center,
      child: Text(
        name.isEmpty ? 'A' : name[0].toUpperCase(),
        style: AfTypography.titleLarge.copyWith(
          fontSize: 32,
          color: AfColors.textOnPrimary,
        ),
      ),
    );
  }
}

class _LastFmConnectionCTA extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AfSpacing.s16),
      padding: const EdgeInsets.all(AfSpacing.s16),
      decoration: const BoxDecoration(
        borderRadius: AfRadii.borderMd,
        gradient: LinearGradient(
          colors: [AfColors.accentMuted, AfColors.semanticError],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                LucideIcons.radio,
                color: AfColors.textOnPrimary,
                size: 20,
              ),
              const SizedBox(width: AfSpacing.s8),
              Text(
                'Connect to Last.fm',
                style: AfTypography.titleSmall.copyWith(
                  color: AfColors.textOnPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AfSpacing.s8),
          Text(
            'Sync your listening habits globally, unlock detailed statistics, and get smart recommendations.',
            style: AfTypography.bodySmall.copyWith(
              color: AfColors.textOnPrimary.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: AfSpacing.s12),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AfColors.accentMuted,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => context.push('/settings'),
            child: const Text('Connect now'),
          ),
        ],
      ),
    );
  }
}

class _StatsDashboard extends ConsumerWidget {
  const _StatsDashboard({required this.isLastFmConnected});
  final bool isLastFmConnected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activePeriod = ref.watch(statsPeriodProvider);
    final activeTab = ref.watch(statsTabProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isLastFmConnected) ...[
          // Period Selector
          Row(
            children: [
              _PeriodButton(
                label: '7 Days',
                value: '7day',
                activeValue: activePeriod,
              ),
              const SizedBox(width: AfSpacing.s8),
              _PeriodButton(
                label: '30 Days',
                value: '1month',
                activeValue: activePeriod,
              ),
              const SizedBox(width: AfSpacing.s8),
              _PeriodButton(
                label: 'All Time',
                value: 'overall',
                activeValue: activePeriod,
              ),
            ],
          ),
          const SizedBox(height: AfSpacing.s12),
        ],

        // Tabs Selector (Songs | Artists | Albums)
        Container(
          padding: const EdgeInsets.all(AfSpacing.s2),
          decoration: const BoxDecoration(
            color: AfColors.surfaceBase,
            borderRadius: AfRadii.borderMd,
          ),
          child: Row(
            children: [
              _TabButton(
                label: 'Songs',
                value: 'songs',
                activeValue: activeTab,
              ),
              _TabButton(
                label: 'Artists',
                value: 'artists',
                activeValue: activeTab,
              ),
              _TabButton(
                label: 'Albums',
                value: 'albums',
                activeValue: activeTab,
              ),
            ],
          ),
        ),
        const SizedBox(height: AfSpacing.s12),

        // List render
        _renderActiveList(context, ref, activeTab),
      ],
    );
  }

  Widget _renderActiveList(
    BuildContext context,
    WidgetRef ref,
    String activeTab,
  ) {
    switch (activeTab) {
      case 'songs':
        final songsAsync = ref.watch(topTracksProvider);
        return songsAsync.when(
          loading: _loadingIndicator,
          error: (err, _) => _errorText(err),
          data: (tracks) => _SongsList(tracks: tracks),
        );
      case 'artists':
        final artistsAsync = ref.watch(topArtistsProvider);
        return artistsAsync.when(
          loading: _loadingIndicator,
          error: (err, _) => _errorText(err),
          data: (artists) => _ArtistsList(artists: artists),
        );
      case 'albums':
        final albumsAsync = ref.watch(topAlbumsProvider);
        return albumsAsync.when(
          loading: _loadingIndicator,
          error: (err, _) => _errorText(err),
          data: (albums) => _AlbumsList(albums: albums),
        );
      default:
        return const SizedBox();
    }
  }

  Widget _loadingIndicator() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(AfSpacing.s32),
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AfColors.accentPrimary,
          ),
        ),
      ),
    );
  }

  Widget _errorText(Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AfSpacing.s16),
        child: Text(
          'Failed to load statistics: $error',
          style: AfTypography.bodySmall.copyWith(color: AfColors.semanticError),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _PeriodButton extends ConsumerWidget {
  const _PeriodButton({
    required this.label,
    required this.value,
    required this.activeValue,
  });
  final String label;
  final String value;
  final String activeValue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = value == activeValue;
    return GestureDetector(
      onTap: () => ref.read(statsPeriodProvider.notifier).state = value,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AfColors.accentSecondary : AfColors.surfaceBase,
          borderRadius: AfRadii.borderSm,
        ),
        child: Text(
          label,
          style: AfTypography.bodySmall.copyWith(
            color: active ? AfColors.textOnPrimary : AfColors.textSecondary,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _TabButton extends ConsumerWidget {
  const _TabButton({
    required this.label,
    required this.value,
    required this.activeValue,
  });
  final String label;
  final String value;
  final String activeValue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = value == activeValue;
    return Expanded(
      child: GestureDetector(
        onTap: () => ref.read(statsTabProvider.notifier).state = value,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? AfColors.surfaceHigh : Colors.transparent,
            borderRadius: AfRadii.borderMd,
          ),
          child: Text(
            label,
            style: AfTypography.bodySmall.copyWith(
              color: active ? AfColors.textPrimary : AfColors.textTertiary,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

class _SongsList extends ConsumerWidget {
  const _SongsList({required this.tracks});
  final List<({String artist, String title, int playCount, String? imageUrl})>
  tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tracks.isEmpty) {
      return _emptyState(
        'No history logged yet. Listen to tracks to collect metrics.',
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: tracks.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: AfSpacing.s8),
      itemBuilder: (context, i) {
        final t = tracks[i];
        return ListTile(
          dense: true,
          tileColor: AfColors.surfaceBase,
          shape: const RoundedRectangleBorder(borderRadius: AfRadii.borderSm),
          leading: SizedBox(
            width: 48,
            child: Row(
              children: [
                Text(
                  '${i + 1}',
                  style: AfTypography.bodySmall.copyWith(
                    color: AfColors.textTertiary,
                  ),
                ),
                const Spacer(),
                t.imageUrl != null
                    ? Artwork(
                        url: t.imageUrl,
                        size: 28,
                        radius: AfRadii.borderSm,
                      )
                    : Container(
                        width: 28,
                        height: 28,
                        decoration: const BoxDecoration(
                          color: AfColors.surfaceHigh,
                          borderRadius: AfRadii.borderSm,
                        ),
                        child: const Icon(
                          LucideIcons.music,
                          size: 14,
                          color: AfColors.textTertiary,
                        ),
                      ),
              ],
            ),
          ),
          title: Text(
            t.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AfTypography.bodySmall.copyWith(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            t.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AfTypography.caption.copyWith(color: AfColors.textTertiary),
          ),
          trailing: Text(
            '${t.playCount} plays',
            style: AfTypography.caption.copyWith(color: AfColors.accentPrimary),
          ),
          onTap: () => _playTrackFromStats(context, ref, t.artist, t.title),
        );
      },
    );
  }
}

class _ArtistsList extends ConsumerWidget {
  const _ArtistsList({required this.artists});
  final List<({String artist, int playCount})> artists;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (artists.isEmpty) {
      return _emptyState('No history logged yet.');
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: artists.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: AfSpacing.s8),
      itemBuilder: (context, i) {
        final a = artists[i];
        return ListTile(
          dense: true,
          tileColor: AfColors.surfaceBase,
          shape: const RoundedRectangleBorder(borderRadius: AfRadii.borderSm),
          leading: SizedBox(
            width: 32,
            child: Row(
              children: [
                Text(
                  '${i + 1}',
                  style: AfTypography.bodySmall.copyWith(
                    color: AfColors.textTertiary,
                  ),
                ),
                const Spacer(),
                const Icon(
                  LucideIcons.user,
                  size: 16,
                  color: AfColors.textTertiary,
                ),
              ],
            ),
          ),
          title: Text(
            a.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AfTypography.bodySmall.copyWith(fontWeight: FontWeight.bold),
          ),
          trailing: Text(
            '${a.playCount} plays',
            style: AfTypography.caption.copyWith(color: AfColors.accentPrimary),
          ),
          onTap: () => _navigateToArtistFromStats(context, ref, a.artist),
        );
      },
    );
  }
}

class _AlbumsList extends ConsumerWidget {
  const _AlbumsList({required this.albums});
  final List<({String artist, String album, int playCount, String? imageUrl})>
  albums;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (albums.isEmpty) {
      return _emptyState('No history logged yet.');
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: albums.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: AfSpacing.s8),
      itemBuilder: (context, i) {
        final alb = albums[i];
        return ListTile(
          dense: true,
          tileColor: AfColors.surfaceBase,
          shape: const RoundedRectangleBorder(borderRadius: AfRadii.borderSm),
          leading: SizedBox(
            width: 48,
            child: Row(
              children: [
                Text(
                  '${i + 1}',
                  style: AfTypography.bodySmall.copyWith(
                    color: AfColors.textTertiary,
                  ),
                ),
                const Spacer(),
                alb.imageUrl != null
                    ? Artwork(
                        url: alb.imageUrl,
                        size: 28,
                        radius: AfRadii.borderSm,
                      )
                    : Container(
                        width: 28,
                        height: 28,
                        decoration: const BoxDecoration(
                          color: AfColors.surfaceHigh,
                          borderRadius: AfRadii.borderSm,
                        ),
                        child: const Icon(
                          LucideIcons.disc,
                          size: 14,
                          color: AfColors.textTertiary,
                        ),
                      ),
              ],
            ),
          ),
          title: Text(
            alb.album,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AfTypography.bodySmall.copyWith(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            alb.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AfTypography.caption.copyWith(color: AfColors.textTertiary),
          ),
          trailing: Text(
            '${alb.playCount} plays',
            style: AfTypography.caption.copyWith(color: AfColors.accentPrimary),
          ),
          onTap: () =>
              _navigateToAlbumFromStats(context, ref, alb.artist, alb.album),
        );
      },
    );
  }
}

Widget _emptyState(String text) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AfSpacing.s24,
        horizontal: AfSpacing.s16,
      ),
      child: Text(
        text,
        style: AfTypography.bodySmall.copyWith(color: AfColors.textTertiary),
        textAlign: TextAlign.center,
      ),
    ),
  );
}

// ── Search/Resolution Helpers ────────────────────────────────────────────────

Future<void> _playTrackFromStats(
  BuildContext context,
  WidgetRef ref,
  String artist,
  String title,
) async {
  unawaited(
    showBlurDialog(
      context: context,
      barrierDismissible: false,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AfColors.accentPrimary,
            ),
          ),
          const SizedBox(width: AfSpacing.s16),
          Text(
            'Locating track in library...',
            style: AfTypography.bodyMedium.copyWith(
              color: AfColors.textPrimary,
            ),
          ),
        ],
      ),
    ),
  );

  try {
    final backend = ref.read(musicBackendProvider);
    if (backend == null) throw Exception('No connected library.');

    AfTrack? resolved;
    if (backend.serverType == ServerType.local) {
      final db = ref.read(localLibraryProvider).db;
      resolved = await db.searchTrackByArtistAndTitle(artist, title);
    } else {
      final results = await backend.search('$artist $title');
      for (final t in results.tracks) {
        if (t.title.toLowerCase() == title.toLowerCase() &&
            t.artistName.toLowerCase() == artist.toLowerCase()) {
          resolved = t;
          break;
        }
      }
      if (resolved == null) {
        for (final t in results.tracks) {
          if (t.title.toLowerCase().contains(title.toLowerCase()) &&
              t.artistName.toLowerCase().contains(artist.toLowerCase())) {
            resolved = t;
            break;
          }
        }
      }
    }

    if (context.mounted) Navigator.pop(context); // Close loading HUD

    if (resolved != null) {
      await ref.read(playActionsProvider).playQueue([resolved], startIndex: 0);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"$title" by $artist is not in your library.'),
          ),
        );
      }
    }
  } catch (e) {
    if (context.mounted) Navigator.pop(context); // Close loading HUD
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to resolve track: ${displayError(e)}')),
      );
    }
  }
}

Future<void> _navigateToArtistFromStats(
  BuildContext context,
  WidgetRef ref,
  String artistName,
) async {
  unawaited(
    showBlurDialog(
      context: context,
      barrierDismissible: false,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AfColors.accentPrimary,
            ),
          ),
          const SizedBox(width: AfSpacing.s16),
          Text(
            'Locating artist...',
            style: AfTypography.bodyMedium.copyWith(
              color: AfColors.textPrimary,
            ),
          ),
        ],
      ),
    ),
  );

  try {
    final backend = ref.read(musicBackendProvider);
    if (backend == null) throw Exception('No connected library.');

    String? artistId;
    if (backend.serverType == ServerType.local) {
      final db = ref.read(localLibraryProvider).db;
      final resolved = await db.artistByName(artistName);
      artistId = resolved?.id;
    } else {
      final results = await backend.search(artistName);
      for (final art in results.artists) {
        if (art.name.toLowerCase() == artistName.toLowerCase()) {
          artistId = art.id;
          break;
        }
      }
    }

    if (context.mounted) Navigator.pop(context); // Close loading HUD

    if (artistId != null) {
      if (context.mounted) unawaited(context.push('/artist/$artistId'));
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Artist "$artistName" not found in library.')),
        );
      }
    }
  } catch (e) {
    if (context.mounted) Navigator.pop(context); // Close loading HUD
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to resolve artist: ${displayError(e)}')),
      );
    }
  }
}

Future<void> _navigateToAlbumFromStats(
  BuildContext context,
  WidgetRef ref,
  String artistName,
  String albumName,
) async {
  unawaited(
    showBlurDialog(
      context: context,
      barrierDismissible: false,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AfColors.accentPrimary,
            ),
          ),
          const SizedBox(width: AfSpacing.s16),
          Text(
            'Locating album...',
            style: AfTypography.bodyMedium.copyWith(
              color: AfColors.textPrimary,
            ),
          ),
        ],
      ),
    ),
  );

  try {
    final backend = ref.read(musicBackendProvider);
    if (backend == null) throw Exception('No connected library.');

    String? albumId;
    if (backend.serverType == ServerType.local) {
      final db = ref.read(localLibraryProvider).db;
      final resolved = await db.albumByKey(albumName, artistName);
      albumId = resolved?.id;
    } else {
      final results = await backend.search('$artistName $albumName');
      for (final alb in results.albums) {
        if (alb.name.toLowerCase() == albumName.toLowerCase() &&
            alb.artistName.toLowerCase() == artistName.toLowerCase()) {
          albumId = alb.id;
          break;
        }
      }
    }

    if (context.mounted) Navigator.pop(context); // Close loading HUD

    if (albumId != null) {
      if (context.mounted) unawaited(context.push('/album/$albumId'));
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Album "$albumName" by $artistName not found in library.',
            ),
          ),
        );
      }
    }
  } catch (e) {
    if (context.mounted) Navigator.pop(context); // Close loading HUD
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to resolve album: ${displayError(e)}')),
      );
    }
  }
}
