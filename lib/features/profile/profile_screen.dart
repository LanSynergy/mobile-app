import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/artwork.dart';
import '../../widgets/bottom_sheet.dart';
import '../../widgets/section_header.dart';

/// Mockup 09 — Profile.
///
/// Per non-negotiable §4.1: shows TRACKS and ALBUMS, never followers.
/// Jellyfin is personal; there is no "follower" concept.
///
/// Every section on this screen is now wired to a live Riverpod provider
/// instead of the previous hard-coded ("Skylark / Field Notes / Pinemoth
/// / Marrow Bay") demo strings:
///   • Stats        ← allAlbumsProvider.length + allTracksProvider.length
///   • Pinned       ← favoriteAlbumsProvider (falls back to recently-added)
///   • Playlists    ← allPlaylistsProvider (removed — now in Playlist tab)
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
    // Same provider in both modes — LocalBackend.recentlyAddedAlbums
    // sorts by MAX(last_modified) so this fallback actually surfaces
    // newly-imported music instead of the alphabetically-first album.
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
                const SizedBox(height: 2),
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
          const SectionHeader(title: 'Account', uppercase: true),
          const SizedBox(height: AfSpacing.s8),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Settings'),
            tileColor: AfColors.surfaceBase,
            shape: const RoundedRectangleBorder(borderRadius: AfRadii.borderMd),
            onTap: () => context.push('/settings'),
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
            const SizedBox(height: 2),
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
                      decoration: BoxDecoration(
                        borderRadius: AfRadii.borderMd,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.55),
                          ],
                          stops: const [0.5, 1.0],
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
                builder: (context) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: const Icon(
                        Icons.photo_camera_outlined,
                        color: AfColors.textPrimary,
                      ),
                      title: const Text(
                        'Take Photo',
                        style: TextStyle(color: AfColors.textPrimary),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        onPickPhoto(ImageSource.camera);
                      },
                    ),
                    ListTile(
                      leading: const Icon(
                        Icons.photo_library_outlined,
                        color: AfColors.textPrimary,
                      ),
                      title: const Text(
                        'Choose from Gallery',
                        style: TextStyle(color: AfColors.textPrimary),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        onPickPhoto(ImageSource.gallery);
                      },
                    ),
                    if (hasPhoto)
                      ListTile(
                        leading: const Icon(
                          Icons.delete_outline,
                          color: AfColors.semanticError,
                        ),
                        title: const Text(
                          'Remove Photo',
                          style: TextStyle(color: AfColors.semanticError),
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
              border: Border.all(color: AfColors.indigo600, width: 2),
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
                  color: AfColors.indigo600,
                ),
                child: const Icon(
                  Icons.camera_alt_outlined,
                  size: 14,
                  color: AfColors.textOnPrimary,
                ),
              ),
            ),
          if (isUploading)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.5),
                ),
                child: const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AfColors.indigo300,
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
      color: AfColors.indigo800,
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
