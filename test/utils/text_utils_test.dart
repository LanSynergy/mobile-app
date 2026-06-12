import 'package:flutter_test/flutter_test.dart';
import 'package:aetherfin/utils/text_utils.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // containsJapanese
  // ═══════════════════════════════════════════════════════════════════════════

  group('containsJapanese', () {
    test('returns true for hiragana', () {
      expect(containsJapanese('こんにちは'), isTrue);
    });

    test('returns true for katakana', () {
      expect(containsJapanese('カタカナ'), isTrue);
    });

    test('returns true for kanji', () {
      expect(containsJapanese('明日'), isTrue);
    });

    test('returns true for mixed Japanese', () {
      expect(containsJapanese('ありがとう世界'), isTrue);
    });

    test('returns false for English', () {
      expect(containsJapanese('Hello world'), isFalse);
    });

    test('returns false for empty string', () {
      expect(containsJapanese(''), isFalse);
    });

    test('returns false for null', () {
      expect(containsJapanese(null), isFalse);
    });

    test('returns false for Korean', () {
      expect(containsJapanese('안녕하세요'), isFalse);
    });

    test('returns true for Chinese (CJK ideographs shared with kanji)', () {
      // CJK Unified Ideographs are shared between Chinese and Japanese.
      // containsJapanese returns true because it checks for kanji range.
      // The resolver uses TextRomanizer for actual language disambiguation.
      expect(containsJapanese('你好世界'), isTrue);
    });

    test('returns false for Cyrillic', () {
      expect(containsJapanese('Привет мир'), isFalse);
    });

    test('returns false for Arabic', () {
      expect(containsJapanese('مرحبا بالعالم'), isFalse);
    });

    test('returns false for Hebrew', () {
      expect(containsJapanese('שלום עולם'), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // containsKorean
  // ═══════════════════════════════════════════════════════════════════════════

  group('containsKorean', () {
    test('returns true for Hangul syllables', () {
      expect(containsKorean('안녕하세요'), isTrue);
    });

    test('returns true for mixed Hangul', () {
      expect(containsKorean('Hello 안녕 World'), isTrue);
    });

    test('returns false for English', () {
      expect(containsKorean('Hello world'), isFalse);
    });

    test('returns false for Japanese', () {
      expect(containsKorean('こんにちは'), isFalse);
    });

    test('returns false for Chinese', () {
      expect(containsKorean('你好'), isFalse);
    });

    test('returns false for empty string', () {
      expect(containsKorean(''), isFalse);
    });

    test('returns false for null', () {
      expect(containsKorean(null), isFalse);
    });

    test('returns false for Cyrillic', () {
      expect(containsKorean('Привет'), isFalse);
    });

    test('returns false for Arabic', () {
      expect(containsKorean('مرحبا'), isFalse);
    });

    test('returns false for Hebrew', () {
      expect(containsKorean('שלום'), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // containsChinese
  // ═══════════════════════════════════════════════════════════════════════════

  group('containsChinese', () {
    test('returns true for Simplified Chinese', () {
      expect(containsChinese('你好世界'), isTrue);
    });

    test('returns true for Traditional Chinese', () {
      expect(containsChinese('你好世界'), isTrue);
    });

    test('returns true for mixed Chinese and Latin', () {
      expect(containsChinese('Hello 你好 World'), isTrue);
    });

    test('returns false for English', () {
      expect(containsChinese('Hello world'), isFalse);
    });

    test('returns true for Japanese (kanji only — shared CJK range)', () {
      // Pure kanji is shared between Chinese and Japanese.
      // containsChinese returns true because CJK Unified Ideographs
      // are shared. The resolver uses TextRomanizer which auto-detects.
      expect(containsChinese('明日'), isTrue);
    });

    test('returns false for Korean', () {
      expect(containsChinese('안녕하세요'), isFalse);
    });

    test('returns false for empty string', () {
      expect(containsChinese(''), isFalse);
    });

    test('returns false for null', () {
      expect(containsChinese(null), isFalse);
    });

    test('returns false for Cyrillic', () {
      expect(containsChinese('Привет'), isFalse);
    });

    test('returns false for Arabic', () {
      expect(containsChinese('مرحبا'), isFalse);
    });

    test('returns false for Hebrew', () {
      expect(containsChinese('שלום'), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // containsCyrillic
  // ═══════════════════════════════════════════════════════════════════════════

  group('containsCyrillic', () {
    test('returns true for Russian', () {
      expect(containsCyrillic('Привет мир'), isTrue);
    });

    test('returns true for Ukrainian', () {
      expect(containsCyrillic('Привіт світ'), isTrue);
    });

    test('returns true for mixed Cyrillic and Latin', () {
      expect(containsCyrillic('Hello Привет World'), isTrue);
    });

    test('returns false for English', () {
      expect(containsCyrillic('Hello world'), isFalse);
    });

    test('returns false for Japanese', () {
      expect(containsCyrillic('こんにちは'), isFalse);
    });

    test('returns false for Korean', () {
      expect(containsCyrillic('안녕하세요'), isFalse);
    });

    test('returns false for empty string', () {
      expect(containsCyrillic(''), isFalse);
    });

    test('returns false for null', () {
      expect(containsCyrillic(null), isFalse);
    });

    test('returns false for Arabic', () {
      expect(containsCyrillic('مرحبا'), isFalse);
    });

    test('returns false for Hebrew', () {
      expect(containsCyrillic('שלום'), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // containsArabic
  // ═══════════════════════════════════════════════════════════════════════════

  group('containsArabic', () {
    test('returns true for Arabic text', () {
      expect(containsArabic('مرحبا بالعالم'), isTrue);
    });

    test('returns true for mixed Arabic and Latin', () {
      expect(containsArabic('Hello مرحبا World'), isTrue);
    });

    test('returns false for English', () {
      expect(containsArabic('Hello world'), isFalse);
    });

    test('returns false for Japanese', () {
      expect(containsArabic('こんにちは'), isFalse);
    });

    test('returns false for Korean', () {
      expect(containsArabic('안녕하세요'), isFalse);
    });

    test('returns false for Cyrillic', () {
      expect(containsArabic('Привет'), isFalse);
    });

    test('returns false for empty string', () {
      expect(containsArabic(''), isFalse);
    });

    test('returns false for null', () {
      expect(containsArabic(null), isFalse);
    });

    test('returns false for Hebrew', () {
      expect(containsArabic('שלום'), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // containsHebrew
  // ═══════════════════════════════════════════════════════════════════════════

  group('containsHebrew', () {
    test('returns true for Hebrew text', () {
      expect(containsHebrew('שלום עולם'), isTrue);
    });

    test('returns true for mixed Hebrew and Latin', () {
      expect(containsHebrew('Hello שלום World'), isTrue);
    });

    test('returns false for English', () {
      expect(containsHebrew('Hello world'), isFalse);
    });

    test('returns false for Japanese', () {
      expect(containsHebrew('こんにちは'), isFalse);
    });

    test('returns false for Korean', () {
      expect(containsHebrew('안녕하세요'), isFalse);
    });

    test('returns false for Cyrillic', () {
      expect(containsHebrew('Привет'), isFalse);
    });

    test('returns false for Arabic', () {
      expect(containsHebrew('مرحبا'), isFalse);
    });

    test('returns false for empty string', () {
      expect(containsHebrew(''), isFalse);
    });

    test('returns false for null', () {
      expect(containsHebrew(null), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // containsRomanizableText — unified check
  // ═══════════════════════════════════════════════════════════════════════════

  group('containsRomanizableText', () {
    test('returns true for Japanese', () {
      expect(containsRomanizableText('こんにちは'), isTrue);
    });

    test('returns true for Korean', () {
      expect(containsRomanizableText('안녕하세요'), isTrue);
    });

    test('returns true for Chinese', () {
      expect(containsRomanizableText('你好世界'), isTrue);
    });

    test('returns true for Cyrillic', () {
      expect(containsRomanizableText('Привет мир'), isTrue);
    });

    test('returns true for Arabic', () {
      expect(containsRomanizableText('مرحبا بالعالم'), isTrue);
    });

    test('returns true for Hebrew', () {
      expect(containsRomanizableText('שלום עולם'), isTrue);
    });

    test('returns false for English', () {
      expect(containsRomanizableText('Hello world'), isFalse);
    });

    test('returns false for empty string', () {
      expect(containsRomanizableText(''), isFalse);
    });

    test('returns false for null', () {
      expect(containsRomanizableText(null), isFalse);
    });

    test('returns false for Latin-only text', () {
      expect(containsRomanizableText('Arigatou sayounara'), isFalse);
    });
  });
}
