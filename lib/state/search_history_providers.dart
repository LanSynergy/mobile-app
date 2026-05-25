import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/search/search_history_store.dart';

/// Most-recently-used list of search queries, persisted across runs.
class SearchHistoryNotifier extends StateNotifier<List<String>> {
  SearchHistoryNotifier() : super(const <String>[]) {
    _hydrate();
  }

  Future<void> _hydrate() async {
    final saved = await SearchHistoryStore.load();
    if (mounted) state = saved;
  }

  Future<void> push(String query) async {
    final updated = await SearchHistoryStore.push(query);
    if (mounted) state = updated;
  }

  Future<void> remove(String query) async {
    final updated = await SearchHistoryStore.remove(query);
    if (mounted) state = updated;
  }

  Future<void> clear() async {
    await SearchHistoryStore.clear();
    if (mounted) state = const <String>[];
  }
}

final searchHistoryProvider =
    StateNotifierProvider<SearchHistoryNotifier, List<String>>(
      (ref) => SearchHistoryNotifier(),
    );
