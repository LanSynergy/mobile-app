/// Structured logging helpers built on `dart:developer.log`.
///
/// The codebase historically used bare `print('aetherfin:<category> ...')`
/// calls so any developer could grep `logcat` for a specific subsystem. That
/// works but requires `// ignore: avoid_print` on every site, and release
/// builds emit the same chatty output that debug builds do.
///
/// `dart:developer.log` is the recommended replacement:
///   * It's filterable by `name:` in Flutter DevTools and `adb logcat`.
///   * It accepts `error` and `stackTrace` parameters so exception traces are
///     attached to a single event rather than printed across multiple lines.
///   * It's compiled out by the Dart VM in profile/release builds the same
///     way `print` is (i.e. you still see it on a debug device), so the
///     trace-on-a-real-device debugging workflow is preserved.
///
/// Migration rule: every prior `print('aetherfin:<category> <msg>')` becomes
/// `afLog('<category>', '<msg>')`. Error sites that previously printed both
/// the exception and the stack as two lines should pass them in once:
/// `afLog('error', 'foo failed', error: e, stackTrace: stack)`.
library;

import 'dart:developer' as developer;

/// Emit a structured log line tagged `aetherfin:<category>`. The `category`
/// argument matches the categories documented in CLAUDE.md §7
/// (`boot`, `http`, `audio`, `data`, `live_update`, `error`, …).
void afLog(
  String category,
  String message, {
  Object? error,
  StackTrace? stackTrace,
}) {
  developer.log(
    message,
    name: 'aetherfin:$category',
    error: error,
    stackTrace: stackTrace,
  );
}
