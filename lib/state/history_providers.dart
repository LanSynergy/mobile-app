import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/jellyfin/models/items.dart';
import 'local_library_providers.dart';

final lostMemoriesProvider = FutureProvider.autoDispose<List<AfTrack>>((
  ref,
) async {
  final lib = ref.watch(localLibraryProvider);
  return lib.db.getLostMemories();
});
