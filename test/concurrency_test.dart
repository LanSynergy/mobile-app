import 'package:flutter_test/flutter_test.dart';

import 'package:aetherfin/core/audio/player_service.dart';

void main() {
  group('AfAsyncLock', () {
    test('executes operations sequentially', () async {
      final lock = AfAsyncLock();
      final order = <int>[];

      final f1 = lock.run(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        order.add(1);
      });

      final f2 = lock.run(() async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        order.add(2);
      });

      await Future.wait([f1, f2]);

      expect(order, [1, 2]);
    });

    test(
      'continues execution chain even when previous operation fails',
      () async {
        final lock = AfAsyncLock();
        final order = <int>[];

        final f1 = lock.run(() async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          throw Exception('Operation 1 failed');
        });

        final f2 = lock.run(() async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          order.add(2);
        });

        expect(f1, throwsA(isA<Exception>()));
        await f2;

        expect(order, [2]);
      },
    );

    test(
      'maintains sequential execution order with many overlapping requests',
      () async {
        final lock = AfAsyncLock();
        final order = <int>[];

        final futures = List<Future<void>>.generate(5, (index) {
          return lock.run(() async {
            // Delay varies to test that order is strictly preserved despite different async durations
            final delayMs = (5 - index) * 10;
            await Future<void>.delayed(Duration(milliseconds: delayMs));
            order.add(index);
          });
        });

        await Future.wait(futures);

        expect(order, [0, 1, 2, 3, 4]);
      },
    );
  });
}
