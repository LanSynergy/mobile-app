import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import 'package:aetherfin/core/audio/player_service.dart';
import 'package:aetherfin/core/jellyfin/models/items.dart';
import 'helpers/fake_player.dart';

class MockMethodChannel extends Mock implements MethodChannel {}

void main() {
  group('Settings race guards on AfPlayerService', () {
    late AfPlayerService service;
    late MockPlayer player;
    late MockMethodChannel channel;
    late StreamControllers ctrls;

    setUpAll(() {
      registerFallbackValue(Duration.zero);
      registerFallbackValue(Device.auto);
      registerFallbackValue(Loop.off);
      registerFallbackValue(Gapless.weak);
      registerFallbackValue(SpectrumSettings.defaults);
      registerFallbackValue(Media(''));
    });

    setUp(() async {
      final fixture = createMockPlayer();
      player = fixture.player;
      ctrls = fixture.ctrls;
      channel = MockMethodChannel();
      when(() => channel.setMethodCallHandler(any())).thenAnswer((_) async {});
      service = AfPlayerService.test(player: player, channel: channel);

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
      final track = const AfTrack(
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
        Playlist(
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

    group('isLoadingQueue guard', () {
      test('skips settings actions when isLoadingQueue is true', () async {
        service.isLoadingQueueForTesting = true;

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

      test('allows settings actions when isLoadingQueue is false', () async {
        service.isLoadingQueueForTesting = false;

        await service.setAudioDevice(Device.auto);
        verify(() => player.setAudioDevice(Device.auto)).called(1);

        await service.setAudioExclusive(true);
        verify(() => player.setAudioExclusive(true)).called(1);

        await service.setAudioSampleRate(44100);
        verify(() => player.setAudioSampleRate(44100)).called(1);

        await service.setPrefetchPlaylist(true);
        verify(() => player.setPrefetchPlaylist(true)).called(1);

        await service.setAfSpeed(1.5);
        verify(() => player.setRate(1.5)).called(1);

        await service.setGapless(Gapless.weak);
        verify(() => player.setGapless(Gapless.weak)).called(1);

        await service.setAfLoopMode(Loop.file);
        verify(() => player.setLoop(Loop.file)).called(1);

        await service.setAfShuffleMode(true);
        verify(() => player.setShuffle(true)).called(1);
      });
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

    group('combined priority guards', () {
      test('disposed check takes priority over isLoadingQueue check', () async {
        service.disposedForTesting = true;
        service.isLoadingQueueForTesting = false;

        await service.setAudioDevice(Device.auto);
        expect(service.isDisposedForTesting, isTrue);
        expect(service.isLoadingQueue, isFalse);
        verifyNever(() => player.setAudioDevice(any()));
      });
    });
  });
}
