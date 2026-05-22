import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import 'package:aetherfin/core/audio/audio_device_manager.dart';
import 'helpers/fake_player.dart';

void main() {
  setUpAll(() {
    registerFallbackValue(Duration.zero);
    registerFallbackValue(Device.auto);
    registerFallbackValue(AudioEffects());
    registerFallbackValue(Loop.off);
    registerFallbackValue(Gapless.weak);
    registerFallbackValue(SpectrumSettings.defaults);
    registerFallbackValue(Media(''));
  });

  group('AfAudioDeviceManager', () {
    late MockPlayer player;
    late StreamControllers ctrls;
    late AfAudioDeviceManager manager;

    setUp(() {
      final fixture = createMockPlayer();
      player = fixture.player;
      ctrls = fixture.ctrls;
      manager = AfAudioDeviceManager(player: player);
    });

    tearDown(() {
      manager.dispose();
      ctrls.dispose();
    });

    // -----------------------------------------------------------------------
    // isRealDeviceChange — deduplication
    // -----------------------------------------------------------------------
    group('isRealDeviceChange', () {
      test('returns true for first call with any name', () {
        expect(manager.isRealDeviceChange('aaudio'), isTrue);
      });

      test('returns false for duplicate name', () {
        manager.isRealDeviceChange('aaudio');
        expect(manager.isRealDeviceChange('aaudio'), isFalse);
      });

      test('returns true for a different name after a previous one', () {
        manager.isRealDeviceChange('aaudio');
        expect(manager.isRealDeviceChange('opensles'), isTrue);
      });

      test('returns true for same name after reset via new device', () {
        manager.isRealDeviceChange('aaudio');
        manager.isRealDeviceChange('opensles');
        // 'aaudio' is no longer the last observed device
        expect(manager.isRealDeviceChange('aaudio'), isTrue);
      });
    });

    // -----------------------------------------------------------------------
    // reapplyPersistedEffects
    // -----------------------------------------------------------------------
    group('reapplyPersistedEffects', () {
      test('re-applies current audio effects via setAudioEffects', () async {
        const effects = AudioEffects();
        when(() => player.state).thenReturn(
          const PlayerState(audioEffects: effects),
        );

        await manager.reapplyPersistedEffects();

        verify(() => player.setAudioEffects(effects)).called(1);
      });

      test('does nothing after dispose', () async {
        manager.dispose();
        await manager.reapplyPersistedEffects();

        verifyNever(() => player.setAudioEffects(any()));
      });

      test('handles setAudioEffects failure gracefully', () async {
        when(() => player.setAudioEffects(any())).thenThrow(Exception('mpv error'));

        // Should not throw — method catches internally
        await manager.reapplyPersistedEffects();
      });
    });

    // -----------------------------------------------------------------------
    // nudge — retry logic
    // -----------------------------------------------------------------------
    group('nudge', () {
      setUp(() {
        when(() => player.state).thenReturn(
          const PlayerState(
            audioDevice: Device(name: 'aaudio', description: 'AAudio'),
            audioDevices: [Device(name: 'auto', description: 'Auto'), Device(name: 'aaudio', description: 'AAudio')],
          ),
        );
      });

      test('fires setAudioDevice at least once within 1 second', () async {
        manager.nudge();
        await Future<void>.delayed(const Duration(milliseconds: 500));

        verify(() => player.setAudioDevice(any())).called(1);
      }, timeout: const Timeout(Duration(seconds: 5)));

      test('bails early and does not retry when already playing', () async {
        when(() => player.state).thenReturn(
          const PlayerState(
            playing: true,
            audioDevice: Device(name: 'aaudio', description: 'AAudio'),
            audioDevices: [Device(name: 'auto', description: 'Auto'), Device(name: 'aaudio', description: 'AAudio')],
          ),
        );

        manager.nudge();
        // Wait for first attempt (300ms) + some buffer
        await Future<void>.delayed(const Duration(seconds: 2));

        // Should fire exactly once and not retry (playing bail)
        verify(() => player.setAudioDevice(any())).called(1);
      }, timeout: const Timeout(Duration(seconds: 10)));

      test('retries when not playing — at least 2 calls within 2 seconds', () async {
        when(() => player.state).thenReturn(
          const PlayerState(
            playing: false,
            audioDevice: Device(name: 'aaudio', description: 'AAudio'),
            audioDevices: [Device(name: 'auto', description: 'Auto'), Device(name: 'aaudio', description: 'AAudio')],
          ),
        );

        manager.nudge();
        // Wait for first (300ms) + second (1000ms) = 1300ms
        await Future<void>.delayed(const Duration(seconds: 2));

        expect(
          verify(() => player.setAudioDevice(any())).callCount,
          greaterThanOrEqualTo(2),
        );
      }, timeout: const Timeout(Duration(seconds: 10)));

      test('all 3 retries fire within 5 seconds when not playing', () async {
        when(() => player.state).thenReturn(
          const PlayerState(
            playing: false,
            audioDevice: Device(name: 'aaudio', description: 'AAudio'),
            audioDevices: [Device(name: 'auto', description: 'Auto'), Device(name: 'aaudio', description: 'AAudio')],
          ),
        );

        manager.nudge();
        // Wait for all 3 retries (300 + 1000 + 2500 = 3800ms)
        await Future<void>.delayed(const Duration(seconds: 5));

        expect(
          verify(() => player.setAudioDevice(any())).callCount,
          greaterThanOrEqualTo(2),
        );
      }, timeout: const Timeout(Duration(seconds: 10)));

      test('selects non-auto device when current device is auto', () async {
        when(() => player.state).thenReturn(
          const PlayerState(
            playing: false,
            audioDevice: Device(name: 'auto', description: 'Autoselect'),
            audioDevices: [
              Device(name: 'auto', description: 'Autoselect'),
              Device(name: 'opensles', description: 'OpenSL ES'),
            ],
          ),
        );

        manager.nudge();
        await Future<void>.delayed(const Duration(milliseconds: 500));

        verify(
          () => player.setAudioDevice(
            Device(name: 'opensles', description: 'OpenSL ES'),
          ),
        ).called(1);
      }, timeout: const Timeout(Duration(seconds: 5)));

      test('does nothing after dispose', () async {
        manager.dispose();

        manager.nudge();
        await Future<void>.delayed(const Duration(milliseconds: 500));

        verifyNever(() => player.setAudioDevice(any()));
      }, timeout: const Timeout(Duration(seconds: 5)));
    });
  });
}
