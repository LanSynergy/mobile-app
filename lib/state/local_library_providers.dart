import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/jellyfin/models/items.dart';
import '../core/local/local_library.dart';

final localLibraryProvider = Provider<LocalLibrary>((ref) {
  final lib = LocalLibrary();
  ref.onDispose(() => lib.close());
  return lib;
});

final localAlbumsProvider = FutureProvider.autoDispose<List<AfAlbum>>((ref) {
  final lib = ref.watch(localLibraryProvider);
  return lib.albums();
});

final localArtistsProvider = FutureProvider.autoDispose<List<AfArtist>>((ref) {
  final lib = ref.watch(localLibraryProvider);
  return lib.artists();
});

final localTracksProvider = FutureProvider.autoDispose<List<AfTrack>>((ref) {
  final lib = ref.watch(localLibraryProvider);
  return lib.tracks();
});

final localGenresProvider = FutureProvider.autoDispose<List<AfGenre>>((ref) {
  final lib = ref.watch(localLibraryProvider);
  return lib.genres();
});
