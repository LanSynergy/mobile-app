import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import '../../helpers/fake_player.dart';

void main() {
  setUpAll(() {
    registerFallbackValue(Duration.zero);
    registerFallbackValue(Device.auto);
    registerFallbackValue(Loop.off);
    registerFallbackValue(Gapless.weak);
    registerFallbackValue(SpectrumSettings.defaults);
    registerFallbackValue(const Media(''));
    registerFallbackValue(<Media>[]);
    registerFallbackValue(const AudioEffects());
  });

  group('PlayerService API surface', () {
    test('MockPlayer can be created without throwing', () {
      final mock = createMockPlayer();
      expect(mock.player, isNotNull);
      expect(mock.ctrls, isNotNull);
    });

    test('MockPlayer streams can be listened to without throwing', () async {
      final mock = createMockPlayer();
      final player = mock.player;
      final ctrls = mock.ctrls;

      // Create .first futures BEFORE adding values. Broadcast stream
      // controllers don't replay values to listeners attached after .add().
      final fPlaying = player.stream.playing.first;
      final fPosition = player.stream.position.first;
      final fCompleted = player.stream.completed.first;
      final fPlaylist = player.stream.playlist.first;
      final fLoop = player.stream.loop.first;
      final fRate = player.stream.rate.first;
      final fShuffle = player.stream.shuffle.first;
      final fBuffering = player.stream.buffering.first;
      final fDuration = player.stream.duration.first;
      final fCoverArt = player.stream.coverArt.first;

      // Now add values — the listeners created by .first above will receive them.
      ctrls.playing.add(false);
      ctrls.position.add(Duration.zero);
      ctrls.completed.add(false);
      ctrls.playlist.add(const Playlist(<Media>[]));
      ctrls.loop.add(Loop.off);
      ctrls.rate.add(1.0);
      ctrls.shuffle.add(false);
      ctrls.buffering.add(false);
      ctrls.duration.add(Duration.zero);
      ctrls.coverArt.add(null);

      // Await all futures — they should complete once the microtask delivers events.
      final results = await Future.wait([
        fPlaying,
        fPosition,
        fCompleted,
        fPlaylist,
        fLoop,
        fRate,
        fShuffle,
        fBuffering,
        fDuration,
        fCoverArt,
      ]);

      expect(results.length, 10);
    });

    test('MockPlayer API methods return without throwing', () async {
      final mock = createMockPlayer();
      final player = mock.player;

      // Stub additional methods not covered by createMockPlayer()
      when(() => player.setVolume(any())).thenAnswer((_) async {});
      when(() => player.setMute(any())).thenAnswer((_) async {});
      when(() => player.setAudioEffects(any())).thenAnswer((_) async {});
      when(() => player.updateAudioEffects(any())).thenAnswer((_) async {});

      await Future.wait([
        player.openAll(<Media>[], index: 0, play: true),
        player.play(),
        player.pause(),
        player.seek(Duration.zero),
        player.next(),
        player.previous(),
        player.stop(),
        player.setVolume(0.5),
        player.setMute(false),
        player.setAudioDriver('aaudio'),
        player.setAudioBuffer(const Duration(milliseconds: 200)),
      ]);
    });

    test('AudioEffects set and update do not throw', () async {
      final mock = createMockPlayer();
      final player = mock.player;

      when(() => player.setAudioEffects(any())).thenAnswer((_) async {});
      when(() => player.updateAudioEffects(any())).thenAnswer((_) async {});

      const effects = AudioEffects();

      await player.setAudioEffects(effects);
      await player.updateAudioEffects((_) => effects);
    });
  });
}
