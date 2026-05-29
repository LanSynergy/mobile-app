import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/search/search_history_store.dart';

/// Most-recently-used list of search queries, persisted across runs.
class SearchHistoryNotifier extends Notifier<List<String>> {
  @override
  List<String> build() {
    _hydrate();
    return const <String>[];
  }

  Future<void> _hydrate() async {
    final saved = await SearchHistoryStore.load();
    state = saved;
  }

  Future<void> push(String query) async {
    final updated = await SearchHistoryStore.push(query);
    state = updated;
  }

  Future<void> remove(String query) async {
    final updated = await SearchHistoryStore.remove(query);
    state = updated;
  }

  Future<void> clear() async {
    await SearchHistoryStore.clear();
    state = const <String>[];
  }
}

final searchHistoryProvider =
    NotifierProvider<SearchHistoryNotifier, List<String>>(
      SearchHistoryNotifier.new,
    );
