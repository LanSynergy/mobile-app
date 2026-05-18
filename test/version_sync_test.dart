import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards against `_kAetherfinVersion` in the HTTP clients drifting away
/// from `pubspec.yaml`. We had a real bug where both clients reported
/// `Aetherfin/0.1.0` long after the app moved to `0.2.3+4`, which made
/// Jellyfin session logs and Subsonic scrobbles attribute traffic to a
/// phantom version. The constants are intentionally hardcoded (see the
/// comment on `_kAetherfinVersion` in `jellyfin/client.dart`); this test
/// is the enforcement layer so a `pubspec.yaml` bump that forgets the
/// constants fails CI instead of shipping silently.
void main() {
  test('client User-Agent versions agree with pubspec.yaml', () {
    final repoRoot = _findRepoRoot(Directory.current);
    final pubspecVersion = _extractPubspecVersion(
      File('${repoRoot.path}/pubspec.yaml').readAsStringSync(),
    );
    expect(pubspecVersion, isNotNull,
        reason: 'Could not parse `version:` line from pubspec.yaml.');

    final filesToCheck = <String>[
      'lib/core/jellyfin/client.dart',
      'lib/core/subsonic/client.dart',
    ];

    for (final relPath in filesToCheck) {
      final source = File('${repoRoot.path}/$relPath').readAsStringSync();
      final constVersion = _extractKAetherfinVersion(source);
      expect(constVersion, isNotNull,
          reason: '$relPath: could not find `_kAetherfinVersion = \'…\'`.');
      expect(constVersion, equals(pubspecVersion),
          reason: '$relPath: `_kAetherfinVersion` ($constVersion) does not '
              'match pubspec.yaml version ($pubspecVersion). Bump both.');
    }
  });
}

/// Walk up from [start] until we find the directory containing `pubspec.yaml`.
/// `flutter test` runs from the package root, but other harnesses may invoke
/// from `test/` or further down — this keeps the test robust to that.
Directory _findRepoRoot(Directory start) {
  var dir = start;
  for (var i = 0; i < 8; i++) {
    if (File('${dir.path}/pubspec.yaml').existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  throw StateError('Could not locate repo root (pubspec.yaml) from ${start.path}.');
}

/// Pull the SemVer portion (`MAJOR.MINOR.PATCH`) out of a `version: X.Y.Z+N`
/// line. The `+build` suffix is intentionally dropped — the runtime User-Agent
/// and the Jellyfin Version field both report only `X.Y.Z`.
String? _extractPubspecVersion(String source) {
  final match = RegExp(r'^version:\s*(\d+\.\d+\.\d+)', multiLine: true)
      .firstMatch(source);
  return match?.group(1);
}

/// Find `const _kAetherfinVersion = 'X.Y.Z';` and return the literal.
String? _extractKAetherfinVersion(String source) {
  final match = RegExp(
    r"_kAetherfinVersion\s*=\s*'([^']+)'",
  ).firstMatch(source);
  return match?.group(1);
}
