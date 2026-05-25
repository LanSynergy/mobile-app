import 'package:flutter_test/flutter_test.dart';
import 'package:aetherfin/core/local/m3u_parser.dart';

void main() {
  group('M3uParser', () {
    group('parse', () {
      test('parses standard M3U (just paths)', () {
        const content = '''file1.mp3
file2.mp3
file3.mp3''';
        final entries = M3uParser.parse(content);
        expect(entries.length, 3);
        expect(entries[0].path, 'file1.mp3');
        expect(entries[1].path, 'file2.mp3');
        expect(entries[2].path, 'file3.mp3');
      });

      test('parses extended M3U with EXTINF entries', () {
        const content = '''#EXTM3U
#EXTINF:301,Radiohead - Karma Police
/radiohead/karma_police.mp3
#EXTINF:-1,TV Girl - Lovers Rock
/tvgirl/lovers_rock.flac''';
        final entries = M3uParser.parse(content);
        expect(entries.length, 2);
        expect(entries[0].title, 'Karma Police');
        expect(entries[0].artist, 'Radiohead');
        expect(entries[0].duration?.inSeconds, 301);
        expect(entries[0].path, '/radiohead/karma_police.mp3');
        expect(entries[1].title, 'Lovers Rock');
        expect(entries[1].artist, 'TV Girl');
      });

      test('parses Aetherfin-format M3U with custom tags', () {
        const content = '''#EXTM3U
# Aetherfin:id:album-123
# Aetherfin:source:jellyfin
#EXTINF:245,Artist - Song
/song.mp3''';
        final entries = M3uParser.parse(content);
        expect(entries.length, 1);
        expect(entries[0].tags['id'], 'album-123');
        expect(entries[0].tags['source'], 'jellyfin');
      });

      test('handles comments and blank lines', () {
        const content = '''#EXTM3U
# This is a comment

file1.mp3

# Another comment
file2.mp3''';
        final entries = M3uParser.parse(content);
        expect(entries.length, 2);
        expect(entries[0].path, 'file1.mp3');
        expect(entries[1].path, 'file2.mp3');
      });

      test('handles relative paths', () {
        const content = '''./music/file1.mp3
../shared/file2.mp3
subdir/file3.mp3''';
        final entries = M3uParser.parse(content);
        expect(entries.length, 3);
        expect(entries[0].path, './music/file1.mp3');
        expect(entries[1].path, '../shared/file2.mp3');
        expect(entries[2].path, 'subdir/file3.mp3');
      });

      test('returns empty list for empty content', () {
        expect(M3uParser.parse(''), isEmpty);
        expect(M3uParser.parse('   '), isEmpty);
        expect(M3uParser.parse('\n\n\n'), isEmpty);
      });

      test('handles corrupt EXTINF line without crash', () {
        const content = '''#EXTINF:notanumber
/path/to/file.mp3''';
        final entries = M3uParser.parse(content);
        expect(entries.length, 1);
        expect(entries[0].duration, isNull);
        expect(entries[0].path, '/path/to/file.mp3');
      });
    });

    group('write', () {
      test('writes M3U with EXTINF entries by default', () {
        final entries = [
          M3UEntry(
            title: 'Karma Police',
            artist: 'Radiohead',
            duration: Duration(seconds: 301),
            path: '/radiohead/karma_police.mp3',
          ),
        ];
        final result = M3uParser.write(entries);
        expect(result, contains('#EXTM3U'));
        expect(result, contains('#EXTINF:301,Radiohead - Karma Police'));
        expect(result, contains('/radiohead/karma_police.mp3'));
      });

      test('writes M3U without EXTINF when disabled', () {
        final entries = [
          M3UEntry(path: '/radiohead/karma_police.mp3'),
        ];
        final result = M3uParser.write(entries, options: const M3uWriteOptions(includeExtInf: false));
        expect(result, contains('#EXTM3U'));
        expect(result, contains('/radiohead/karma_police.mp3'));
        expect(result, isNot(contains('#EXTINF')));
      });

      test('round-trip: write then parse produces same data', () {
        final originalEntries = [
          M3UEntry(
            title: 'Karma Police',
            artist: 'Radiohead',
            duration: Duration(seconds: 301),
            path: '/radiohead/karma_police.mp3',
          ),
          M3UEntry(
            title: 'Lovers Rock',
            artist: 'TV Girl',
            duration: Duration(seconds: 209),
            path: '/tvgirl/lovers_rock.flac',
          ),
        ];
        final m3u = M3uParser.write(originalEntries);
        final parsed = M3uParser.parse(m3u);
        expect(parsed.length, originalEntries.length);
        expect(parsed[0].title, originalEntries[0].title);
        expect(parsed[0].artist, originalEntries[0].artist);
        expect(parsed[0].duration?.inSeconds, originalEntries[0].duration?.inSeconds);
        expect(parsed[0].path, originalEntries[0].path);
      });
    });
  });
}
