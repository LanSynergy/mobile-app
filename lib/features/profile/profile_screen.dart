import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/section_header.dart';

/// Mockup 09 — Profile.
///
/// Per non-negotiable §4.1: shows TRACKS and ALBUMS, never followers.
/// Jellyfin is personal; there is no "follower" concept.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final name = auth?.userName ?? 'You';
    final serverName = auth?.server.name ?? 'Demo library';

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
        children: [
          const SizedBox(height: AfSpacing.s24),
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: AfColors.indigo800,
                  child: Text(
                    name.isEmpty ? 'A' : name[0].toUpperCase(),
                    style: AfTypography.titleLarge.copyWith(
                      color: AfColors.textOnPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: AfSpacing.s12),
                Text(name, style: AfTypography.titleLarge),
                const SizedBox(height: 2),
                Text(
                  serverName,
                  style: AfTypography.bodySmall
                      .copyWith(color: AfColors.textTertiary),
                ),
              ],
            ),
          ),
          const SizedBox(height: AfSpacing.s24),
          Row(
            children: const [
              _StatCard(label: 'Tracks', value: '2,247'),
              SizedBox(width: AfSpacing.s12),
              _StatCard(label: 'Albums', value: '189'),
            ],
          ),
          const SizedBox(height: AfSpacing.s24),
          SectionHeader(title: 'Pinned', uppercase: true),
          const SizedBox(height: AfSpacing.s8),
          const _PinnedRow(),
          const SizedBox(height: AfSpacing.s24),
          SectionHeader(title: 'Public playlists', uppercase: true),
          const SizedBox(height: AfSpacing.s8),
          for (final name in const [
            'Long Drives',
            'Late Night Reading',
            'For the Plane',
          ])
            ListTile(
              leading: const Icon(Icons.playlist_play_rounded,
                  color: AfColors.indigo300),
              title: Text(name),
              subtitle: Text(
                'Updated yesterday',
                style: AfTypography.bodySmall
                    .copyWith(color: AfColors.textTertiary),
              ),
              tileColor: AfColors.surfaceBase,
              shape: const RoundedRectangleBorder(
                  borderRadius: AfRadii.borderMd),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: AfSpacing.s16),
              onTap: () {},
            ),
          const SizedBox(height: AfSpacing.s24),
          SectionHeader(title: 'Account', uppercase: true),
          const SizedBox(height: AfSpacing.s8),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Settings'),
            tileColor: AfColors.surfaceBase,
            shape: const RoundedRectangleBorder(
                borderRadius: AfRadii.borderMd),
            onTap: () => context.push('/settings'),
          ),
          const SizedBox(height: AfSpacing.s8),
          ListTile(
            leading: const Icon(Icons.logout_rounded),
            title: const Text('Sign out'),
            tileColor: AfColors.surfaceBase,
            shape: const RoundedRectangleBorder(
                borderRadius: AfRadii.borderMd),
            onTap: () async {
              await ref.read(authProvider.notifier).clear();
              if (context.mounted) context.go('/');
            },
          ),
          const SizedBox(height: AfSpacing.bottomInsetWithMiniAndNav),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(AfSpacing.s16),
        decoration: BoxDecoration(
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
  const _PinnedRow();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 4,
        separatorBuilder: (_, __) => const SizedBox(width: AfSpacing.s12),
        itemBuilder: (context, i) {
          return Container(
            width: 120,
            decoration: BoxDecoration(
              borderRadius: AfRadii.borderMd,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AfColors.indigo800,
                  Color.lerp(
                          AfColors.indigo800, AfColors.indigo950, i / 4.0)!,
                ],
              ),
            ),
            alignment: Alignment.bottomLeft,
            padding: const EdgeInsets.all(AfSpacing.s12),
            child: Text(
              ['Skylark', 'Field Notes', 'Pinemoth', 'Marrow Bay'][i],
              style: AfTypography.titleSmall.copyWith(
                color: AfColors.textOnPrimary,
              ),
            ),
          );
        },
      ),
    );
  }
}
