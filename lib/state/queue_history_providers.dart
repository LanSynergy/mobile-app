import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/local/queue_history_repository.dart';
import 'local_library_providers.dart';

/// Provider for QueueHistoryRepository — backed by the AppDatabase.
final queueHistoryRepositoryProvider = Provider<QueueHistoryRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return QueueHistoryRepository(db);
});

/// Provider for the list of recent queue history entries.
final recentQueueHistoryProvider =
    FutureProvider.autoDispose<List<QueueHistoryItem>>((ref) async {
      final repo = ref.watch(queueHistoryRepositoryProvider);
      return repo.loadRecent(limit: 10);
    });
