import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aetherfin/core/local/app_database.dart';
import 'package:aetherfin/core/local/queue_history_repository.dart';
import 'package:aetherfin/state/local_library_providers.dart';
import 'package:aetherfin/state/queue_history_providers.dart';

void main() {
  group('queueHistoryRepositoryProvider', () {
    test('creates repository instance', () {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(
            AppDatabase.forTesting(NativeDatabase.memory()),
          ),
        ],
      );
      addTearDown(container.dispose);
      final repo = container.read(queueHistoryRepositoryProvider);
      expect(repo, isA<QueueHistoryRepository>());
    });
  });
}
