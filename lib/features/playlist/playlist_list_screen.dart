import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/skeletons/playlist_skeleton.dart';
import '../../widgets/af_scrollbar.dart';
import 'import_m3u_dialog.dart';

class PlaylistListScreen extends ConsumerWidget {
  const PlaylistListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(allPlaylistsProvider);
    final smartPlaylists = ref.watch(smartPlaylistsProvider);
    final smartCount = smartPlaylists.maybeWhen(
      data: (list) => list.length,
      orElse: () => 0,
    );
    final spectral = ref.watch(currentSpectralProvider);

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(allPlaylistsProvider);
          await ref.read(allPlaylistsProvider.future);
        },
        color: spectral.primary,
        backgroundColor: AfColors.surfaceBase,
        child: AfScrollbar(
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: ClampingScrollPhysics(),
            ),
            slivers: [
              // ── Header ──────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AfSpacing.s16,
                    AfSpacing.s8,
                    AfSpacing.s16,
                    AfSpacing.s16,
                  ),
                  child: Row(
                    children: [
                      Text('Playlists', style: AfTypography.display),
                      const Spacer(),
                      IconButton(
                        icon: Icon(
                          LucideIcons.listPlus,
                          color: spectral.primary,
                          size: 22,
                        ),
                        tooltip: 'Import M3U',
                        onPressed: () => ref
                            .read(importM3UActionProvider)
                            .import(context: context),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Playlist body ───────────────────────────────────────────
              ...playlists.when(
                data: (list) =>
                    _buildSlivers(context, ref, list, smartCount, spectral),
                loading: () => [
                  const SliverToBoxAdapter(child: PlaylistSkeleton()),
                ],
                error: (e, _) => [
                  SliverToBoxAdapter(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AfSpacing.s24),
                        child: Text(
                          'Couldn\u2019t load playlists',
                          style: AfTypography.bodyMedium.copyWith(
                            color: AfColors.semanticError,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SliverToBoxAdapter(
                child: SizedBox(height: AfSpacing.bottomInsetWithMiniAndNav),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSlivers(
    BuildContext context,
    WidgetRef ref,
    List<AfPlaylist> list,
    int smartCount,
    Spectral spectral,
  ) {
    final slivers = <Widget>[];

    // ── Smart playlist shortcut ──────────────────────────────────────────
    if (smartCount > 0) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AfSpacing.s16,
              vertical: AfSpacing.s8,
            ),
            child: Text(
              'Smart Playlists',
              style: AfTypography.label.copyWith(color: AfColors.textTertiary),
            ),
          ),
        ),
      );
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
            child: _PlaylistCard(
              leading: _IconBadge(
                icon: LucideIcons.sparkles,
                tint: spectral.primary,
              ),
              title: 'Smart Playlists',
              subtitle: '$smartCount playlists',
              onTap: () => context.push('/smart-playlists'),
            ),
          ),
        ),
      );
      slivers.add(
        const SliverToBoxAdapter(child: SizedBox(height: AfSpacing.s12)),
      );
    }

    // ── User playlists ───────────────────────────────────────────────────
    if (list.isNotEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AfSpacing.s16,
              vertical: AfSpacing.s8,
            ),
            child: Text(
              'My Playlists',
              style: AfTypography.label.copyWith(color: AfColors.textTertiary),
            ),
          ),
        ),
      );
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
          sliver: SliverList.separated(
            itemCount: list.length,
            separatorBuilder: (context, index) =>
                const SizedBox(height: AfSpacing.s8),
            itemBuilder: (context, i) {
              final p = list[i];
              return _PlaylistCard(
                leading: _IconBadge(
                  icon: LucideIcons.listMusic,
                  tint: spectral.muted,
                ),
                title: p.name,
                subtitle: p.trackCountLabel,
                onTap: () => context.push('/playlist/${p.id}'),
              );
            },
          ),
        ),
      );
    } else {
      // ── Empty state ────────────────────────────────────────────────────
      slivers.add(
        SliverFillRemaining(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: spectral.primary.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    LucideIcons.listMusic,
                    color: spectral.muted,
                    size: 36,
                  ),
                ),
                const SizedBox(height: AfSpacing.s16),
                Text('No playlists yet', style: AfTypography.titleSmall),
                const SizedBox(height: AfSpacing.s4),
                Text(
                  'Create one or import an M3U file',
                  style: AfTypography.bodySmall.copyWith(
                    color: AfColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return slivers;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AfColors.surfaceRaised,
      borderRadius: AfRadii.borderMd,
      child: InkWell(
        borderRadius: AfRadii.borderMd,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AfSpacing.s16,
            vertical: AfSpacing.s12,
          ),
          child: Row(
            children: [
              leading,
              const SizedBox(width: AfSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: AfTypography.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AfSpacing.s2),
                    Text(
                      subtitle,
                      style: AfTypography.bodySmall.copyWith(
                        color: AfColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                LucideIcons.chevronRight,
                color: AfColors.textDisabled,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon, required this.tint});
  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: AfRadii.borderSm,
      ),
      child: Icon(icon, color: tint, size: 20),
    );
  }
}
