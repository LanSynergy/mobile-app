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
  return (code >= 0x30A0 && code <= 0x30FF) ||
      (code >= 0x31F0 && code <= 0x31FF);
}

/// Checks if a character is kanji (CJK Unified Ideograph, U+4E00–U+9FFF).
bool _isKanji(String char) {
  if (char.isEmpty) return false;
  final code = char.codeUnitAt(0);
  return code >= 0x4E00 && code <= 0x9FFF;
}

/// Checks if a character is Hangul (Korean).
///
/// Covers Hangul Jamo (U+1100–U+11FF), Hangul Compatibility Jamo
/// (U+3130–U+318F), and Hangul Syllables (U+AC00–U+D7AF).
bool _isHangul(String char) {
  if (char.isEmpty) return false;
  final code = char.codeUnitAt(0);
  return (code >= 0x1100 && code <= 0x11FF) ||
      (code >= 0x3130 && code <= 0x318F) ||
      (code >= 0xAC00 && code <= 0xD7AF);
}

/// Checks if a character is Cyrillic (U+0400–U+04FF or U+0500–U+052F).
bool _isCyrillic(String char) {
  if (char.isEmpty) return false;
  final code = char.codeUnitAt(0);
  return (code >= 0x0400 && code <= 0x04FF) ||
      (code >= 0x0500 && code <= 0x052F);
}

/// Checks if a character is Arabic.
///
/// Covers Arabic (U+0600–U+06FF), Arabic Supplement (U+0750–U+077F),
/// Arabic Presentation Forms-A (U+FB50–U+FDFF), and
/// Arabic Presentation Forms-B (U+FE70–U+FEFF).
bool _isArabic(String char) {
  if (char.isEmpty) return false;
  final code = char.codeUnitAt(0);
  return (code >= 0x0600 && code <= 0x06FF) ||
      (code >= 0x0750 && code <= 0x077F) ||
      (code >= 0xFB50 && code <= 0xFDFF) ||
      (code >= 0xFE70 && code <= 0xFEFF);
}

/// Checks if a character is Hebrew.
///
/// Covers Hebrew (U+0590–U+05FF) and
/// Hebrew Presentation Forms-A (U+FB1D–U+FB4F).
bool _isHebrew(String char) {
  if (char.isEmpty) return false;
  final code = char.codeUnitAt(0);
  return (code >= 0x0590 && code <= 0x05FF) ||
      (code >= 0xFB1D && code <= 0xFB4F);
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

/// Returns true if [text] contains any Korean characters (Hangul).
bool containsKorean(String? text) {
  if (text == null || text.isEmpty) return false;
  for (var i = 0; i < text.length; i++) {
    if (_isHangul(text[i])) return true;
  }
  return false;
}

/// Returns true if [text] contains any Chinese characters (CJK Ideographs).
///
/// Note: CJK Ideographs are shared between Chinese and Japanese. Use
/// [containsJapanese] first to check for hiragana/katakana which
/// disambiguates Japanese from pure Chinese text.
bool containsChinese(String? text) {
  if (text == null || text.isEmpty) return false;
  for (var i = 0; i < text.length; i++) {
    if (_isKanji(text[i])) return true;
  }
  return false;
}

/// Returns true if [text] contains any Cyrillic characters.
bool containsCyrillic(String? text) {
  if (text == null || text.isEmpty) return false;
  for (var i = 0; i < text.length; i++) {
    if (_isCyrillic(text[i])) return true;
  }
  return false;
}

/// Returns true if [text] contains any Arabic characters.
bool containsArabic(String? text) {
  if (text == null || text.isEmpty) return false;
  for (var i = 0; i < text.length; i++) {
    if (_isArabic(text[i])) return true;
  }
  return false;
}

/// Returns true if [text] contains any Hebrew characters.
bool containsHebrew(String? text) {
  if (text == null || text.isEmpty) return false;
  for (var i = 0; i < text.length; i++) {
    if (_isHebrew(text[i])) return true;
  }
  return false;
}

/// Returns true if [text] contains any romanizable (non-Latin) text
/// from languages supported by the `romanize` package:
/// Japanese, Korean, Chinese, Cyrillic, Arabic, or Hebrew.
bool containsRomanizableText(String? text) {
  if (text == null || text.isEmpty) return false;
  return containsJapanese(text) ||
      containsKorean(text) ||
      containsChinese(text) ||
      containsCyrillic(text) ||
      containsArabic(text) ||
      containsHebrew(text);
}
