import 'dart:io';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../design_tokens/tokens.dart';
import '../../../state/providers.dart';
import '../../../widgets/bottom_sheet.dart';
import '../../../widgets/press_scale.dart';

/// Gradient "Profile" title row with a settings gear button.
class ProfileHeaderTitle extends ConsumerWidget {
  const ProfileHeaderTitle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spectral = ref.watch(
      currentSpectralProvider.select(
        (s) => (primary: s.primary, secondary: s.secondary),
      ),
    );

    return Row(
      children: [
        Expanded(
          child: ShaderMask(
            shaderCallback: (bounds) => LinearGradient(
              colors: [spectral.primary, spectral.secondary],
            ).createShader(bounds),
            child: Text(
              'Profile',
              style: AfTypography.display.copyWith(color: Colors.white),
            ),
          ),
        ),
        PressScale(
          onTap: () => context.push('/settings'),
          child: ClipRRect(
            borderRadius: AfRadii.borderPill,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                padding: const EdgeInsets.all(AfSpacing.s12),
                decoration: BoxDecoration(
                  color: AfColors.glassFill,
                  borderRadius: AfRadii.borderPill,
                  border: Border.all(
                    color: AfColors.glassBorderStrong,
                    width: 1,
                  ),
                ),
                child: const Icon(
                  LucideIcons.settings,
                  color: AfColors.textSecondary,
                  size: 18,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Avatar image picker with spectral glow, user name, and server name.
class ProfileAvatarSection extends ConsumerWidget {
  const ProfileAvatarSection({
    super.key,
    required this.name,
    required this.serverName,
    required this.profilePhoto,
  });

  final String name;
  final String serverName;
  final ({bool isUploading, String? localPath, String? networkUrl})
  profilePhoto;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spectral = ref.watch(
      currentSpectralProvider.select(
        (s) => (primary: s.primary, secondary: s.secondary),
      ),
    );

    return Center(
      child: Column(
        children: [
          // Spectral glow behind avatar
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      spectral.primary.withValues(alpha: 0.25),
                      spectral.primary.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
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
                  } on Exception catch (e) {
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
                    await ref.read(profilePhotoProvider.notifier).removePhoto();
                  } on Exception catch (e) {
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
            ],
          ),
          const SizedBox(height: AfSpacing.s12),
          Text(name, style: AfTypography.titleLarge),
          const SizedBox(height: AfSpacing.s4),
          Text(
            serverName,
            style: AfTypography.bodySmall.copyWith(
              color: AfColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarImagePicker extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final spectral = ref.watch(
      currentSpectralProvider.select(
        (s) => (primary: s.primary, secondary: s.secondary, muted: s.muted),
      ),
    );
    final hasPhoto =
        (localPath != null && File(localPath!).existsSync()) ||
        networkUrl != null;

    Widget avatarContent;
    if (localPath != null && File(localPath!).existsSync()) {
      avatarContent = Image.file(
        File(localPath!),
        width: AfSpacing.avatarSize,
        height: AfSpacing.avatarSize,
        cacheWidth: AfSpacing.avatarSize.toInt(),
        cacheHeight: AfSpacing.avatarSize.toInt(),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            _initialsAvatar(spectral.muted),
      );
    } else if (networkUrl != null) {
      avatarContent = CachedNetworkImage(
        imageUrl: networkUrl!,
        httpHeaders: authHeaders,
        width: AfSpacing.avatarSize,
        height: AfSpacing.avatarSize,
        memCacheWidth: AfSpacing.avatarSize.toInt(),
        memCacheHeight: AfSpacing.avatarSize.toInt(),
        fit: BoxFit.cover,
        placeholder: (context, url) => _initialsAvatar(spectral.muted),
        errorWidget: (context, url, error) => _initialsAvatar(spectral.muted),
      );
    } else {
      avatarContent = _initialsAvatar(spectral.muted);
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
            width: AfSpacing.avatarSize,
            height: AfSpacing.avatarSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: spectral.secondary, width: 2),
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
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: spectral.secondary,
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
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: spectral.primary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _initialsAvatar(Color bgColor) {
    return Container(
      width: AfSpacing.avatarSize,
      height: AfSpacing.avatarSize,
      color: bgColor,
      alignment: Alignment.center,
      child: Text(
        name.isEmpty ? 'A' : name[0].toUpperCase(),
        style: AfTypography.avatarInitials.copyWith(
          color: AfColors.textOnPrimary,
        ),
      ),
    );
  }
}
