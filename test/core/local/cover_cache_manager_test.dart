import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:aetherfin/core/local/cover_cache_manager.dart';

void main() {
  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('cover_cache_test_');
  });

  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  Future<CoverCacheManager> createManager({int? maxBytes}) =>
      CoverCacheManager.create(
        cacheDir: tmpDir.path,
        maxBytes: maxBytes ?? 1000,
      );

  group('CoverCacheManager', () {
    test('tracks access timestamps', () async {
      final manager = await createManager();
      final f = File('${tmpDir.path}/cover1.jpg');
      f.writeAsBytesSync(List.filled(100, 1));
      manager.trackAccess(f.path);
    });

    test('evicts when over limit', () async {
      final manager = await createManager(maxBytes: 1000);
      for (int i = 0; i < 5; i++) {
        final f = File('${tmpDir.path}/cover$i.jpg');
        f.writeAsBytesSync(List.filled(400, i));
        manager.trackAccess(f.path);
      }
      final deleted = await manager.evictIfNeeded();
      expect(deleted.length, greaterThan(0));
      int remaining = 0;
      for (final f in tmpDir.listSync().whereType<File>()) {
        if (f.path.endsWith('_access_meta.json')) continue;
        remaining += f.lengthSync();
      }
      expect(remaining, lessThanOrEqualTo(1000));
    });

    test('does not evict when under limit', () async {
      final manager = await createManager(maxBytes: 1000);
      final f = File('${tmpDir.path}/cover.jpg');
      f.writeAsBytesSync(List.filled(100, 1));
      manager.trackAccess(f.path);
      expect(await manager.evictIfNeeded(), isEmpty);
    });

    test('evicts oldest files first (LRU order)', () async {
      final manager = await createManager(maxBytes: 1000);
      for (int i = 0; i < 4; i++) {
        final f = File('${tmpDir.path}/cover$i.jpg');
        f.writeAsBytesSync(List.filled(400, i));
        manager.trackAccess(f.path);
      }
      manager.trackAccess('${tmpDir.path}/cover2.jpg');

      await manager.evictIfNeeded();

      expect(File('${tmpDir.path}/cover2.jpg').existsSync(), isTrue);
      int remaining = 0;
      for (final f in tmpDir.listSync().whereType<File>()) {
        if (f.path.endsWith('_access_meta.json')) continue;
        remaining += f.lengthSync();
      }
      expect(remaining, lessThanOrEqualTo(1000));
    });

    test('clears all cached files', () async {
      final manager = await createManager();
      for (int i = 0; i < 3; i++) {
        final f = File('${tmpDir.path}/cover$i.jpg');
        f.writeAsBytesSync(List.filled(100, i));
        manager.trackAccess(f.path);
      }
      await manager.clear();
      final files = tmpDir.listSync().whereType<File>().toList();
      for (final f in files) {
        expect(
          f.path.endsWith('_access_meta.json'),
          isTrue,
          reason: 'only metadata file should survive clear',
        );
      }
    });

    test('persists access timestamps across instances', () async {
      final dir = tmpDir.path;
      final m1 = await CoverCacheManager.create(cacheDir: dir, maxBytes: 1000);
      final f = File('$dir/cover.jpg');
      f.writeAsBytesSync(List.filled(100, 1));
      m1.trackAccess(f.path);
      // Force save by evicting (triggers _saveMeta) then create new instance
      await m1.evictIfNeeded();
      final m2 = await CoverCacheManager.create(cacheDir: dir, maxBytes: 1000);
      final f2 = File('$dir/cover2.jpg');
      f2.writeAsBytesSync(List.filled(400, 1));
      m2.trackAccess(f2.path);
    });

    test('pruneStaleEntries removes missing file entries', () async {
      final manager = await createManager();
      final f = File('${tmpDir.path}/cover.jpg');
      f.writeAsBytesSync(List.filled(100, 1));
      manager.trackAccess(f.path);
      f.deleteSync();
      await manager.pruneStaleEntries();
      final m2 = await CoverCacheManager.create(
        cacheDir: tmpDir.path,
        maxBytes: 1000,
      );
      expect(await m2.evictIfNeeded(), isEmpty);
    });

    test('preserves unknown files (no access log) on eviction', () async {
      final manager = await createManager(maxBytes: 1000);
      final f = File('${tmpDir.path}/unknown.jpg');
      f.writeAsBytesSync(List.filled(100, 1));
      for (int i = 0; i < 3; i++) {
        final f2 = File('${tmpDir.path}/tracked$i.jpg');
        f2.writeAsBytesSync(List.filled(400, i));
        manager.trackAccess(f2.path);
      }
      await manager.evictIfNeeded();
    });
  });
}
