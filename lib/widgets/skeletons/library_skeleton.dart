import 'package:flutter/material.dart';

import '../../design_tokens/tokens.dart';
import '../skeleton.dart';
import 'album_card_skeleton.dart';
import 'track_row_skeleton.dart';

/// Which library section to show a skeleton for.
enum LibrarySkeletonMode { albums, artists, songs, playlists, genres, liked }

/// Shimmer skeleton for the library screen tabs.
class LibrarySkeleton extends StatelessWidget {
  const LibrarySkeleton({super.key, required this.mode});

  final LibrarySkeletonMode mode;

  @override
  Widget build(BuildContext context) {
    return switch (mode) {
      LibrarySkeletonMode.albums => const _AlbumGridSkeleton(),
      LibrarySkeletonMode.artists => const _ArtistListSkeleton(),
      LibrarySkeletonMode.songs => const _TrackListSkeleton(),
      LibrarySkeletonMode.playlists => const _PlaylistListSkeleton(),
      LibrarySkeletonMode.genres => const _GenreGridSkeleton(),
      LibrarySkeletonMode.liked => const _TrackListSkeleton(),
    };
  }
}

class _AlbumGridSkeleton extends StatelessWidget {
  const _AlbumGridSkeleton();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: AfSpacing.bottomInsetWithMiniAndNav,
      ),
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: AfSpacing.s12,
        crossAxisSpacing: AfSpacing.s12,
        childAspectRatio: 0.9,
        padding: AfSpacing.pageHorizontal,
        children: List.generate(12, (_) => const AlbumCardSkeleton()),
      ),
    );
  }
}

class _ArtistListSkeleton extends StatelessWidget {
  const _ArtistListSkeleton();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: AfSpacing.bottomInsetWithMiniAndNav,
      ),
      child: ListView(
        padding: AfSpacing.pageHorizontal,
        children: List.generate(10, (_) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: AfSpacing.s8),
            child: Row(
              children: [
                SkeletonCircle(size: 48),
                SizedBox(width: AfSpacing.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FractionallySizedBox(
                        widthFactor: 0.5,
                        child: SkeletonBar(height: 16),
                      ),
                      SizedBox(height: AfSpacing.s4),
                      FractionallySizedBox(
                        widthFactor: 0.3,
                        child: SkeletonBar(height: 14),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _TrackListSkeleton extends StatelessWidget {
  const _TrackListSkeleton();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: AfSpacing.bottomInsetWithMiniAndNav,
      ),
      child: ListView(
        padding: AfSpacing.pageHorizontal,
        children: List.generate(10, (_) => const TrackRowSkeleton()),
      ),
    );
  }
}

class _PlaylistListSkeleton extends StatelessWidget {
  const _PlaylistListSkeleton();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: AfSpacing.bottomInsetWithMiniAndNav,
      ),
      child: ListView(
        padding: AfSpacing.pageHorizontal,
        children: List.generate(10, (_) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: AfSpacing.s8),
            child: Row(
              children: [
                SkeletonBlock(width: 56, height: 56),
                SizedBox(width: AfSpacing.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FractionallySizedBox(
                        widthFactor: 0.6,
                        child: SkeletonBar(height: 16),
                      ),
                      SizedBox(height: AfSpacing.s4),
                      FractionallySizedBox(
                        widthFactor: 0.35,
                        child: SkeletonBar(height: 14),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _GenreGridSkeleton extends StatelessWidget {
  const _GenreGridSkeleton();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AfSpacing.s16,
        right: AfSpacing.s16,
        bottom: AfSpacing.bottomInsetWithMiniAndNav,
      ),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: AfSpacing.s12,
        crossAxisSpacing: AfSpacing.s12,
        childAspectRatio: 2.5,
        children: List.generate(8, (_) {
          return ShimmerWrap(
            child: Container(
              decoration: const BoxDecoration(
                color: AfColors.surfaceRaised,
                borderRadius: AfRadii.borderPill,
              ),
            ),
          );
        }),
      ),
    );
  }
}
