import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import 'sections/about_section.dart';
import 'sections/listening_stats_section.dart';
import 'sections/profile_header.dart';
import 'sections/settings_section.dart';

/// Profile screen — orchestrator that composes extracted section widgets.
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
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        ),
        slivers: [
          // ── Header — title + settings button ─────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AfSpacing.s16,
                AfSpacing.s16,
                AfSpacing.s16,
                0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Profile', style: AfTypography.titleLarge),
                  const SettingsButton(),
                ],
              ),
            ),
          ),

          // ── Split info — avatar + info + inline stats ────────────────
          SliverToBoxAdapter(
            child: SplitInfoSection(
              name: name,
              serverName: serverName,
              profilePhoto: (
                isUploading: profilePhoto.isUploading,
                localPath: profilePhoto.localPath,
                networkUrl: profilePhoto.networkUrl,
              ),
              trackCount: _fmtCount(tracksAsync),
              albumCount: _fmtCount(albumsAsync),
            ),
          ),

          // ── Quick stats — artists + playlists ────────────────────────
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: AfSpacing.s16),
              child: QuickStatsRow(artistCount: '—', playlistCount: '—'),
            ),
          ),

          // ── Pinned ───────────────────────────────────────────────────
          const SliverToBoxAdapter(child: PinnedSectionHeader()),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: AfSpacing.s8),
              child: PinnedAlbumsRow(albums: pinned),
            ),
          ),

          // ── Listening Stats ──────────────────────────────────────────
          SliverToBoxAdapter(
            child: ListeningStatsSection(isLastFmConnected: isLastFmConnected),
          ),

          // ── About ───────────────────────────────────────────────────
          const SliverToBoxAdapter(child: AboutSection()),

          const SliverToBoxAdapter(
            child: SizedBox(height: AfSpacing.bottomInsetWithMiniAndNav),
          ),
        ],
      ),
    );
  }

  /// Format an AsyncValue count with thousands separators ("2,247").
  String _fmtCount<T>(AsyncValue<List<T>> async) =>
      async.maybeWhen(data: (list) => _fmt(list.length), orElse: () => '—');

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
