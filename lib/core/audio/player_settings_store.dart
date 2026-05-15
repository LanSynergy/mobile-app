import 'dart:convert';

import 'package:mpv_audio_kit/mpv_audio_kit.dart'
    show
        AcompressorSettings,
        AexciterSettings,
        AgateSettings,
        AudioEffects,
        BassSettings,
        Cache,
        CrossfeedSettings,
        CrystalizerSettings,
        DeesserSettings,
        Format,
        Gapless,
        LoudnormSettings,
        ReplayGain,
        ReplayGainSettings,
        RubberbandSettings,
        StereowidenSettings,
        SuperequalizerSettings,
        TrebleSettings,
        VirtualbassSettings;
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
  static const _kReplayGainPreamp = 'af.replay_gain_preamp';
  static const _kReplayGainFallback = 'af.replay_gain_fallback';
  static const _kReplayGainClip = 'af.replay_gain_clip';
  static const _kPrefetchPlaylist = 'af.prefetch_playlist';
  static const _kAudioEffects = 'af.audio_effects_json';

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

  static Future<void> saveReplayGainFull(ReplayGainSettings settings) async {
    final p = await _prefs();
    await p.setString(_kReplayGain, settings.mode.name);
    await p.setDouble(_kReplayGainPreamp, settings.preamp);
    await p.setDouble(_kReplayGainFallback, settings.fallback);
    await p.setBool(_kReplayGainClip, settings.clip);
  }

  static Future<void> savePrefetchPlaylist(bool enabled) async {
    final p = await _prefs();
    await p.setBool(_kPrefetchPlaylist, enabled);
  }

  static Future<void> saveGapless(Gapless mode) async {
    final p = await _prefs();
    await p.setString(_kGapless, mode.name);
  }

  /// Serialize the user-visible audio effects to JSON and persist.
  static Future<void> saveAudioEffects(AudioEffects fx) async {
    final p = await _prefs();
    final map = <String, dynamic>{
      'bass_g': fx.bass.g,
      'bass_enabled': fx.bass.enabled,
      'treble_g': fx.treble.g,
      'treble_enabled': fx.treble.enabled,
      'loudnorm_enabled': fx.loudnorm.enabled,
      'compressor_enabled': fx.acompressor.enabled,
      'compressor_threshold': fx.acompressor.threshold,
      'compressor_ratio': fx.acompressor.ratio,
      'compressor_attack': fx.acompressor.attack,
      'compressor_release': fx.acompressor.release,
      'eq_enabled': fx.superequalizer.enabled,
      'eq_params': fx.superequalizer.params,
      'rubberband_enabled': fx.rubberband.enabled,
      'rubberband_pitch': fx.rubberband.pitch,
      'rubberband_tempo': fx.rubberband.tempo,
      'crossfeed_enabled': fx.crossfeed.enabled,
      'crossfeed_strength': fx.crossfeed.strength,
      'stereowiden_enabled': fx.stereowiden.enabled,
      'stereowiden_delay': fx.stereowiden.delay,
      'exciter_enabled': fx.aexciter.enabled,
      'exciter_amount': fx.aexciter.amount,
      'crystalizer_enabled': fx.crystalizer.enabled,
      'crystalizer_i': fx.crystalizer.i,
      'virtualbass_enabled': fx.virtualbass.enabled,
      'virtualbass_cutoff': fx.virtualbass.cutoff,
      'gate_enabled': fx.agate.enabled,
      'deesser_enabled': fx.deesser.enabled,
    };
    await p.setString(_kAudioEffects, jsonEncode(map));
  }

  /// Restore audio effects from JSON.
  static AudioEffects? loadAudioEffects(SharedPreferences p) {
    final json = p.getString(_kAudioEffects);
    if (json == null) return null;
    try {
      final m = jsonDecode(json) as Map<String, dynamic>;
      final eqParamsRaw = m['eq_params'] as Map<String, dynamic>?;
      final eqParams = eqParamsRaw?.map(
            (k, v) => MapEntry(k, (v as num).toDouble()),
          ) ??
          const <String, double>{};
      return AudioEffects(
        bass: BassSettings(
          enabled: m['bass_enabled'] as bool? ?? false,
          g: (m['bass_g'] as num?)?.toDouble() ?? 0.0,
        ),
        treble: TrebleSettings(
          enabled: m['treble_enabled'] as bool? ?? false,
          g: (m['treble_g'] as num?)?.toDouble() ?? 0.0,
        ),
        loudnorm: LoudnormSettings(
          enabled: m['loudnorm_enabled'] as bool? ?? false,
        ),
        acompressor: AcompressorSettings(
          enabled: m['compressor_enabled'] as bool? ?? false,
          threshold: (m['compressor_threshold'] as num?)?.toDouble() ?? 0.1,
          ratio: (m['compressor_ratio'] as num?)?.toDouble() ?? 4.0,
          attack: (m['compressor_attack'] as num?)?.toDouble() ?? 20.0,
          release: (m['compressor_release'] as num?)?.toDouble() ?? 250.0,
        ),
        superequalizer: SuperequalizerSettings(
          enabled: m['eq_enabled'] as bool? ?? false,
          params: eqParams,
        ),
        rubberband: RubberbandSettings(
          enabled: m['rubberband_enabled'] as bool? ?? false,
          pitch: (m['rubberband_pitch'] as num?)?.toDouble() ?? 1.0,
          tempo: (m['rubberband_tempo'] as num?)?.toDouble() ?? 1.0,
        ),
        crossfeed: CrossfeedSettings(
          enabled: m['crossfeed_enabled'] as bool? ?? false,
          strength: (m['crossfeed_strength'] as num?)?.toDouble() ?? 0.2,
        ),
        stereowiden: StereowidenSettings(
          enabled: m['stereowiden_enabled'] as bool? ?? false,
          delay: (m['stereowiden_delay'] as num?)?.toDouble() ?? 20.0,
        ),
        aexciter: AexciterSettings(
          enabled: m['exciter_enabled'] as bool? ?? false,
          amount: (m['exciter_amount'] as num?)?.toDouble() ?? 1.0,
        ),
        crystalizer: CrystalizerSettings(
          enabled: m['crystalizer_enabled'] as bool? ?? false,
          i: (m['crystalizer_i'] as num?)?.toDouble() ?? 2.0,
        ),
        virtualbass: VirtualbassSettings(
          enabled: m['virtualbass_enabled'] as bool? ?? false,
          cutoff: (m['virtualbass_cutoff'] as num?)?.toDouble() ?? 250.0,
        ),
        agate: AgateSettings(
          enabled: m['gate_enabled'] as bool? ?? false,
        ),
        deesser: DeesserSettings(
          enabled: m['deesser_enabled'] as bool? ?? false,
        ),
      );
    } catch (_) {
      return null;
    }
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
      final preamp = p.getDouble(_kReplayGainPreamp) ?? 0.0;
      final fallback = p.getDouble(_kReplayGainFallback) ?? 0.0;
      final clip = p.getBool(_kReplayGainClip) ?? false;
      await tryApply('replayGain=$replayGainName', () async {
        await svc.setReplayGain(ReplayGainSettings(
          mode: mode,
          preamp: preamp,
          fallback: fallback,
          clip: clip,
        ));
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

    final prefetch = p.getBool(_kPrefetchPlaylist);
    if (prefetch != null) {
      await tryApply('prefetchPlaylist=$prefetch',
          () => svc.setPrefetchPlaylist(prefetch));
    }

    final fx = loadAudioEffects(p);
    if (fx != null) {
      await tryApply('audioEffects', () => svc.setAudioEffects(fx));
    }

    afLog('boot', 'PlayerSettingsStore applied persisted settings');
  }
}
