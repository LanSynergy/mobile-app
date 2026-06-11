/// Checks if a character is hiragana (U+3040–U+309F).
bool _isHiragana(String char) {
  if (char.isEmpty) return false;
  final code = char.codeUnitAt(0);
  return code >= 0x3040 && code <= 0x309F;
}

/// Checks if a character is katakana (U+30A0–U+30FF or U+31F0–U+31FF).
bool _isKatakana(String char) {
  if (char.isEmpty) return false;
  final code = char.codeUnitAt(0);
  return (code >= 0x30A0 && code <= 0x30FF) || (code >= 0x31F0 && code <= 0x31FF);
}

/// Checks if a character is kanji (CJK Unified Ideograph, U+4E00–U+9FFF).
bool _isKanji(String char) {
  if (char.isEmpty) return false;
  final code = char.codeUnitAt(0);
  return code >= 0x4E00 && code <= 0x9FFF;
}

/// Returns true if [text] contains any Japanese characters
/// (hiragana, katakana, or kanji).
bool containsJapanese(String? text) {
  if (text == null || text.isEmpty) return false;
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (_isHiragana(char) || _isKatakana(char) || _isKanji(char)) {
      return true;
    }
  }
  return false;
}
