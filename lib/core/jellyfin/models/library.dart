/// A library "view" returned by `/Users/{userId}/Views`.
class LibraryView {
  final String id;
  final String name;
  final String collectionType; // e.g. 'music', 'audiobooks'
  final int trackCount;
  final int albumCount;

  const LibraryView({
    required this.id,
    required this.name,
    required this.collectionType,
    this.trackCount = 0,
    this.albumCount = 0,
  });

  bool get hasAudio => collectionType == 'music' || collectionType == 'audiobooks';
}
