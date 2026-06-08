import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/audio/play_actions.dart';
import '../../../core/jellyfin/models/items.dart';
import '../../../design_tokens/tokens.dart';
import '../../../state/providers.dart';
import '../../../widgets/af_scrollbar.dart';
import '../../../widgets/async_error_view.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/skeletons/library_skeleton.dart';
import '../../../widgets/track_context_menu.dart';
import '../../../widgets/track_row.dart';

/// Songs list — local mode (SQL) or server mode (paginated).
class SongsTab extends ConsumerWidget {
  const SongsTab({required this.isLocal, super.key});
  final bool isLocal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeId = ref.watch(currentTrackProvider)?.id;
    final isBuffering = ref.watch(isBufferingProvider);
    final accent = ref.watch(currentSpectralProvider.select((s) => s.energy));

    if (isLocal) {
      final tracks = ref.watch(localTracksProvider);
      return tracks.when(
        data: (list) => _buildList(list, activeId, isBuffering, accent, ref),
        loading: () => const LibrarySkeleton(mode: LibrarySkeletonMode.songs),
        error: (e, _) => AsyncErrorView(
          label: 'Couldn\u2019t load songs',
          error: e,
          onRetry: () => ref.invalidate(localTracksProvider),
        ),
      );
    }

    final tracksState = ref.watch(tracksPaginationProvider);
    if (tracksState.error != null && tracksState.items.isEmpty) {
      return AsyncErrorView(
        label: 'Couldn\u2019t load songs',
        error: Exception(tracksState.error),
        onRetry: () =>
            ref.read(tracksPaginationProvider.notifier).loadFirstPage(),
      );
    }
    if (tracksState.items.isEmpty && tracksState.isLoadingMore) {
      return const Center(child: CircularProgressIndicator());
    }

    return _buildList(tracksState.items, activeId, isBuffering, accent, ref);
  }

  Widget _buildList(
    List<AfTrack> tracks,
    String? activeId,
    bool isBuffering,
    Color accent,
    WidgetRef ref,
  ) {
    const padding = EdgeInsets.symmetric(horizontal: AfSpacing.s8);

    if (tracks.isEmpty) {
      return const EmptyState(
        icon: LucideIcons.music,
        title: 'No songs yet',
        body: 'Songs from your library will appear here',
      );
    }

    return RepaintBoundary(
      child: AfScrollbar(
        child: ListView.builder(
          padding: padding.add(
            const EdgeInsets.only(bottom: AfSpacing.bottomInsetWithMiniAndNav),
          ),
          itemCount: tracks.length,
          itemBuilder: (context, i) {
            final t = tracks[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: AfSpacing.s4),
              child: TrackRow(
                track: t,
                isActive: t.id == activeId,
                isBuffering: t.id == activeId && isBuffering,
                activeAccent: accent,
                onTap: () =>
                    ref.read(playActionsProvider).playSmartQueue(t, tracks),
                onLongPress: () => showTrackContextMenu(context, ref, t),
              ),
            );
          },
        ),
      ),
    );
  }
}
