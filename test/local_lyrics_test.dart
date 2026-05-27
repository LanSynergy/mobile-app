import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:aetherfin/core/local/local_backend.dart';
import 'package:aetherfin/core/local/local_db.dart';
import 'package:aetherfin/core/local/local_library.dart';
import 'package:aetherfin/core/lyrics/embedded_lyrics_parser.dart';

class MockLocalLibrary extends Mock implements LocalLibrary {}
class MockLocalDb extends Mock implements LocalDb {}

void main() {
  late Directory tempDir;
  late MockLocalLibrary mockLibrary;
  late MockLocalDb mockDb;
  late LocalBackend localBackend;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('aetherfin_lyrics_test');
    mockLibrary = MockLocalLibrary();
    mockDb = MockLocalDb();
    localBackend = LocalBackend(library: mockLibrary, db: mockDb);
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  group('Sidecar LRC lyrics', () {
    test('resolves and reads lowercase sidecar .lrc file', () async {
      final audioFile = File(p.join(tempDir.path, 'song.mp3'));
      await audioFile.writeAsString('audio-mock');
      
      final lrcFile = File(p.join(tempDir.path, 'song.lrc'));
      const lyricsText = '[00:10.00]Hello sidecar lyrics\n[00:15.00]Line two';
      await lrcFile.writeAsString(lyricsText);

      final result = await localBackend.lyrics(audioFile.path);
      expect(result, equals(lyricsText));
    });

    test('resolves and reads uppercase sidecar .LRC file', () async {
      final audioFile = File(p.join(tempDir.path, 'song.flac'));
      await audioFile.writeAsString('audio-mock');
      
      final lrcFile = File(p.join(tempDir.path, 'song.LRC'));
      const lyricsText = '[00:10.00]Hello uppercase sidecar';
      await lrcFile.writeAsString(lyricsText);

      final result = await localBackend.lyrics(audioFile.path);
      expect(result, equals(lyricsText));
    });

    test('saveSidecarLrc writes lyrics to sidecar .lrc file', () async {
      final audioFile = File(p.join(tempDir.path, 'song.mp3'));
      await audioFile.writeAsString('audio-mock');
      
      const lyricsText = 'New saved lyrics';
      final success = await localBackend.saveSidecarLrc(audioFile.path, lyricsText);
      expect(success, isTrue);

      final lrcFile = File(p.join(tempDir.path, 'song.lrc'));
      expect(await lrcFile.exists(), isTrue);
      expect(await lrcFile.readAsString(), equals(lyricsText));
    });
  });

  group('Embedded lyrics parsing', () {
    test('extracts USLT lyrics from MP3 file', () async {
      final audioFile = File(p.join(tempDir.path, 'embedded.mp3'));
      
      // Build ID3v2.3 tag with USLT frame
      const text = 'Hello USLT Lyrics';
      final textBytes = Uint8List.fromList(text.codeUnits);
      
      // USLT frame body: 1 byte encoding (3 = UTF-8), 3 bytes language ('eng'), 1 byte descriptor null terminator (0), then text
      final usltBody = Uint8List(1 + 3 + 1 + textBytes.length);
      usltBody[0] = 3; // encoding: UTF-8
      usltBody[1] = 0x65; // 'e'
      usltBody[2] = 0x6E; // 'n'
      usltBody[3] = 0x67; // 'g'
      usltBody[4] = 0x00; // descriptor null terminator
      usltBody.setRange(5, usltBody.length, textBytes);
      
      final usltFrameSize = usltBody.length;
      
      // USLT Frame Header: 4 bytes 'USLT', 4 bytes size, 2 bytes flags
      final usltFrame = Uint8List(10 + usltFrameSize);
      usltFrame.setRange(0, 4, [0x55, 0x53, 0x4C, 0x54]); // 'USLT'
      usltFrame[4] = (usltFrameSize >> 24) & 0xFF;
      usltFrame[5] = (usltFrameSize >> 16) & 0xFF;
      usltFrame[6] = (usltFrameSize >> 8) & 0xFF;
      usltFrame[7] = usltFrameSize & 0xFF;
      usltFrame[8] = 0;
      usltFrame[9] = 0;
      usltFrame.setRange(10, usltFrame.length, usltBody);
      
      // ID3v2 Tag Header: 3 bytes 'ID3', 2 bytes version (3, 0), 1 byte flags, 4 bytes tag size (synchsafe)
      final id3Size = usltFrame.length;
      final id3SizeSynchsafe = [
        (id3Size >> 21) & 0x7F,
        (id3Size >> 14) & 0x7F,
        (id3Size >> 7) & 0x7F,
        id3Size & 0x7F,
      ];
      
      final tagHeader = Uint8List(10);
      tagHeader.setRange(0, 3, [0x49, 0x44, 0x33]); // 'ID3'
      tagHeader[3] = 3; // version 2.3
      tagHeader[4] = 0;
      tagHeader[5] = 0; // flags
      tagHeader.setRange(6, 10, id3SizeSynchsafe);
      
      final mp3Bytes = BytesBuilder();
      mp3Bytes.add(tagHeader);
      mp3Bytes.add(usltFrame);
      // Dummy audio payload
      mp3Bytes.add([0xFF, 0xFB, 0x90, 0x44]);
      
      await audioFile.writeAsBytes(mp3Bytes.toBytes());
      
      final result = await EmbeddedLyricsParser.extractLyrics(audioFile.path);
      expect(result, equals(text));
    });

    test('extracts Vorbis comment lyrics from FLAC file', () async {
      final audioFile = File(p.join(tempDir.path, 'embedded.flac'));
      
      // Comment: "LYRICS=Hello FLAC Lyrics"
      const commentStr = 'LYRICS=Hello FLAC Lyrics';
      final commentBytes = Uint8List.fromList(commentStr.codeUnits);
      
      // Vorbis comment block body:
      // - vendor string length (4 bytes LE) -> 0
      // - vendor string (0 bytes)
      // - comment count (4 bytes LE) -> 1
      // - comment 1 length (4 bytes LE) -> commentStr.length
      // - comment 1 bytes
      final commentBody = BytesBuilder();
      commentBody.add([0, 0, 0, 0]); // vendor len
      commentBody.add([1, 0, 0, 0]); // comment count = 1
      final len = commentBytes.length;
      commentBody.add([
        len & 0xFF,
        (len >> 8) & 0xFF,
        (len >> 16) & 0xFF,
        (len >> 24) & 0xFF,
      ]);
      commentBody.add(commentBytes);
      
      final blockData = commentBody.toBytes();
      
      // FLAC block header:
      // - 1 byte block header (last block flag = 1, type = 4 VORBIS_COMMENT) -> 0x84
      // - 3 bytes length
      final blockHeader = Uint8List(4);
      blockHeader[0] = 0x84;
      blockHeader[1] = (blockData.length >> 16) & 0xFF;
      blockHeader[2] = (blockData.length >> 8) & 0xFF;
      blockHeader[3] = blockData.length & 0xFF;
      
      final flacBytes = BytesBuilder();
      flacBytes.add([0x66, 0x4C, 0x61, 0x43]); // 'fLaC'
      flacBytes.add(blockHeader);
      flacBytes.add(blockData);
      
      await audioFile.writeAsBytes(flacBytes.toBytes());
      
      final result = await EmbeddedLyricsParser.extractLyrics(audioFile.path);
      expect(result, equals('Hello FLAC Lyrics'));
    });

    test('extracts lyrics from M4A file ©lyr atom', () async {
      final audioFile = File(p.join(tempDir.path, 'embedded.m4a'));
      
      const lyrics = 'Hello M4A Lyrics';
      final lyricsBytes = Uint8List.fromList(lyrics.codeUnits);
      
      // data atom inside ©lyr atom
      final dataBody = BytesBuilder();
      dataBody.add([0, 0, 0, 1]); // type: UTF-8
      dataBody.add([0, 0, 0, 0]); // flags/locale
      dataBody.add(lyricsBytes);
      final dataBodyBytes = dataBody.toBytes();
      final dataAtomSize = 8 + dataBodyBytes.length;
      final dataAtom = BytesBuilder();
      dataAtom.add([
        (dataAtomSize >> 24) & 0xFF,
        (dataAtomSize >> 16) & 0xFF,
        (dataAtomSize >> 8) & 0xFF,
        dataAtomSize & 0xFF,
      ]);
      dataAtom.add(Uint8List.fromList('data'.codeUnits));
      dataAtom.add(dataBodyBytes);
      final dataAtomBytes = dataAtom.toBytes();
      
      // ©lyr atom
      final lyrAtomSize = 8 + dataAtomBytes.length;
      final lyrAtom = BytesBuilder();
      lyrAtom.add([
        (lyrAtomSize >> 24) & 0xFF,
        (lyrAtomSize >> 16) & 0xFF,
        (lyrAtomSize >> 8) & 0xFF,
        lyrAtomSize & 0xFF,
      ]);
      lyrAtom.add([0xA9, 0x6C, 0x79, 0x72]); // '©lyr'
      lyrAtom.add(dataAtomBytes);
      final lyrAtomBytes = lyrAtom.toBytes();
      
      // ilst atom
      final ilstAtomSize = 8 + lyrAtomBytes.length;
      final ilstAtom = BytesBuilder();
      ilstAtom.add([
        (ilstAtomSize >> 24) & 0xFF,
        (ilstAtomSize >> 16) & 0xFF,
        (ilstAtomSize >> 8) & 0xFF,
        ilstAtomSize & 0xFF,
      ]);
      ilstAtom.add(Uint8List.fromList('ilst'.codeUnits));
      ilstAtom.add(lyrAtomBytes);
      final ilstAtomBytes = ilstAtom.toBytes();
      
      // meta atom
      final metaAtomSize = 8 + 4 + ilstAtomBytes.length;
      final metaAtom = BytesBuilder();
      metaAtom.add([
        (metaAtomSize >> 24) & 0xFF,
        (metaAtomSize >> 16) & 0xFF,
        (metaAtomSize >> 8) & 0xFF,
        metaAtomSize & 0xFF,
      ]);
      metaAtom.add(Uint8List.fromList('meta'.codeUnits));
      metaAtom.add([0, 0, 0, 0]); // dummy header
      metaAtom.add(ilstAtomBytes);
      final metaAtomBytes = metaAtom.toBytes();
      
      // udta atom
      final udtaAtomSize = 8 + metaAtomBytes.length;
      final udtaAtom = BytesBuilder();
      udtaAtom.add([
        (udtaAtomSize >> 24) & 0xFF,
        (udtaAtomSize >> 16) & 0xFF,
        (udtaAtomSize >> 8) & 0xFF,
        udtaAtomSize & 0xFF,
      ]);
      udtaAtom.add(Uint8List.fromList('udta'.codeUnits));
      udtaAtom.add(metaAtomBytes);
      final udtaAtomBytes = udtaAtom.toBytes();
      
      // moov atom
      final moovAtomSize = 8 + udtaAtomBytes.length;
      final moovAtom = BytesBuilder();
      moovAtom.add([
        (moovAtomSize >> 24) & 0xFF,
        (moovAtomSize >> 16) & 0xFF,
        (moovAtomSize >> 8) & 0xFF,
        moovAtomSize & 0xFF,
      ]);
      moovAtom.add(Uint8List.fromList('moov'.codeUnits));
      moovAtom.add(udtaAtomBytes);
      final moovAtomBytes = moovAtom.toBytes();
      
      // ftyp atom (dummy header of M4A file)
      final ftypAtom = BytesBuilder();
      ftypAtom.add([0, 0, 0, 20]);
      ftypAtom.add(Uint8List.fromList('ftyp'.codeUnits));
      ftypAtom.add(Uint8List.fromList('M4A '.codeUnits));
      ftypAtom.add([0, 0, 0, 0]);
      ftypAtom.add(Uint8List.fromList('mp42'.codeUnits));
      
      final m4aBytes = BytesBuilder();
      m4aBytes.add(ftypAtom.toBytes());
      m4aBytes.add(moovAtomBytes);
      
      await audioFile.writeAsBytes(m4aBytes.toBytes());
      
      final result = await EmbeddedLyricsParser.extractLyrics(audioFile.path);
      expect(result, equals(lyrics));
    });
  });
}
