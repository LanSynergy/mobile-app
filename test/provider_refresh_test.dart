import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  group('Riverpod Invalidation Race Condition (BUG-3)', () {
    test('Sequence A (Buggy): read future then invalidate resolves immediately with stale data', () async {
      int fetchCount = 0;
      final completerProvider = FutureProvider<int>((ref) async {
        fetchCount++;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return fetchCount;
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      // 1. Initial fetch
      final firstVal = await container.read(completerProvider.future);
      expect(firstVal, 1);
      expect(fetchCount, 1);

      // 2. Buggy sequence: read future first, then invalidate
      final oldFuture = container.read(completerProvider.future);
      container.invalidate(completerProvider);

      // The old future is already completed with the previous value (1)
      final value = await oldFuture;
      expect(value, 1); // Returns old value immediately
      
      // Even though invalidation was triggered, oldFuture did not wait for fetchCount 2
      expect(fetchCount, 1); // Has not started the second fetch yet
    });

    test('Sequence B (Correct): invalidate then read future waits for the new fetch to complete', () async {
      int fetchCount = 0;
      final completerProvider = FutureProvider<int>((ref) async {
        fetchCount++;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return fetchCount;
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      // 1. Initial fetch
      final firstVal = await container.read(completerProvider.future);
      expect(firstVal, 1);
      expect(fetchCount, 1);

      // 2. Correct sequence: invalidate first, then read future
      container.invalidate(completerProvider);
      final newFuture = container.read(completerProvider.future);

      // The new future is not completed and waits for the new async fetch
      final value = await newFuture;
      expect(value, 2);
      expect(fetchCount, 2);
    });
  });
}
