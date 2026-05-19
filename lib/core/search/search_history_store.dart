import 'package:shared_preferences/shared_preferences.dart';

/// Persists the user's recent search queries to `shared_preferences`
/// so the search screen can surface them on every visit.
///
/// Implementation notes:
///   - Most-recently-used (MRU) ordering: a fresh hit moves the entry
///     to position 0.
///   - Capped at [maxEntries] to keep the chip row scannable and the
///     persistence cost negligible.
///   - Queries are stored already trimmed and lowercased — matching
///     the normalization rule the search provider key uses, so a
///     chip-tap re-executes the exact same provider key (no
///     duplicate fetch, immediate cache hit).
class SearchHistoryStore {
  static const _kKey = 'af.search_history';
  static const maxEntries = 10;

  /// Read the full ordered list (newest first). Returns an empty list
  /// on first run or if the key was wiped.
  static Future<List<String>> load() async {
    final p = await SharedPreferences.getInstance();
    return p.getStringList(_kKey) ?? const <String>[];
  }

  /// Insert [query] at position 0, deduplicate, and trim to
  /// [maxEntries]. No-op when [query] is empty.
  ///
  /// Returns the new list so callers can update in-memory state
  /// without re-reading from disk.
  static Future<List<String>> push(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return load();
    final p = await SharedPreferences.getInstance();
    final current = List<String>.from(p.getStringList(_kKey) ?? const []);
    current.removeWhere((q) => q == trimmed);
    current.insert(0, trimmed);
    if (current.length > maxEntries) {
      current.removeRange(maxEntries, current.length);
    }
    await p.setStringList(_kKey, current);
    return current;
  }

  /// Remove a single entry. Silently no-ops if the entry is not
  /// present.
  static Future<List<String>> remove(String query) async {
    final p = await SharedPreferences.getInstance();
    final current = List<String>.from(p.getStringList(_kKey) ?? const []);
    current.removeWhere((q) => q == query);
    await p.setStringList(_kKey, current);
    return current;
  }

  /// Drop every saved entry.
  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kKey);
  }
}
