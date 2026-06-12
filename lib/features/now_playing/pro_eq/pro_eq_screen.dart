import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/audio/player_settings_store.dart';
import '../../../design_tokens/pro_audio.dart';
import '../../../design_tokens/tokens.dart';
import '../../../state/providers.dart';
import '../../now_playing/eq_band_logic.dart';
import '../../now_playing/eq_preset.dart';
import 'pro_eq_widgets.dart';

/// Dedicated professional EQ screen — parametric + graphic EQ only.
///
/// NOT the full DSP screen. This focuses on EQ only:
/// - Stereo peak meter
/// - Frequency response curve
/// - 5-band parametric EQ
/// - 18-band graphic EQ
/// - Tone controls (bass/treble)
/// - Presets
class ProEqScreen extends ConsumerStatefulWidget {
  const ProEqScreen({super.key});

  @override
  ConsumerState<ProEqScreen> createState() => _ProEqScreenState();
}

class _ProEqScreenState extends ConsumerState<ProEqScreen> {
  final EqDspState _s = EqDspState();
  int _selectedParametricBand = 0;
  int? _selectedGraphicBand;
  String? _activePreset;

  @override
  void initState() {
    super.initState();
    _loadFxState();
  }

  void _loadFxState() {
    final fx = ref.read(playerServiceProvider).audioEffects;
    _s.loadFromAudioEffects(fx);
  }

  Future<void> _apply() async {
    final effects = _s.toAudioEffects();
    await ref.read(playerServiceProvider).setAudioEffects(effects);
  }

  void _resetAll() {
    setState(() {
      _s.reset();
      _activePreset = null;
    });
    _apply();
  }

  void _applyPreset(String name, EqPreset preset) {
    setState(() {
      _activePreset = name;
      _s.bass = preset.bass;
      _s.treble = preset.treble;
      _s.eqEnabled = preset.bands.isNotEmpty;
      for (final k in _s.eqBands.keys) {
        _s.eqBands[k] = preset.bands[k] ?? 1.0;
      }
    });
    _apply();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ProAudioColors.bgPrimary,
      appBar: AppBar(
        backgroundColor: ProAudioColors.bgPrimary,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Pro EQ',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFFE0E0E0),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _resetAll,
            child: Text(
              'Reset',
              style: AfTypography.bodySmall.copyWith(
                color: ProAudioColors.textDim,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(
            horizontal: ProAudioSpacing.panelMargin,
            vertical: ProAudioSpacing.controlGap,
          ),
          children: [
            // ── Stereo Peak Meter ─────────────────────────────────────────
            const ProSectionPanel(
              title: 'Stereo Peak Meter',
              child: ProStereoPeakMeter(leftLevel: 0.0, rightLevel: 0.0),
            ),

            const SizedBox(height: ProAudioSpacing.sectionGap),

            // ── Frequency Response Curve ──────────────────────────────────
            ProSectionPanel(
              title: 'Frequency Response',
              child: SizedBox(
                height: 160,
                child: ProFrequencyResponseView(
                  bands: _s.parametricBands,
                  selectedBand: _selectedParametricBand,
                  accentColor: ProAudioColors.curveActive,
                  onBandChanged: (index, band) {
                    setState(() => _s.parametricBands[index] = band);
                    _apply();
                  },
                  onBandSelected: (index) {
                    setState(() => _selectedParametricBand = index ?? 0);
                  },
                ),
              ),
            ),

            const SizedBox(height: ProAudioSpacing.sectionGap),

            // ── Parametric EQ Band Controls ───────────────────────────────
            ProSectionPanel(
              title: 'Parametric EQ',
              child: ProParametricControls(
                bands: _s.parametricBands,
                selectedBand: _selectedParametricBand,
                onBandSelected: (i) =>
                    setState(() => _selectedParametricBand = i),
                onBandChanged: (i, band) {
                  setState(() => _s.parametricBands[i] = band);
                  _apply();
                },
              ),
            ),

            const SizedBox(height: ProAudioSpacing.sectionGap),

            // ── 18-Band Graphic EQ ────────────────────────────────────────
            ProSectionPanel(
              title: '18-Band Graphic EQ',
              child: ProGraphicEqControls(
                bands: kEqBands,
                gains: _s.eqBands,
                enabled: _s.eqEnabled,
                selectedBand: _selectedGraphicBand,
                onEnabledChanged: (v) {
                  setState(() => _s.eqEnabled = v);
                  _apply();
                },
                onGainChanged: (key, gain) {
                  setState(() => _s.eqBands[key] = gain);
                  _apply();
                },
                onBandSelected: (i) => setState(() => _selectedGraphicBand = i),
              ),
            ),

            const SizedBox(height: ProAudioSpacing.sectionGap),

            // ── Tone Controls ─────────────────────────────────────────────
            ProSectionPanel(
              title: 'Tone',
              child: ProToneControls(
                bass: _s.bass,
                treble: _s.treble,
                onChanged: (bass, treble) {
                  setState(() {
                    _s.bass = bass;
                    _s.treble = treble;
                  });
                  _apply();
                },
              ),
            ),

            const SizedBox(height: ProAudioSpacing.sectionGap),

            // ── Presets ───────────────────────────────────────────────────
            ProSectionPanel(
              title: 'Presets',
              child: ProPresetChips(
                activePreset: _activePreset,
                onApply: _applyPreset,
              ),
            ),

            const SizedBox(height: ProAudioSpacing.sectionGap * 2),
          ],
        ),
      ),
    );
  }
}
