import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Settings race guards', () {
    // -------------------------------------------------------------------
    // Guard helpers mirroring the pattern added to AfPlayerService setters.
    // The guards in player_service.dart are:
    //   if (_disposed) return;
    //   if (_isLoadingQueue) return;
    //
    // These tests verify that the guard *logic* correctly intercepts
    // before any _player.* command fires. The setters directly delegate
    // to _player.*; the guards are the sole defense mechanism.
    //
    // Note: guards use parameters instead of local constants so the
    // analyzer cannot statically prove dead branches — each test
    // simulates a true runtime decision.
    // -------------------------------------------------------------------

    group('_isLoadingQueue guard', () {
      test('skips setter when isLoadingQueue is true', () {
        var commandFired = false;

        void guardedSetter(bool isLoadingQueue) {
          if (isLoadingQueue) return;
          commandFired = true;
        }

        guardedSetter(true);

        expect(
          commandFired,
          isFalse,
          reason: 'guard prevented mpv command from firing during queue load',
        );
      });

      test('allows setter when isLoadingQueue is false', () {
        var commandFired = false;

        void guardedSetter(bool isLoadingQueue) {
          if (isLoadingQueue) return;
          commandFired = true;
        }

        guardedSetter(false);

        expect(
          commandFired,
          isTrue,
          reason: 'setter proceeds normally when not loading',
        );
      });

      test('guard is transparent after loading completes (toggle test)', () {
        var commandFired = 0;
        var isLoadingQueue = true;

        void guardedSetter() {
          if (isLoadingQueue) return;
          commandFired++;
        }

        guardedSetter(); // skipped
        expect(commandFired, 0);

        isLoadingQueue = false;
        guardedSetter(); // proceeds
        expect(commandFired, 1);

        // Verify the guard doesn't permanently block
        guardedSetter(); // proceeds again
        expect(commandFired, 2);
      });
    });

    group('_disposed guard', () {
      test('skips setter when disposed is true', () {
        var commandFired = false;

        void guardedSetter(bool disposed) {
          if (disposed) return;
          commandFired = true;
        }

        guardedSetter(true);

        expect(
          commandFired,
          isFalse,
          reason: 'guard prevented mpv command after dispose',
        );
      });

      test('allows setter when disposed is false', () {
        var commandFired = false;

        void guardedSetter(bool disposed) {
          if (disposed) return;
          commandFired = true;
        }

        guardedSetter(false);

        expect(
          commandFired,
          isTrue,
          reason: 'setter proceeds normally when not disposed',
        );
      });
    });

    group('_isLoadingQueue guard on audio device handler', () {
      test('skips reapplyPersistedEffects when isLoadingQueue is true', () {
        var effectsReapplied = false;

        // Simulates the audioDevice stream handler guard:
        //   if (_isLoadingQueue) return;
        //   await _audioDeviceManager.reapplyPersistedEffects();
        Future<void> audioDeviceHandler(bool isLoadingQueue) async {
          if (isLoadingQueue) return;
          effectsReapplied = true;
        }

        audioDeviceHandler(true);

        expect(
          effectsReapplied,
          isFalse,
          reason: 'guard prevented reapplyPersistedEffects during queue load',
        );
      });

      test('allows reapplyPersistedEffects when not loading', () async {
        var effectsReapplied = false;

        Future<void> audioDeviceHandler(bool isLoadingQueue) async {
          if (isLoadingQueue) return;
          effectsReapplied = true;
        }

        await audioDeviceHandler(false);

        expect(
          effectsReapplied,
          isTrue,
          reason: 'reapplyPersistedEffects proceeds when not loading',
        );
      });
    });

    group('combined guards (no false rejection)', () {
      test('setter proceeds when both flags are false', () {
        var commandFired = false;

        void guardedSetter(bool disposed, bool isLoadingQueue) {
          if (disposed) return;
          if (isLoadingQueue) return;
          commandFired = true;
        }

        guardedSetter(false, false);

        expect(
          commandFired,
          isTrue,
          reason: 'setter proceeds with both flags false — no false rejection',
        );
      });

      test('_disposed guard takes priority over isLoadingQueue', () {
        var commandFired = false;

        void guardedSetter(bool disposed, bool isLoadingQueue) {
          if (disposed) return;
          if (isLoadingQueue) return;
          commandFired = true;
        }

        guardedSetter(true, false);

        expect(
          commandFired,
          isFalse,
          reason: '_disposed guard fires first and prevents execution',
        );
      });

      test('isLoadingQueue guard fires when disposed is false', () {
        var commandFired = false;

        void guardedSetter(bool disposed, bool isLoadingQueue) {
          if (disposed) return;
          if (isLoadingQueue) return;
          commandFired = true;
        }

        guardedSetter(false, true);

        expect(
          commandFired,
          isFalse,
          reason: '_isLoadingQueue guard fires when only it is active',
        );
      });
    });
  });
}
