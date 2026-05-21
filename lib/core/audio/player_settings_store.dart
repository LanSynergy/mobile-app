import 'dart:convert';

import 'package:mpv_audio_kit/mpv_audio_kit.dart'
    show
        AcompressorSettings,
        AcrusherSettings,
        AechoSettings,
        AexciterSettings,
        AgateSettings,
        AphaserSettings,
        AudioEffects,
        BassSettings,
        Cache,
        ChorusSettings,
        CrossfeedSettings,
        CrystalizerSettings,
        DeesserSettings,
        FlangerSettings,
        Format,
        Gapless,
        LoudnormSettings,
        ReplayGain,
        ReplayGainSettings,
        RubberbandSettings,
        StereowidenSettings,
        SuperequalizerSettings,
        TrebleSettings,
        TremoloSettings,
        VibratoSettings,
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
  static const _kEqPresets = 'af.eq_presets_json';
  static const _kActivePreset = 'af.active_eq_preset';
  static const _kDspMasterEnabled = 'af.dsp_master_enabled';
  static const _kArtworkPulse = 'af.artwork_pulse_enabled';
  static const _kOfflineCacheEnabled = 'af.offline_cache_enabled';
  static const _kOfflineCacheMaxSize = 'af.offline_cache_max_size';

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

  /// Persist the DSP master switch state.
  static Future<void> saveDspMasterEnabled(bool enabled) async {
    final p = await _prefs();
    await p.setBool(_kDspMasterEnabled, enabled);
  }

  /// Load the DSP master switch state. Defaults to true (effects active).
  static Future<bool> loadDspMasterEnabled() async {
    final p = await _prefs();
    return p.getBool(_kDspMasterEnabled) ?? true;
  }

  /// Persist the artwork pulse animation toggle.
  static Future<void> saveArtworkPulse(bool enabled) async {
    final p = await _prefs();
    await p.setBool(_kArtworkPulse, enabled);
  }

  /// Load the artwork pulse animation toggle. Defaults to true (pulse on).
  static Future<bool> loadArtworkPulse() async {
    final p = await _prefs();
    return p.getBool(_kArtworkPulse) ?? true;
  }

  /// Persist offline cache enabled state.
  static Future<void> saveOfflineCacheEnabled(bool enabled) async {
    final p = await _prefs();
    await p.setBool(_kOfflineCacheEnabled, enabled);
  }

  /// Persist offline cache max size in bytes.
  static Future<void> saveOfflineCacheMaxSize(int bytes) async {
    final p = await _prefs();
    await p.setInt(_kOfflineCacheMaxSize, bytes);
  }

  /// Load offline cache enabled state. Defaults to false (disabled).
  static Future<bool> loadOfflineCacheEnabled() async {
    final p = await _prefs();
    return p.getBool(_kOfflineCacheEnabled) ?? false;
  }

  /// Load offline cache max size. Defaults to 1 GB.
  static Future<int> loadOfflineCacheMaxSize() async {
    final p = await _prefs();
    return p.getInt(_kOfflineCacheMaxSize) ?? (1024 * 1024 * 1024);
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
      'gate_threshold': fx.agate.threshold,
      'gate_ratio': fx.agate.ratio,
      'gate_attack': fx.agate.attack,
      'gate_release': fx.agate.release,
      'deesser_enabled': fx.deesser.enabled,
      'deesser_i': fx.deesser.i,
      'deesser_m': fx.deesser.m,
      'deesser_f': fx.deesser.f,
      // Echo / delay
      'echo_enabled': fx.aecho.enabled,
      'echo_in_gain': fx.aecho.in_gain,
      'echo_out_gain': fx.aecho.out_gain,
      'echo_delays': fx.aecho.delays,
      'echo_decays': fx.aecho.decays,
      // Modulation effects
      'phaser_enabled': fx.aphaser.enabled,
      'phaser_in_gain': fx.aphaser.in_gain,
      'phaser_out_gain': fx.aphaser.out_gain,
      'phaser_delay': fx.aphaser.delay,
      'phaser_decay': fx.aphaser.decay,
      'phaser_speed': fx.aphaser.speed,
      'flanger_enabled': fx.flanger.enabled,
      'flanger_delay': fx.flanger.delay,
      'flanger_depth': fx.flanger.depth,
      'flanger_regen': fx.flanger.regen,
      'flanger_width': fx.flanger.width,
      'flanger_speed': fx.flanger.speed,
      'chorus_enabled': fx.chorus.enabled,
      'chorus_in_gain': fx.chorus.in_gain,
      'chorus_out_gain': fx.chorus.out_gain,
      'chorus_delays': fx.chorus.delays,
      'chorus_decays': fx.chorus.decays,
      'chorus_speeds': fx.chorus.speeds,
      'chorus_depths': fx.chorus.depths,
      'tremolo_enabled': fx.tremolo.enabled,
      'tremolo_f': fx.tremolo.f,
      'tremolo_d': fx.tremolo.d,
      'vibrato_enabled': fx.vibrato.enabled,
      'vibrato_f': fx.vibrato.f,
      'vibrato_d': fx.vibrato.d,
      'crusher_enabled': fx.acrusher.enabled,
      'crusher_bits': fx.acrusher.bits,
      'crusher_mix': fx.acrusher.mix,
      'crusher_samples': fx.acrusher.samples,
    };
    await p.setString(_kAudioEffects, jsonEncode(map));
  }

  // ── EQ Presets ────────────────────────────────────────────────────────────

  /// Save a named EQ preset (18-band params + bass/treble).
  static Future<void> saveEqPreset(String name, EqPreset preset) async {
    final p = await _prefs();
    final all = loadEqPresets(p);
    all[name] = preset;
    final encoded = all.map((k, v) => MapEntry(k, v.toJson()));
    await p.setString(_kEqPresets, jsonEncode(encoded));
  }

  /// Delete a named EQ preset.
  static Future<void> deleteEqPreset(String name) async {
    final p = await _prefs();
    final all = loadEqPresets(p);
    all.remove(name);
    final encoded = all.map((k, v) => MapEntry(k, v.toJson()));
    await p.setString(_kEqPresets, jsonEncode(encoded));
  }

  /// Load all user-saved EQ presets.
  static Map<String, EqPreset> loadEqPresets(SharedPreferences p) {
    final json = p.getString(_kEqPresets);
    if (json == null) return {};
    try {
      final raw = jsonDecode(json) as Map<String, dynamic>;
      return raw.map((k, v) => MapEntry(k, EqPreset.fromJson(v as Map<String, dynamic>)));
    } catch (_) {
      return {};
    }
  }

  /// Load all user-saved EQ presets (async convenience).
  static Future<Map<String, EqPreset>> loadEqPresetsAsync() async {
    final p = await _prefs();
    return loadEqPresets(p);
  }

  /// Save the name of the currently active preset (null to clear).
  static Future<void> saveActivePreset(String? name) async {
    final p = await _prefs();
    if (name == null) {
      await p.remove(_kActivePreset);
    } else {
      await p.setString(_kActivePreset, name);
    }
  }

  /// Load the name of the currently active preset.
  static String? loadActivePreset(SharedPreferences p) {
    return p.getString(_kActivePreset);
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
          threshold: (m['gate_threshold'] as num?)?.toDouble() ?? 0.01,
          ratio: (m['gate_ratio'] as num?)?.toDouble() ?? 2.0,
          attack: (m['gate_attack'] as num?)?.toDouble() ?? 20.0,
          release: (m['gate_release'] as num?)?.toDouble() ?? 250.0,
        ),
        deesser: DeesserSettings(
          enabled: m['deesser_enabled'] as bool? ?? false,
          i: (m['deesser_i'] as num?)?.toDouble() ?? 0.0,
          m: (m['deesser_m'] as num?)?.toDouble() ?? 0.5,
          f: (m['deesser_f'] as num?)?.toDouble() ?? 0.5,
        ),
        aecho: AechoSettings(
          enabled: m['echo_enabled'] as bool? ?? false,
          in_gain: (m['echo_in_gain'] as num?)?.toDouble() ?? 0.6,
          out_gain: (m['echo_out_gain'] as num?)?.toDouble() ?? 0.3,
          delays: m['echo_delays'] as String? ?? '500',
          decays: m['echo_decays'] as String? ?? '0.5',
        ),
        aphaser: AphaserSettings(
          enabled: m['phaser_enabled'] as bool? ?? false,
          in_gain: (m['phaser_in_gain'] as num?)?.toDouble() ?? 0.4,
          out_gain: (m['phaser_out_gain'] as num?)?.toDouble() ?? 0.74,
          delay: (m['phaser_delay'] as num?)?.toDouble() ?? 3.0,
          decay: (m['phaser_decay'] as num?)?.toDouble() ?? 0.4,
          speed: (m['phaser_speed'] as num?)?.toDouble() ?? 0.5,
        ),
        flanger: FlangerSettings(
          enabled: m['flanger_enabled'] as bool? ?? false,
          delay: (m['flanger_delay'] as num?)?.toDouble() ?? 0.0,
          depth: (m['flanger_depth'] as num?)?.toDouble() ?? 2.0,
          regen: (m['flanger_regen'] as num?)?.toDouble() ?? 0.0,
          width: (m['flanger_width'] as num?)?.toDouble() ?? 71.0,
          speed: (m['flanger_speed'] as num?)?.toDouble() ?? 0.5,
        ),
        chorus: ChorusSettings(
          enabled: m['chorus_enabled'] as bool? ?? false,
          in_gain: (m['chorus_in_gain'] as num?)?.toDouble() ?? 0.4,
          out_gain: (m['chorus_out_gain'] as num?)?.toDouble() ?? 0.4,
          delays: m['chorus_delays'] as String? ?? '40|60',
          decays: m['chorus_decays'] as String? ?? '0.4|0.32',
          speeds: m['chorus_speeds'] as String? ?? '0.25|0.4',
          depths: m['chorus_depths'] as String? ?? '2|3',
        ),
        tremolo: TremoloSettings(
          enabled: m['tremolo_enabled'] as bool? ?? false,
          f: (m['tremolo_f'] as num?)?.toDouble() ?? 5.0,
          d: (m['tremolo_d'] as num?)?.toDouble() ?? 0.5,
        ),
        vibrato: VibratoSettings(
          enabled: m['vibrato_enabled'] as bool? ?? false,
          f: (m['vibrato_f'] as num?)?.toDouble() ?? 5.0,
          d: (m['vibrato_d'] as num?)?.toDouble() ?? 0.5,
        ),
        acrusher: AcrusherSettings(
          enabled: m['crusher_enabled'] as bool? ?? false,
          bits: (m['crusher_bits'] as num?)?.toDouble() ?? 8.0,
          mix: (m['crusher_mix'] as num?)?.toDouble() ?? 0.5,
          samples: (m['crusher_samples'] as num?)?.toDouble() ?? 1.0,
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
      // Only apply effects if the master switch was ON when last saved.
      final masterEnabled = p.getBool(_kDspMasterEnabled) ?? true;
      if (masterEnabled) {
        await tryApply('audioEffects', () => svc.setAudioEffects(fx));
      }
    }

    afLog('boot', 'PlayerSettingsStore applied persisted settings');
  }
}

/// A named EQ preset containing 18-band params + bass/treble shelves.
class EqPreset {
  final Map<String, double> bands;
  final double bass;
  final double treble;

  const EqPreset({
    required this.bands,
    this.bass = 0.0,
    this.treble = 0.0,
  });

  Map<String, dynamic> toJson() => {
        'bands': bands,
        'bass': bass,
        'treble': treble,
      };

  factory EqPreset.fromJson(Map<String, dynamic> json) {
    final bandsRaw = json['bands'] as Map<String, dynamic>?;
    final bands = bandsRaw?.map(
          (k, v) => MapEntry(k, (v as num).toDouble()),
        ) ??
        const <String, double>{};
    return EqPreset(
      bands: bands,
      bass: (json['bass'] as num?)?.toDouble() ?? 0.0,
      treble: (json['treble'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
