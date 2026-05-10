import 'dart:math' as math;

import '../jellyfin/models/items.dart';
import '../jellyfin/models/quality.dart';

/// A self-contained demo library — used until the user connects to a
/// real Jellyfin server, and as a deterministic fixture for tests.
///
/// The data here intentionally avoids real, copyrighted artist/album
/// names. Every track gets a deterministic peaks array so the waveform
/// renders honestly (per spec §8.8: "never a fake 'looks musical' pattern").
class DemoLibrary {
  static final tracks = _buildTracks();
  static final albums = _buildAlbums();
  static final artists = _buildArtists();
  static final playlists = _buildPlaylists();
  static final genres = const [
    AfGenre('Indie',     '#5644C9'),
    AfGenre('Electronic','#332C7A'),
    AfGenre('Jazz',      '#453AA1'),
    AfGenre('Ambient',   '#251F58'),
    AfGenre('Classical', '#181439'),
    AfGenre('Hip-Hop',   '#6657D7'),
    AfGenre('Folk',      '#A89DEC'),
    AfGenre('Pop',       '#8276E0'),
  ];

  static List<AfTrack> tracksByAlbum(String albumId) =>
      tracks.where((t) => t.albumId == albumId).toList();

  static AfAlbum? albumById(String id) =>
      albums.cast<AfAlbum?>().firstWhere((a) => a?.id == id, orElse: () => null);

  static AfArtist? artistById(String id) =>
      artists.cast<AfArtist?>().firstWhere((a) => a?.id == id, orElse: () => null);

  static AfTrack? trackById(String id) =>
      tracks.cast<AfTrack?>().firstWhere((t) => t?.id == id, orElse: () => null);

  /// Deterministic peaks for the waveform. Seeded by track ID so the same
  /// track always renders the same shape.
  static List<int> peaksFor(String trackId, {int bars = 96}) {
    final rng = math.Random(trackId.hashCode);
    return List<int>.generate(bars, (i) {
      final base = 0.35 + 0.55 * rng.nextDouble();
      final wave = math.sin(i / 6 + trackId.length) * 0.18;
      return ((base + wave).clamp(0.05, 0.98) * 100).round();
    });
  }

  // ---------------------------------------------------------------------------
  // Builders
  // ---------------------------------------------------------------------------

  static List<AfAlbum> _buildAlbums() {
    final sources = [
      ('al1', 'Neon Cathedral',     'Skylark', 2022, 12, 47, true),
      ('al2', 'Soft Aperture',      'Lumen Tide', 2024, 9, 34, false),
      ('al3', 'Field Notes',        'Aria Greene', 2021, 14, 51, true),
      ('al4', 'Slow Rain at Noon',  'Pinemoth', 2023, 10, 39, false),
      ('al5', 'Velvet Signal',      'Marrow Bay', 2025, 11, 44, true),
      ('al6', 'Moss & Mirror',      'North Quietly', 2023, 8, 29, false),
      ('al7', 'Halflight',          'Skylark', 2020, 13, 49, true),
      ('al8', 'Underwater Letters', 'Coral Quartet', 2024, 7, 26, false),
      ('al9', 'Perennial',          'Aria Greene', 2025, 10, 36, true),
      ('al10','Glasshouse',         'Lumen Tide', 2022, 9, 33, false),
      ('al11','Boreal Patterns',    'Pinemoth', 2021, 12, 42, true),
      ('al12','Sea & Solder',       'Marrow Bay', 2024, 8, 30, false),
    ];
    final now = DateTime.now();
    return [
      for (var i = 0; i < sources.length; i++)
        AfAlbum(
          id: sources[i].$1,
          name: sources[i].$2,
          artistName: sources[i].$3,
          year: sources[i].$4,
          trackCount: sources[i].$5,
          totalDuration: Duration(minutes: sources[i].$6),
          quality: TrackQuality(
            sourceCodec: sources[i].$7 ? 'flac' : 'aac',
            bitDepth: sources[i].$7 ? 24 : null,
            sampleRateKhz: sources[i].$7 ? 96 : null,
            bitrateKbps: sources[i].$7 ? null : 256,
          ),
          dateAdded: now.subtract(Duration(days: i * 4 + 2)),
        ),
    ];
  }

  static List<AfArtist> _buildArtists() {
    return const [
      AfArtist(
        id: 'ar1',
        name: 'Skylark',
        albumCount: 2,
        trackCount: 25,
        bio: 'Skylark is a four-piece project that builds slow, '
            'gradient-shaped pieces from acoustic loops, field recordings, '
            'and re-amplified piano. Every record is mixed in one room.',
      ),
      AfArtist(id: 'ar2', name: 'Lumen Tide', albumCount: 2, trackCount: 18),
      AfArtist(id: 'ar3', name: 'Aria Greene', albumCount: 2, trackCount: 24),
      AfArtist(id: 'ar4', name: 'Pinemoth', albumCount: 2, trackCount: 22),
      AfArtist(id: 'ar5', name: 'Marrow Bay', albumCount: 2, trackCount: 19),
      AfArtist(id: 'ar6', name: 'North Quietly', albumCount: 1, trackCount: 8),
      AfArtist(id: 'ar7', name: 'Coral Quartet', albumCount: 1, trackCount: 7),
    ];
  }

  static List<AfTrack> _buildTracks() {
    final out = <AfTrack>[];
    final albumSeeds = [
      ('al1', 'Skylark',      'Neon Cathedral',     true),
      ('al2', 'Lumen Tide',   'Soft Aperture',      false),
      ('al3', 'Aria Greene',  'Field Notes',        true),
      ('al4', 'Pinemoth',     'Slow Rain at Noon',  false),
      ('al5', 'Marrow Bay',   'Velvet Signal',      true),
      ('al6', 'North Quietly','Moss & Mirror',      false),
      ('al7', 'Skylark',      'Halflight',          true),
      ('al8', 'Coral Quartet','Underwater Letters', false),
      ('al9', 'Aria Greene',  'Perennial',          true),
      ('al10','Lumen Tide',   'Glasshouse',         false),
      ('al11','Pinemoth',     'Boreal Patterns',    true),
      ('al12','Marrow Bay',   'Sea & Solder',       false),
    ];
    final titleBank = [
      'Driftless', 'A Quieter Year', 'Backyard Stars', 'New Glass',
      'Returning Bird', 'Midwinter Letter', 'Pale Engine', 'After Rain',
      'Old Cassette', 'Little Architecture', 'Sleep Margin', 'Tin Light',
      'Kept Promise', 'Still Cloud', 'Slow Saturday', 'Open Map',
      'Halfway Home', 'Folded Map', 'The Long Way',
    ];
    final rng = math.Random(7);
    for (var ai = 0; ai < albumSeeds.length; ai++) {
      final (albumId, artist, album, lossless) = albumSeeds[ai];
      final tracks = 6 + rng.nextInt(6);
      for (var ti = 1; ti <= tracks; ti++) {
        final id = '${albumId}_t$ti';
        final title = titleBank[(ai * 5 + ti) % titleBank.length];
        final secs = 150 + rng.nextInt(180);
        out.add(AfTrack(
          id: id,
          title: title,
          artistName: artist,
          albumName: album,
          albumId: albumId,
          artistId: 'ar${ai % 7 + 1}',
          trackNumber: ti,
          duration: Duration(seconds: secs),
          quality: TrackQuality(
            sourceCodec: lossless ? 'flac' : 'aac',
            bitDepth: lossless ? 24 : null,
            sampleRateKhz: lossless ? 96 : null,
            bitrateKbps: lossless ? null : 256,
            isTranscoded: ti == 4 && ai == 0, // a single demo transcode
            transcodeCodec: ti == 4 && ai == 0 ? 'aac' : null,
            transcodeBitrateKbps: ti == 4 && ai == 0 ? 192 : null,
          ),
          peaks: peaksFor(id),
        ));
      }
    }
    return out;
  }

  static List<AfPlaylist> _buildPlaylists() {
    return const [
      AfPlaylist(id: 'p1', name: 'Long Drives',         trackCount: 38, isPublic: true),
      AfPlaylist(id: 'p2', name: 'Late Night Reading',  trackCount: 22, isPublic: true),
      AfPlaylist(id: 'p3', name: 'Morning Light',       trackCount: 18, isPublic: false),
      AfPlaylist(id: 'p4', name: 'Cooking Things',      trackCount: 31, isPublic: false),
      AfPlaylist(id: 'p5', name: 'For the Plane',       trackCount: 47, isPublic: true),
    ];
  }
}
