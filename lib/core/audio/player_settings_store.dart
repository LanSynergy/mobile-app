import 'package:mpv_audio_kit/mpv_audio_kit.dart'
    show Cache, Format, Gapless, ReplayGain;
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/log.dart';
import 'player_service.dart';

/// Persists user-tweakable mpv runtime settings to `shared_preferences`
/// so they survive app restarts.
///
/// mpv resets every property to its compiled-in default on each `Player()`
/// construction. The settings dialogs (`SettingsScreen`) write through to
/// mpv via `AfPlayerService.setX()`, but without persistence those values
/// vanish on app cold-start.
///
/// Flow:
/// 1. UI calls `PlayerSettingsStore.saveX(value)` after a successful setter.
/// 2. On app start, `applyPersisted(svc)` reads every key and replays the
///    setters against the freshly-constructed player.
///
/// Persisted keys:
///   - audio_sample_rate (int, 0 = auto)
///   - audio_format (String, Format.mpvValue or 'auto')
///   - audio_exclusive (bool)
///   - audio_buffer_ms (int, default 200)
///   - audio_stream_silence (bool)
///   - cache_secs (int, default 30)
///   - replay_gain_mode (String, ReplayGain.mpvValue)
///   - gapless (String, Gapless.mpvValue)
class PlayerSettingsStore {
  static const _kSampleRate = 'af.audio_sample_rate';
  static const _kFormat = 'af.audio_format';
  static const _kExclusive = 'af.audio_exclusive';
  static const _kBufferMs = 'af.audio_buffer_ms';
  static const _kStreamSilence = 'af.audio_stream_silence';
  static const _kCacheSecs = 'af.cache_secs';
  static const _kReplayGain = 'af.replay_gain_mode';
  static const _kGapless = 'af.gapless';

  static Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  // ── Setters (called from UI) ──────────────────────────────────────────────

  static Future<void> saveSampleRate(int rate) async {
    final p = await _prefs();
    await p.setInt(_kSampleRate, rate);
  }

  static Future<void> saveFormat(Format format) async {
    final p = await _prefs();
    await p.setString(_kFormat, format.name);
  }

  static Future<void> saveExclusive(bool enabled) async {
    final p = await _prefs();
    await p.setBool(_kExclusive, enabled);
  }

  static Future<void> saveBufferMs(int ms) async {
    final p = await _prefs();
    await p.setInt(_kBufferMs, ms);
  }

  static Future<void> saveStreamSilence(bool enabled) async {
    final p = await _prefs();
    await p.setBool(_kStreamSilence, enabled);
  }

  static Future<void> saveCacheSecs(int secs) async {
    final p = await _prefs();
    await p.setInt(_kCacheSecs, secs);
  }

  static Future<void> saveReplayGain(ReplayGain mode) async {
    final p = await _prefs();
    await p.setString(_kReplayGain, mode.name);
  }

  static Future<void> saveGapless(Gapless mode) async {
    final p = await _prefs();
    await p.setString(_kGapless, mode.name);
  }

  // ── Apply on startup ──────────────────────────────────────────────────────

  /// Reads every persisted key and replays the matching setter on [svc].
  /// Call this once after the player has been constructed and configured.
  /// Failures are logged but do not throw — a single bad value should not
  /// break startup.
  static Future<void> applyPersisted(AfPlayerService svc) async {
    final p = await _prefs();

    Future<void> tryApply(String label, Future<void> Function() action) async {
      try {
        await action();
      } catch (e, stack) {
        afLog('error', 'PlayerSettingsStore apply $label failed',
            error: e, stackTrace: stack);
      }
    }

    final sampleRate = p.getInt(_kSampleRate);
    if (sampleRate != null) {
      await tryApply('sampleRate=$sampleRate',
          () => svc.setAudioSampleRate(sampleRate));
    }

    final formatName = p.getString(_kFormat);
    if (formatName != null) {
      final format = Format.values.firstWhere(
        (f) => f.name == formatName,
        orElse: () => Format.auto,
      );
      await tryApply('format=$formatName', () => svc.setAudioFormat(format));
    }

    final exclusive = p.getBool(_kExclusive);
    if (exclusive != null) {
      await tryApply('exclusive=$exclusive',
          () => svc.setAudioExclusive(exclusive));
    }

    final bufferMs = p.getInt(_kBufferMs);
    if (bufferMs != null) {
      await tryApply('bufferMs=$bufferMs',
          () => svc.setAudioBuffer(Duration(milliseconds: bufferMs)));
    }

    final streamSilence = p.getBool(_kStreamSilence);
    if (streamSilence != null) {
      await tryApply('streamSilence=$streamSilence',
          () => svc.setAudioStreamSilence(streamSilence));
    }

    final cacheSecs = p.getInt(_kCacheSecs);
    if (cacheSecs != null) {
      await tryApply('cacheSecs=$cacheSecs', () async {
        await svc.setCache(svc.cacheSettings.copyWith(
          mode: Cache.yes,
          secs: Duration(seconds: cacheSecs),
        ));
      });
    }

    final replayGainName = p.getString(_kReplayGain);
    if (replayGainName != null) {
      final mode = ReplayGain.values.firstWhere(
        (m) => m.name == replayGainName,
        orElse: () => ReplayGain.no,
      );
      await tryApply('replayGain=$replayGainName', () async {
        await svc.setReplayGain(svc.replayGain.copyWith(mode: mode));
      });
    }

    final gaplessName = p.getString(_kGapless);
    if (gaplessName != null) {
      final mode = Gapless.values.firstWhere(
        (g) => g.name == gaplessName,
        orElse: () => Gapless.weak,
      );
      await tryApply('gapless=$gaplessName', () => svc.setGapless(mode));
    }

    afLog('boot', 'PlayerSettingsStore applied persisted settings');
  }
}
