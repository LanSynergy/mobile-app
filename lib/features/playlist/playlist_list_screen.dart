import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/skeletons/playlist_skeleton.dart';
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

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(allPlaylistsProvider);
          await ref.read(allPlaylistsProvider.future);
        },
        color: AfColors.indigo300,
        backgroundColor: AfColors.surfaceBase,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: ClampingScrollPhysics(),
          ),
          slivers: [
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
                    Text('Playlists', style: AfTypography.titleLarge),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(
                        LucideIcons.listPlus,
                        color: AfColors.indigo400,
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
            ...playlists.when(
              data: (list) => _buildSlivers(context, ref, list, smartCount),
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
    );
  }

  List<Widget> _buildSlivers(
    BuildContext context,
    WidgetRef ref,
    List<AfPlaylist> list,
    int smartCount,
  ) {
    final slivers = <Widget>[];

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
              style: AfTypography.titleSmall.copyWith(
                color: AfColors.textTertiary,
              ),
            ),
          ),
        ),
      );
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
            child: ListTile(
              leading: Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  borderRadius: AfRadii.borderSm,
                  color: AfColors.indigo900,
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: AfColors.indigo300,
                ),
              ),
              title: Text('Smart Playlists', style: AfTypography.titleSmall),
              subtitle: Text(
                '$smartCount playlists',
                style: AfTypography.bodySmall.copyWith(
                  color: AfColors.textTertiary,
                ),
              ),
              tileColor: AfColors.surfaceRaised,
              shape: const RoundedRectangleBorder(
                borderRadius: AfRadii.borderMd,
              ),
              onTap: () => context.push('/smart-playlists'),
            ),
          ),
        ),
      );
      slivers.add(
        const SliverToBoxAdapter(child: SizedBox(height: AfSpacing.s12)),
      );
    }

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
              style: AfTypography.titleSmall.copyWith(
                color: AfColors.textTertiary,
              ),
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
              return ListTile(
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                    borderRadius: AfRadii.borderSm,
                    color: AfColors.indigo800,
                  ),
                  child: const Icon(
                    Icons.playlist_play_rounded,
                    color: AfColors.indigo300,
                  ),
                ),
                title: Text(p.name, style: AfTypography.titleSmall),
                subtitle: Text(
                  p.trackCountLabel,
                  style: AfTypography.bodySmall.copyWith(
                    color: AfColors.textTertiary,
                  ),
                ),
                tileColor: AfColors.surfaceRaised,
                shape: const RoundedRectangleBorder(
                  borderRadius: AfRadii.borderMd,
                ),
                onTap: () => context.push('/playlist/${p.id}'),
              );
            },
          ),
        ),
      );
    } else {
      slivers.add(
        SliverFillRemaining(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  LucideIcons.listMusic,
                  color: AfColors.textTertiary,
                  size: 48,
                ),
                const SizedBox(height: AfSpacing.s16),
                Text(
                  'No playlists yet',
                  style: AfTypography.bodyMedium.copyWith(
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
