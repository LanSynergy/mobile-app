// Run before `flutter build` to generate a unique build ID.
// Usage: dart run tool/generate_build_id.dart

import 'dart:io';
import 'dart:math';

void main() {
  final rng = Random.secure();
  final id = List.generate(8, (_) => rng.nextInt(16).toRadixString(16)).join();
  final content =
      '// AUTO-GENERATED — do not edit manually.\n'
      '// Regenerated on every build by tool/generate_build_id.dart\n'
      "const kBuildId = '$id';\n";
  File('lib/build_id.dart').writeAsStringSync(content);
  stderr.writeln('Generated build ID: $id');
}
