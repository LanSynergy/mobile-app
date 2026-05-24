import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import 'package:aetherfin/core/audio/media_session_bridge.dart';
import 'package:aetherfin/core/audio/player_service.dart';
import 'package:aetherfin/core/jellyfin/models/items.dart';
import 'helpers/fake_player.dart';

class MockMethodChannel extends Mock implements MethodChannel {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Settings Race Guard - player_service', () {
    late MockPlayer player;
    late StreamControllers ctrls;
    late MockMethodChannel channel;
    late AfPlayerService service;

    setUpAll(() {
      registerFallbackValue(Duration.zero);
      registerFallbackValue(Device.auto);
      registerFallbackValue(Loop.off);
      registerFallbackValue(Gapless.weak);
      registerFallbackValue(SpectrumSettings.defaults);
      registerFallbackValue(const Media(''));
    });

    setUp(() async {
      final fixture = createMockPlayer();
      player = fixture.player;
      ctrls = fixture.ctrls;
      channel = MockMethodChannel();
      when(() => channel.setMethodCallHandler(any())).thenAnswer((_) async {});
      final bridge = NativeMediaSessionBridge(channel: channel);
      service = AfPlayerService.test(player: player, bridge: bridge);

      // Stub player methods called by the guarded settings setters
      when(() => player.setAudioDevice(any())).thenAnswer((_) async {});
      when(() => player.setAudioExclusive(any())).thenAnswer((_) async {});
      when(() => player.setAudioSampleRate(any())).thenAnswer((_) async {});
      when(() => player.setPrefetchPlaylist(any())).thenAnswer((_) async {});
      when(() => player.setRate(any())).thenAnswer((_) async {});
      when(() => player.setGapless(any())).thenAnswer((_) async {});
      when(() => player.setLoop(any())).thenAnswer((_) async {});
      when(() => player.setShuffle(any())).thenAnswer((_) async {});

      // Populate queue so settings actions are allowed
      const track = AfTrack(
        id: '1',
        title: 'Track A',
        artistName: 'Test Artist',
        albumName: 'Test Album',
      );
      await service.playQueue(
        [track],
        startIndex: 0,
        resolveStreamUrl: (t) => 'https://example.com/1.flac',
      );
      ctrls.playlist.add(
        const Playlist(
          [Media('https://example.com/1.flac')],
          index: 0,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      clearInteractions(player);
    });

    tearDown(() async {
      await service.dispose();
      ctrls.dispose();
    });

    group('disposed guard', () {
      test('skips settings actions when disposed is true', () async {
        service.disposedForTesting = true;

        await service.setAudioDevice(Device.auto);
        verifyNever(() => player.setAudioDevice(any()));

        await service.setAudioExclusive(true);
        verifyNever(() => player.setAudioExclusive(any()));

        await service.setAudioSampleRate(44100);
        verifyNever(() => player.setAudioSampleRate(any()));

        await service.setPrefetchPlaylist(true);
        verifyNever(() => player.setPrefetchPlaylist(any()));

        await service.setAfSpeed(1.5);
        verifyNever(() => player.setRate(any()));

        await service.setGapless(Gapless.weak);
        verifyNever(() => player.setGapless(any()));

        await service.setAfLoopMode(Loop.file);
        verifyNever(() => player.setLoop(any()));

        await service.setAfShuffleMode(true);
        verifyNever(() => player.setShuffle(any()));
      });
    });


  });
}
