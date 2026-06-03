import '../jellyfin/models/items.dart';
import 'innertube_client.dart';

/// Content returned by [YouTubeMusicClient.browseHome].
class YouTubeHomeContent {
  const YouTubeHomeContent({
    required this.sections,
    required this.chips,
    required this.region,
    this.continuation,
  });

  factory YouTubeHomeContent.empty() => const YouTubeHomeContent(
        sections: [],
        chips: [],
        region: 'US',
      );

  /// All sections from the home page (e.g. "Listen again", "Trending").
  final List<YouTubeHomeSection> sections;

  /// Filter chips from the home page.
  final List<InnerTubeChip> chips;

  /// Region code (e.g. "ID", "MY", "US").
  final String region;

  /// Continuation token for loading more sections.
  final String? continuation;

  /// Flat list of all tracks across sections.
  List<AfTrack> get trendingTracks => sections
      .expand((s) => s.items)
      .where((item) => item.type == InnerTubeItemType.song)
      .map((item) => AfTrack(
            id: item.id,
            title: item.title,
            artistName: item.subtitle,
            albumName: '',
            imageUrl: item.thumbnailUrl,
          ))
      .toList();
}

/// A single section on the YouTube Music home page.
class YouTubeHomeSection {
  const YouTubeHomeSection({
    required this.title,
    required this.items,
  });

  final String title;
  final List<InnerTubeItem> items;

  /// Helper to map back to tracks for backward compatibility.
  List<AfTrack> get tracks => items
      .where((item) => item.type == InnerTubeItemType.song)
      .map((item) => AfTrack(
            id: item.id,
            title: item.title,
            artistName: item.subtitle,
            albumName: '',
            imageUrl: item.thumbnailUrl,
          ))
      .toList();
}

