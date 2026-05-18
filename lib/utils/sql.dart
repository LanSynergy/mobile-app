/// Escape SQL `LIKE` metacharacters (`%`, `_`, `\`) so a user-typed
/// pattern is matched literally. Always pair the produced pattern with
/// a `LIKE … ESCAPE '\'` clause — the raw backslash must be declared
/// as the escape character on the SQL side.
///
/// Without this, a search like `100%` acts as `100<wildcard>` and a
/// folder URI containing `%` could prune unrelated tracks during
/// `removeFolder()`.
String escapeSqlLike(String s) {
  final buf = StringBuffer();
  for (final r in s.runes) {
    if (r == 0x5C /* \ */ || r == 0x25 /* % */ || r == 0x5F /* _ */) {
      buf.write(r'\');
    }
    buf.writeCharCode(r);
  }
  return buf.toString();
}
