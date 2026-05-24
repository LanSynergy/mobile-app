import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import 'package:aetherfin/core/audio/media_session_bridge.dart';
import 'package:aetherfin/core/audio/player_service.dart';
import 'package:aetherfin/core/jellyfin/models/items.dart';
import 'helpers/fake_player.dart';

class MockMethodChannel extends Mock implements MethodChannel {}

typedef _StateUpdater = void Function(PlayerState Function(PlayerState) updater);

({
  AfPlayerService service,
  NativeMediaSessionBridge bridge,
  MockPlayer player,
  StreamControllers ctrls,
  MockMethodChannel channel,
  _StateUpdater updateState,
}) _createFixture() {
  final result = createMockPlayer();
  final player = result.player;
  final ctrls = result.ctrls;
  final channel = MockMethodChannel();

  var mutableState = const PlayerState();
  when(() => player.state).thenAnswer((_) => mutableState);
  void updateState(PlayerState Function(PlayerState) updater) {
    mutableState = updater(mutableState);
  }

  when(() => channel.invokeMethod(any())).thenAnswer((_) async => null);
  when(() => channel.invokeMethod(any(), any())).thenAnswer((_) async => null);
  when(() => channel.setMethodCallHandler(any())).thenAnswer((_) async {});

  final bridge = NativeMediaSessionBridge(channel: channel);
  final service = AfPlayerService.test(
    player: player,
    bridge: bridge,
  );

  return (
    service: service,
    bridge: bridge,
    player: player,
    ctrls: ctrls,
    channel: channel,
    updateState: updateState,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Completed handler race conditions & serialization', () {
    late AfPlayerService service;
    late MockPlayer player;
    late StreamControllers ctrls;
    late _StateUpdater updateState;
    late List<String> events;

    const trackA = AfTrack(
      id: '1',
      title: 'Track A',
      artistName: 'Test Artist',
      albumName: 'Test Album',
    );
    const trackB = AfTrack(
      id: '2',
      title: 'Track B',
      artistName: 'Test Artist',
      albumName: 'Test Album',
    );
    const trackC = AfTrack(
      id: '3',
      title: 'Track C',
      artistName: 'Test Artist',
      albumName: 'Test Album',
    );

    setUpAll(() {
      registerFallbackValue(Duration.zero);
      registerFallbackValue(Device.auto);
      registerFallbackValue(Loop.off);
      registerFallbackValue(Gapless.weak);
      registerFallbackValue(SpectrumSettings.defaults);
      registerFallbackValue(const Media(''));
      registerFallbackValue(<Media>[]);
    });

    setUp(() async {
      final fixture = _createFixture();
      service = fixture.service;
      player = fixture.player;
      ctrls = fixture.ctrls;
      updateState = fixture.updateState;
      events = <String>[];

      // Stub methods called during playback setup
      when(() => player.setAudioDevice(any())).thenAnswer((_) async {});
      when(() => player.setAudioExclusive(any())).thenAnswer((_) async {});
      when(() => player.setAudioSampleRate(any())).thenAnswer((_) async {});
      when(() => player.setPrefetchPlaylist(any())).thenAnswer((_) async {});
      when(() => player.setRate(any())).thenAnswer((_) async {});
      when(() => player.setGapless(any())).thenAnswer((_) async {});
      when(() => player.setLoop(any())).thenAnswer((_) async {});
      when(() => player.setShuffle(any())).thenAnswer((_) async {});

      // Stub methods to track execution order with delays
      when(() => player.jump(any())).thenAnswer((invocation) async {
        final index = invocation.positionalArguments[0] as int;
        events.add('jump_start_$index');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        updateState((s) => s.copyWith(
              playlist: Playlist(
                s.playlist.items,
                index: index,
              ),
            ));
        ctrls.playlist.add(
          Playlist(
            [
              const Media('https://example.com/1.flac'),
              const Media('https://example.com/2.flac'),
              const Media('https://example.com/3.flac'),
            ],
            index: index,
          ),
        );
        events.add('jump_end_$index');
      });

      when(() => player.next()).thenAnswer((_) async {
        events.add('next_start');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final nextIndex = player.state.playlist.index + 1;
        updateState((s) => s.copyWith(
              playlist: Playlist(
                s.playlist.items,
                index: nextIndex,
              ),
            ));
        ctrls.playlist.add(
          Playlist(
            [
              const Media('https://example.com/1.flac'),
              const Media('https://example.com/2.flac'),
              const Media('https://example.com/3.flac'),
            ],
            index: nextIndex,
          ),
        );
        events.add('next_end');
      });

      when(() => player.previous()).thenAnswer((_) async {
        events.add('previous_start');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final prevIndex = player.state.playlist.index - 1;
        updateState((s) => s.copyWith(
              playlist: Playlist(
                s.playlist.items,
                index: prevIndex,
              ),
            ));
        ctrls.playlist.add(
          Playlist(
            [
              const Media('https://example.com/1.flac'),
              const Media('https://example.com/2.flac'),
              const Media('https://example.com/3.flac'),
            ],
            index: prevIndex,
          ),
        );
        events.add('previous_end');
      });

      when(() => player.play()).thenAnswer((_) async {
        events.add('play_start');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        events.add('play_end');
      });

      when(() => player.pause()).thenAnswer((_) async {
        events.add('pause_start');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        events.add('pause_end');
      });

      when(() => player.seek(any())).thenAnswer((invocation) async {
        final pos = invocation.positionalArguments[0] as Duration;
        events.add('seek_start_${pos.inMilliseconds}');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        events.add('seek_end_${pos.inMilliseconds}');
      });

      when(() => player.stop()).thenAnswer((_) async {
        events.add('stop_start');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        events.add('stop_end');
      });

      // Populate queue
      await service.playQueue(
        [trackA, trackB, trackC],
        startIndex: 0,
        resolveStreamUrl: (t) => 'https://example.com/${t.id}.flac',
      );

      ctrls.playlist.add(
        const Playlist(
          [
            Media('https://example.com/1.flac'),
            Media('https://example.com/2.flac'),
            Media('https://example.com/3.flac'),
          ],
          index: 0,
        ),
      );

      await Future<void>.delayed(Duration.zero);
      events.clear();
    });

    tearDown(() async {
      await service.dispose();
      ctrls.dispose();
    });

    test('completed handler and skipToNext run sequentially without interleaving', () async {
      updateState((s) => s.copyWith(
            playing: true,
            completed: true,
            loop: Loop.off,
            playlist: const Playlist(
              [
                Media('https://example.com/1.flac'),
                Media('https://example.com/2.flac'),
                Media('https://example.com/3.flac'),
              ],
              index: 0,
            ),
          ));

      ctrls.completed.add(true);
      await Future<void>.delayed(Duration.zero);
      final skipFut = service.skipToNext();

      await Future<void>.delayed(const Duration(milliseconds: 150));
      await skipFut;

      expect(
        events,
        containsAllInOrder([
          'jump_start_1',
          'jump_end_1',
          'next_start',
          'next_end',
        ]),
      );

      final indexStart1 = events.indexOf('jump_start_1');
      final indexEnd1 = events.indexOf('jump_end_1');
      final indexStart2 = events.indexOf('next_start');
      final indexEnd2 = events.indexOf('next_end');

      expect(indexStart1, lessThan(indexEnd1));
      expect(indexEnd1, lessThan(indexStart2));
      expect(indexStart2, lessThan(indexEnd2));
    });

    test('completed handler and skipToQueueItem run sequentially without interleaving', () async {
      updateState((s) => s.copyWith(
            playing: true,
            completed: true,
            loop: Loop.off,
            playlist: const Playlist(
              [
                Media('https://example.com/1.flac'),
                Media('https://example.com/2.flac'),
                Media('https://example.com/3.flac'),
              ],
              index: 0,
            ),
          ));

      ctrls.completed.add(true);
      await Future<void>.delayed(Duration.zero);
      final skipFut = service.skipToQueueItem(2);

      await Future<void>.delayed(const Duration(milliseconds: 150));
      await skipFut;

      expect(
        events,
        containsAllInOrder([
          'jump_start_1',
          'jump_end_1',
          'jump_start_2',
          'jump_end_2',
        ]),
      );

      final indexStart1 = events.indexOf('jump_start_1');
      final indexEnd1 = events.indexOf('jump_end_1');
      final indexStart2 = events.indexOf('jump_start_2');
      final indexEnd2 = events.indexOf('jump_end_2');

      expect(indexStart1, lessThan(indexEnd1));
      expect(indexEnd1, lessThan(indexStart2));
      expect(indexStart2, lessThan(indexEnd2));
    });

    test('completed handler (stop) and play run sequentially', () async {
      ctrls.playlist.add(
        const Playlist(
          [
            Media('https://example.com/1.flac'),
            Media('https://example.com/2.flac'),
            Media('https://example.com/3.flac'),
          ],
          index: 2,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      events.clear();

      updateState((s) => s.copyWith(
            playing: true,
            completed: true,
            loop: Loop.off,
            playlist: const Playlist(
              [
                Media('https://example.com/1.flac'),
                Media('https://example.com/2.flac'),
                Media('https://example.com/3.flac'),
              ],
              index: 2,
            ),
          ));

      ctrls.completed.add(true);
      await Future<void>.delayed(Duration.zero);
      final playFut = service.play();

      await Future<void>.delayed(const Duration(milliseconds: 150));
      await playFut;

      expect(
        events,
        containsAllInOrder([
          'stop_start',
          'stop_end',
          'play_start',
          'play_end',
        ]),
      );

      final indexStopStart = events.indexOf('stop_start');
      final indexStopEnd = events.indexOf('stop_end');
      final indexPlayStart = events.indexOf('play_start');
      final indexPlayEnd = events.indexOf('play_end');

      expect(indexStopStart, lessThan(indexStopEnd));
      expect(indexStopEnd, lessThan(indexPlayStart));
      expect(indexPlayStart, lessThan(indexPlayEnd));
    });

    test('completed handler (jump) and seek run sequentially', () async {
      updateState((s) => s.copyWith(
            playing: true,
            completed: true,
            loop: Loop.off,
            playlist: const Playlist(
              [
                Media('https://example.com/1.flac'),
                Media('https://example.com/2.flac'),
                Media('https://example.com/3.flac'),
              ],
              index: 0,
            ),
          ));

      ctrls.completed.add(true);
      await Future<void>.delayed(Duration.zero);
      final seekFut = service.seek(const Duration(seconds: 10));

      await Future<void>.delayed(const Duration(milliseconds: 150));
      await seekFut;

      expect(
        events,
        containsAllInOrder([
          'jump_start_1',
          'jump_end_1',
          'seek_start_10000',
          'seek_end_10000',
        ]),
      );

      final indexJumpStart = events.indexOf('jump_start_1');
      final indexJumpEnd = events.indexOf('jump_end_1');
      final indexSeekStart = events.indexOf('seek_start_10000');
      final indexSeekEnd = events.indexOf('seek_end_10000');

      expect(indexJumpStart, lessThan(indexJumpEnd));
      expect(indexJumpEnd, lessThan(indexSeekStart));
      expect(indexSeekStart, lessThan(indexSeekEnd));
    });
  });
}
