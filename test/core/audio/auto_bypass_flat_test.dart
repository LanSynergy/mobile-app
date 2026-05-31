import 'package:flutter_test/flutter_test.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import 'package:aetherfin/core/audio/player_service.dart';

/// Tests for [autoBypassFlat] — the pre-mpv filter pruner that
/// disables filters whose parameters are at their no-op values, so
/// libmpv doesn't carry dead entries in its `af` chain.
void main() {
  group('autoBypassFlat', () {
    test('bass: enabled stays true when gain is non-zero', () {
      final fx = const AudioEffects().copyWith(
        bass: const BassSettings(enabled: true, g: 6.0),
      );
      final out = autoBypassFlat(fx);
      expect(out.bass.enabled, isTrue);
      expect(out.bass.g, 6.0);
    });

    test('bass: enabled flips to false when gain is 0', () {
      final fx = const AudioEffects().copyWith(
        bass: const BassSettings(enabled: true, g: 0.0),
      );
      final out = autoBypassFlat(fx);
      expect(out.bass.enabled, isFalse);
    });

    test('treble: enabled flips to false when gain is 0', () {
      final fx = const AudioEffects().copyWith(
        treble: const TrebleSettings(enabled: true, g: 0.0),
      );
      final out = autoBypassFlat(fx);
      expect(out.treble.enabled, isFalse);
    });

    test('superequalizer: enabled stays true when params is non-empty', () {
      final fx = const AudioEffects().copyWith(
        superequalizer: const SuperequalizerSettings(
          enabled: true,
          params: {'1b': 2.0},
        ),
      );
      final out = autoBypassFlat(fx);
      expect(out.superequalizer.enabled, isTrue);
    });

    test('superequalizer: enabled stays true when a band is cut to 0.0', () {
      // Regression: previously the auto-bypass used `gain != 0.0` to
      // decide whether the EQ was meaningful, which treated a band
      // cut to 0 (full mute) as "flat" and disabled the entire
      // superequalizer. A 0.0 band is a strong user signal — keep it.
      final fx = const AudioEffects().copyWith(
        superequalizer: const SuperequalizerSettings(
          enabled: true,
          params: {'1b': 0.0},
        ),
      );
      final out = autoBypassFlat(fx);
      expect(out.superequalizer.enabled, isTrue);
    });

    test('superequalizer: enabled flips to false when params is empty', () {
      final fx = const AudioEffects().copyWith(
        superequalizer: const SuperequalizerSettings(enabled: true, params: {}),
      );
      final out = autoBypassFlat(fx);
      expect(out.superequalizer.enabled, isFalse);
    });

    test(
      'deesser: out-of-range f is clamped to [0,1] so libmpv accepts it',
      () {
        // Regression: the EQ/DSP screen previously exposed deesser.f
        // as a Hz cutoff (2000..12000) but libmpv's `lavfi-deesser`
        // takes a 0..1 ratio. The first toggle of de-esser would
        // submit `f=5500`, libmpv would reject the entire af chain,
        // and Bass/Treble/EQ would silently stop working too. The
        // sanitiser clamps so a stale persisted value cannot poison
        // the chain on next launch.
        final fx = const AudioEffects().copyWith(
          deesser: const DeesserSettings(
            enabled: true,
            f: 5500.0,
            i: 0.5,
            m: 0.5,
          ),
        );
        final out = autoBypassFlat(fx);
        expect(out.deesser.f, 1.0);
        expect(out.deesser.i, 0.5);
        expect(out.deesser.m, 0.5);
        expect(out.deesser.enabled, isTrue);
      },
    );

    test('deesser: negative params are clamped to 0', () {
      final fx = const AudioEffects().copyWith(
        deesser: const DeesserSettings(
          enabled: true,
          f: -0.2,
          i: -1.0,
          m: -3.5,
        ),
      );
      final out = autoBypassFlat(fx);
      expect(out.deesser.f, 0.0);
      expect(out.deesser.i, 0.0);
      expect(out.deesser.m, 0.0);
    });

    test('deesser: in-range params pass through unchanged', () {
      final fx = const AudioEffects().copyWith(
        deesser: const DeesserSettings(enabled: true, f: 0.5, i: 0.3, m: 0.75),
      );
      final out = autoBypassFlat(fx);
      expect(out.deesser.f, 0.5);
      expect(out.deesser.i, 0.3);
      expect(out.deesser.m, 0.75);
    });

    test('disabled filters stay disabled', () {
      final fx = const AudioEffects().copyWith(
        bass: const BassSettings(enabled: false, g: 6.0),
        treble: const TrebleSettings(enabled: false, g: 6.0),
        superequalizer: const SuperequalizerSettings(
          enabled: false,
          params: {'1b': 2.0},
        ),
      );
      final out = autoBypassFlat(fx);
      expect(out.bass.enabled, isFalse);
      expect(out.treble.enabled, isFalse);
      expect(out.superequalizer.enabled, isFalse);
    });
  });
}
