/// A library "view" returned by `/Users/{userId}/Views`.
class LibraryView {

  const LibraryView({
    required this.id,
    required this.name,
    required this.collectionType,
    this.trackCount = 0,
    this.albumCount = 0,
  });
  final String id;
  final String name;
  final String collectionType; // e.g. 'music', 'audiobooks'
  final int trackCount;
  final int albumCount;

  bool get hasAudio => collectionType == 'music' || collectionType == 'audiobooks';
}
