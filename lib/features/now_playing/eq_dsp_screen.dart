import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/player_settings_store.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/af_dialog.dart';
import 'eq_dsp_widgets.dart';
import 'eq_preset.dart';

class EqDspScreen extends ConsumerStatefulWidget {
  const EqDspScreen({super.key});

  @override
  ConsumerState<EqDspScreen> createState() => _EqDspScreenState();
}

class _EqDspScreenState extends ConsumerState<EqDspScreen> {
  Timer? _scrollSafetyTimer;
  bool _isScrollActive = false;
  Map<String, EqPreset> _userPresets = {};

  @override
  void initState() {
    super.initState();
    _loadPresets();
  }

  @override
  void dispose() {
    _scrollSafetyTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadPresets() async {
    final p = await PlayerSettingsStore.loadEqPresetsAsync();
    if (mounted) setState(() => _userPresets = p);
  }

  void _setScrollActive(bool v) {
    if (_isScrollActive != v) setState(() => _isScrollActive = v);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(audioEffectsProvider);
    final notifier = ref.read(audioEffectsProvider.notifier);

    return Scaffold(
      backgroundColor: AfColors.surfaceCanvas,
      appBar: AppBar(
        backgroundColor: AfColors.surfaceCanvas,
        surfaceTintColor: Colors.transparent,
        title: const Text('Equalizer & DSP'),
        centerTitle: false,
        actions: [
          Center(
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: state.masterEnabled
                      ? AfColors.indigo500.withValues(alpha: 0.5)
                      : AfColors.textTertiary.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Effects',
                    style: AfTypography.bodySmall.copyWith(
                      fontSize: 11,
                      color: state.masterEnabled
                          ? AfColors.indigo400
                          : AfColors.textTertiary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    height: 24,
                    child: Switch.adaptive(
                      value: state.masterEnabled,
                      activeTrackColor: AfColors.indigo500,
                      onChanged: notifier.setMasterEnabled,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            tooltip: 'Reset all',
            onPressed: notifier.resetAll,
            color: AfColors.semanticError.withValues(alpha: 0.7),
          ),
        ],
      ),
      body: AnimatedOpacity(
        opacity: state.masterEnabled ? 1.0 : 0.4,
        duration: const Duration(milliseconds: 200),
        child: Listener(
          onPointerDown: (_) {
            _scrollSafetyTimer?.cancel();
          },
          onPointerUp: (_) {
            _setScrollActive(false);
          },
          onPointerCancel: (_) {
            _setScrollActive(false);
          },
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n is ScrollStartNotification && !_isScrollActive) {
                _setScrollActive(true);
              }
              return false;
            },
            child: NotificationListener<OverscrollIndicatorNotification>(
              onNotification: (n) {
                n.disallowIndicator();
                return true;
              },
              child: Stack(
                children: [
                  ListView(
                    physics: const ClampingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      EqCurveWidget(bands: state.eqBands),
                      const SizedBox(height: 12),
                      _PresetRow(
                        presets: {...kBuiltInPresets, ..._userPresets},
                        userPresets: _userPresets,
                        activePreset: state.activePreset,
                        onApply: (name, p) => notifier.applyPreset(
                          name,
                          p.bands,
                          p.bass,
                          p.treble,
                        ),
                        onDelete: _deletePreset,
                        onSave: _saveCurrentPreset,
                        state: state,
                        notifier: notifier,
                      ),
                      const SizedBox(height: 16),
                      _buildCards(state, notifier),
                    ],
                  ),
                  // Overlay that absorbs all touches during scroll
                  if (_isScrollActive)
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: () {},
                        onPanDown: (_) {},
                        behavior: HitTestBehavior.opaque,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCards(AudioEffectsState s, AudioEffectsNotifier n) {
    return Column(
      children: [
        // ── Tone ──
        EqEffectCard(
          title: 'Tone',
          subtitle: 'Bass & Treble shelves',
          icon: Icons.tune_rounded,
          enabled: s.bass != 0 || s.treble != 0,
          onToggle: (v) {
            if (!v) {
              n.setBass(0);
              n.setTreble(0);
            }
          },
          children: [
            compactSlider(
              'Bass',
              s.bass,
              -12,
              12,
              24,
              n.setBass,
              n.applyNow,
              suffix: 'dB',
            ),
            compactSlider(
              'Treble',
              s.treble,
              -12,
              12,
              24,
              n.setTreble,
              n.applyNow,
              suffix: 'dB',
            ),
          ],
        ),
        const SizedBox(height: 10),

        // ── 18-Band EQ ──
        EqEffectCard(
          title: 'Graphic EQ',
          subtitle: '18 frequency bands',
          icon: Icons.equalizer_rounded,
          enabled: s.eqEnabled,
          onToggle: n.setEqEnabled,
          children: [
            _EqBandSliders(s, n),
            if (s.eqEnabled)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: n.flattenEq,
                    child: Text(
                      'Flatten',
                      style: AfTypography.bodySmall.copyWith(
                        color: AfColors.textTertiary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  TextButton.icon(
                    onPressed: _saveCurrentPreset,
                    icon: const Icon(Icons.save_outlined, size: 14),
                    label: Text(
                      'Save preset',
                      style: AfTypography.bodySmall.copyWith(
                        color: AfColors.indigo400,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 10),

        // ── Dynamics ──
        EqEffectCard(
          title: 'Dynamics',
          subtitle: 'Compressor, Gate, De-esser',
          icon: Icons.waves_rounded,
          enabled: s.loudnorm || s.compressor || s.gate || s.deesser,
          onToggle: (_) {},
          children: [
            _buildToggle('Loudness', 'EBU R128', s.loudnorm, n.setLoudnorm),
            if (s.loudnorm) sectionDivider(),
            _buildToggle(
              'Compressor',
              'Reduces volume spikes',
              s.compressor,
              n.setCompressor,
            ),
            if (s.compressor) ...[
              sectionDivider(),
              compactSlider(
                'Threshold',
                s.compThreshold,
                0.001,
                1,
                100,
                n.setCompThreshold,
                n.applyNow,
                precision: 3,
              ),
              compactSlider(
                'Ratio',
                s.compRatio,
                1,
                20,
                38,
                n.setCompRatio,
                n.applyNow,
                precision: 1,
                suffix: ':1',
              ),
              compactSlider(
                'Attack',
                s.compAttack,
                0.01,
                200,
                100,
                n.setCompAttack,
                n.applyNow,
                precision: 1,
                suffix: 'ms',
              ),
              compactSlider(
                'Release',
                s.compRelease,
                5,
                2000,
                100,
                n.setCompRelease,
                n.applyNow,
                precision: 0,
                suffix: 'ms',
              ),
            ],
            sectionDivider(),
            _buildToggle(
              'Noise Gate',
              'Silences below threshold',
              s.gate,
              n.setGate,
            ),
            if (s.gate) ...[
              sectionDivider(),
              compactSlider(
                'Threshold',
                s.gateThreshold,
                0.001,
                1,
                100,
                n.setGateThreshold,
                n.applyNow,
                precision: 3,
              ),
              compactSlider(
                'Ratio',
                s.gateRatio,
                1,
                20,
                38,
                n.setGateRatio,
                n.applyNow,
                precision: 1,
                suffix: ':1',
              ),
              compactSlider(
                'Attack',
                s.gateAttack,
                0.01,
                200,
                100,
                n.setGateAttack,
                n.applyNow,
                precision: 1,
                suffix: 'ms',
              ),
              compactSlider(
                'Release',
                s.gateRelease,
                5,
                2000,
                100,
                n.setGateRelease,
                n.applyNow,
                precision: 0,
                suffix: 'ms',
              ),
            ],
            sectionDivider(),
            _buildToggle(
              'De-esser',
              'Reduces sibilance',
              s.deesser,
              n.setDeesser,
            ),
            if (s.deesser) ...[
              sectionDivider(),
              compactSlider(
                'Intensity',
                s.deesserIntensity,
                0,
                1,
                20,
                n.setDeesserIntensity,
                n.applyNow,
                precision: 2,
              ),
              compactSlider(
                'Mix',
                s.deesserMix,
                0,
                1,
                20,
                n.setDeesserMix,
                n.applyNow,
                precision: 2,
              ),
              compactSlider(
                'Freq keep',
                s.deesserFreq,
                0,
                1,
                20,
                n.setDeesserFreq,
                n.applyNow,
                precision: 2,
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),

        // ── Echo / Delay ──
        EqEffectCard(
          title: 'Echo / Delay',
          subtitle: 'Multi-tap delay',
          icon: Icons.replay_rounded,
          enabled: s.echoEnabled,
          onToggle: n.setEchoEnabled,
          children: [
            compactSlider(
              'In gain',
              s.echoInGain,
              0,
              1,
              20,
              n.setEchoInGain,
              n.applyNow,
              precision: 2,
            ),
            compactSlider(
              'Out gain',
              s.echoOutGain,
              0,
              1,
              20,
              n.setEchoOutGain,
              n.applyNow,
              precision: 2,
            ),
            compactTextField(
              context,
              'Delays (ms)',
              s.echoDelays,
              '500|250',
              n.setEchoDelays,
            ),
            compactTextField(
              context,
              'Decays (0-1)',
              s.echoDecays,
              '0.5|0.3',
              n.setEchoDecays,
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Separate taps with | (pipe)',
                style: AfTypography.bodySmall.copyWith(
                  color: AfColors.textTertiary,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // ── Pitch & Tempo ──
        EqEffectCard(
          title: 'Pitch & Tempo',
          subtitle: 'Rubberband engine',
          icon: Icons.music_note_rounded,
          enabled: s.rubberbandEnabled,
          onToggle: n.setRubberbandEnabled,
          children: [
            compactSlider(
              'Pitch',
              s.pitch,
              0.5,
              2,
              30,
              n.setPitch,
              n.applyNow,
              suffix: 'x',
              precision: 2,
            ),
            compactSlider(
              'Tempo',
              s.tempo,
              0.5,
              2,
              30,
              n.setTempo,
              n.applyNow,
              suffix: 'x',
              precision: 2,
            ),
          ],
        ),
        const SizedBox(height: 10),

        // ── Spatial ──
        EqEffectCard(
          title: 'Spatial',
          subtitle: 'Crossfeed & Stereo widen',
          icon: Icons.surround_sound_rounded,
          enabled: s.crossfeed || s.stereoWiden,
          onToggle: (_) {},
          children: [
            _buildToggle(
              'Crossfeed',
              'Natural headphone imaging',
              s.crossfeed,
              n.setCrossfeed,
            ),
            if (s.crossfeed) ...[
              sectionDivider(),
              compactSlider(
                'Strength',
                s.crossfeedStrength,
                0,
                1,
                20,
                n.setCrossfeedStrength,
                n.applyNow,
                precision: 2,
              ),
            ],
            sectionDivider(),
            _buildToggle(
              'Stereo widening',
              'Expands stereo image',
              s.stereoWiden,
              n.setStereoWiden,
            ),
            if (s.stereoWiden) ...[
              sectionDivider(),
              compactSlider(
                'Delay',
                s.stereoWidenDelay,
                1,
                100,
                99,
                n.setStereoWidenDelay,
                n.applyNow,
                suffix: 'ms',
                precision: 0,
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),

        // ── Modulation ──
        EqEffectCard(
          title: 'Modulation',
          subtitle: 'Phaser, Flanger, Chorus, Tremolo, Vibrato',
          icon: Icons.blur_on_rounded,
          enabled: s.phaser || s.flanger || s.chorus || s.tremolo || s.vibrato,
          onToggle: (_) {},
          children: [
            _buildToggle(
              'Phaser',
              'Phase-shifting sweep',
              s.phaser,
              n.setPhaser,
            ),
            if (s.phaser) ...[
              sectionDivider(),
              compactSlider(
                'In gain',
                s.phaserInGain,
                0,
                1,
                20,
                n.setPhaserInGain,
                n.applyNow,
                precision: 2,
              ),
              compactSlider(
                'Out gain',
                s.phaserOutGain,
                0,
                1,
                20,
                n.setPhaserOutGain,
                n.applyNow,
                precision: 2,
              ),
              compactSlider(
                'Delay',
                s.phaserDelay,
                0,
                5,
                50,
                n.setPhaserDelay,
                n.applyNow,
                precision: 1,
                suffix: 'ms',
              ),
              compactSlider(
                'Decay',
                s.phaserDecay,
                0,
                0.99,
                99,
                n.setPhaserDecay,
                n.applyNow,
                precision: 2,
              ),
              compactSlider(
                'Speed',
                s.phaserSpeed,
                0.1,
                2,
                19,
                n.setPhaserSpeed,
                n.applyNow,
                precision: 2,
                suffix: 'Hz',
              ),
            ],
            sectionDivider(),
            _buildToggle(
              'Flanger',
              'Flanging with feedback',
              s.flanger,
              n.setFlanger,
            ),
            if (s.flanger) ...[
              sectionDivider(),
              compactSlider(
                'Delay',
                s.flangerDelay,
                0,
                30,
                60,
                n.setFlangerDelay,
                n.applyNow,
                precision: 1,
                suffix: 'ms',
              ),
              compactSlider(
                'Depth',
                s.flangerDepth,
                0,
                10,
                20,
                n.setFlangerDepth,
                n.applyNow,
                precision: 1,
              ),
              compactSlider(
                'Regen',
                s.flangerRegen,
                -95,
                95,
                38,
                n.setFlangerRegen,
                n.applyNow,
                precision: 0,
                suffix: '%',
              ),
              compactSlider(
                'Width',
                s.flangerWidth,
                0,
                100,
                20,
                n.setFlangerWidth,
                n.applyNow,
                precision: 0,
                suffix: '%',
              ),
              compactSlider(
                'Speed',
                s.flangerSpeed,
                0.1,
                10,
                99,
                n.setFlangerSpeed,
                n.applyNow,
                precision: 1,
                suffix: 'Hz',
              ),
            ],
            sectionDivider(),
            _buildToggle('Chorus', 'Multi-voice chorus', s.chorus, n.setChorus),
            if (s.chorus) ...[
              sectionDivider(),
              compactSlider(
                'In gain',
                s.chorusInGain,
                0,
                1,
                20,
                n.setChorusInGain,
                n.applyNow,
                precision: 2,
              ),
              compactSlider(
                'Out gain',
                s.chorusOutGain,
                0,
                1,
                20,
                n.setChorusOutGain,
                n.applyNow,
                precision: 2,
              ),
              compactTextField(
                context,
                'Delays (ms)',
                s.chorusDelays,
                '40|60',
                n.setChorusDelays,
              ),
              compactTextField(
                context,
                'Decays',
                s.chorusDecays,
                '0.4|0.32',
                n.setChorusDecays,
              ),
              compactTextField(
                context,
                'Speeds (Hz)',
                s.chorusSpeeds,
                '0.25|0.4',
                n.setChorusSpeeds,
              ),
              compactTextField(
                context,
                'Depths',
                s.chorusDepths,
                '2|3',
                n.setChorusDepths,
              ),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Separate voices with | (pipe)',
                  style: AfTypography.bodySmall.copyWith(
                    color: AfColors.textTertiary,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
            sectionDivider(),
            _buildToggle(
              'Tremolo',
              'Amplitude modulation',
              s.tremolo,
              n.setTremolo,
            ),
            if (s.tremolo) ...[
              sectionDivider(),
              compactSlider(
                'Frequency',
                s.tremoloFreq,
                0.1,
                20,
                40,
                n.setTremoloFreq,
                n.applyNow,
                precision: 1,
                suffix: 'Hz',
              ),
              compactSlider(
                'Depth',
                s.tremoloDepth,
                0,
                1,
                20,
                n.setTremoloDepth,
                n.applyNow,
                precision: 2,
              ),
            ],
            sectionDivider(),
            _buildToggle(
              'Vibrato',
              'Pitch modulation',
              s.vibrato,
              n.setVibrato,
            ),
            if (s.vibrato) ...[
              sectionDivider(),
              compactSlider(
                'Frequency',
                s.vibratoFreq,
                0.1,
                20,
                40,
                n.setVibratoFreq,
                n.applyNow,
                precision: 1,
                suffix: 'Hz',
              ),
              compactSlider(
                'Depth',
                s.vibratoDepth,
                0,
                1,
                20,
                n.setVibratoDepth,
                n.applyNow,
                precision: 2,
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),

        // ── Creative ──
        EqEffectCard(
          title: 'Creative',
          subtitle: 'Exciter, Crystalizer, Virtual Bass, Bit-crusher',
          icon: Icons.auto_fix_high_rounded,
          enabled: s.exciter || s.crystalizer || s.virtualBass || s.crusher,
          onToggle: (_) {},
          children: [
            _buildToggle(
              'Harmonic exciter',
              'Adds harmonic overtones',
              s.exciter,
              n.setExciter,
            ),
            if (s.exciter) ...[
              sectionDivider(),
              compactSlider(
                'Amount',
                s.exciterAmount,
                0,
                10,
                20,
                n.setExciterAmount,
                n.applyNow,
                precision: 1,
              ),
            ],
            sectionDivider(),
            _buildToggle(
              'Crystalizer',
              'Audio sharpener',
              s.crystalizer,
              n.setCrystalizer,
            ),
            if (s.crystalizer) ...[
              sectionDivider(),
              compactSlider(
                'Intensity',
                s.crystalizerIntensity,
                -10,
                10,
                40,
                n.setCrystalizerIntensity,
                n.applyNow,
                precision: 1,
              ),
            ],
            sectionDivider(),
            _buildToggle(
              'Virtual bass',
              'Psychoacoustic enhancement',
              s.virtualBass,
              n.setVirtualBass,
            ),
            if (s.virtualBass) ...[
              sectionDivider(),
              compactSlider(
                'Cutoff',
                s.virtualBassCutoff,
                100,
                500,
                40,
                n.setVirtualBassCutoff,
                n.applyNow,
                suffix: 'Hz',
                precision: 0,
              ),
            ],
            sectionDivider(),
            _buildToggle(
              'Bit-crusher',
              'Lo-fi resolution',
              s.crusher,
              n.setCrusher,
            ),
            if (s.crusher) ...[
              sectionDivider(),
              compactSlider(
                'Bits',
                s.crusherBits,
                1,
                16,
                15,
                n.setCrusherBits,
                n.applyNow,
                precision: 0,
              ),
              compactSlider(
                'Mix',
                s.crusherMix,
                0,
                1,
                20,
                n.setCrusherMix,
                n.applyNow,
                precision: 2,
              ),
              compactSlider(
                'Samples',
                s.crusherSamples,
                1,
                250,
                50,
                n.setCrusherSamples,
                n.applyNow,
                precision: 0,
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildToggle(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: AfTypography.bodySmall.copyWith(fontSize: 13),
                ),
                Text(
                  subtitle,
                  style: AfTypography.bodySmall.copyWith(
                    color: AfColors.textTertiary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 24,
            child: Switch.adaptive(
              value: value,
              activeTrackColor: AfColors.indigo500,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveCurrentPreset() async {
    final s = ref.read(audioEffectsProvider);
    final ctrl = TextEditingController();
    final name = await showBlurDialog<String>(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Save EQ Preset', style: AfTypography.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Preset name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, ctrl.text.trim()),
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (name == null || name.isEmpty) return;
    final preset = EqPreset(
      bands: Map.of(s.eqBands),
      bass: s.bass,
      treble: s.treble,
    );
    await PlayerSettingsStore.saveEqPreset(name, preset);
    setState(() => _userPresets[name] = preset);
  }

  Future<void> _deletePreset(String name) async {
    await PlayerSettingsStore.deleteEqPreset(name);
    setState(() => _userPresets.remove(name));
  }
}

// ── Preset chips row ────────────────────────────────────────────────────────

class _PresetRow extends StatelessWidget {
  const _PresetRow({
    required this.presets,
    required this.userPresets,
    required this.activePreset,
    required this.onApply,
    required this.onDelete,
    required this.onSave,
    required this.state,
    required this.notifier,
  });

  final Map<String, EqPreset> presets;
  final Map<String, EqPreset> userPresets;
  final String? activePreset;
  final void Function(String, EqPreset) onApply;
  final Future<void> Function(String) onDelete;
  final VoidCallback onSave;
  final AudioEffectsState state;
  final AudioEffectsNotifier notifier;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'PRESETS',
          style: AfTypography.bodySmall.copyWith(
            color: AfColors.textTertiary,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: presets.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, index) {
              if (index == presets.length) {
                return _saveChip(onSave);
              }
              final entry = presets.entries.elementAt(index);
              final isActive = activePreset == entry.key;
              final isUser = userPresets.containsKey(entry.key);
              return GestureDetector(
                onLongPress: isUser
                    ? () => _showDelete(context, entry.key)
                    : null,
                child: _PresetChip(
                  label: entry.key,
                  isActive: isActive,
                  onTap: () => onApply(entry.key, entry.value),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showDelete(BuildContext context, String name) {
    showBlurDialog<void>(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Delete "$name"?', style: AfTypography.titleMedium),
          const SizedBox(height: 8),
          Text(
            'This preset will be permanently removed.',
            style: AfTypography.bodyMedium,
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  onDelete(name);
                },
                child: const Text(
                  'Delete',
                  style: TextStyle(color: AfColors.semanticError),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: isActive
              ? AfColors.indigo500.withValues(alpha: 0.25)
              : AfColors.surfaceHigh,
          borderRadius: BorderRadius.circular(18),
          border: isActive
              ? Border.all(
                  color: AfColors.indigo500.withValues(alpha: 0.6),
                  width: 1.2,
                )
              : null,
        ),
        child: Text(
          label,
          style: AfTypography.bodySmall.copyWith(
            fontSize: 12,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            color: isActive ? AfColors.indigo300 : AfColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

Widget _saveChip(VoidCallback onTap) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AfColors.surfaceHigh,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AfColors.surfaceHigh),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.add, size: 14, color: AfColors.textTertiary),
          const SizedBox(width: 4),
          Text(
            'Save',
            style: AfTypography.bodySmall.copyWith(
              fontSize: 12,
              color: AfColors.textTertiary,
            ),
          ),
        ],
      ),
    ),
  );
}

// ── 18-band EQ sliders (extracted widget) ───────────────────────────────────

class _EqBandSliders extends StatelessWidget {
  const _EqBandSliders(this.state, this.notifier);
  final AudioEffectsState state;
  final AudioEffectsNotifier notifier;

  @override
  Widget build(BuildContext context) {
    if (!state.eqEnabled) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: kEqBands.entries.map((entry) {
        final key = entry.key;
        final freq = entry.value;
        final gain = state.eqBands[key] ?? 1.0;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Row(
            children: [
              SizedBox(
                width: 52,
                child: Text(
                  freq,
                  style: AfTypography.mono.copyWith(
                    fontSize: 10,
                    color: AfColors.textTertiary,
                  ),
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 5,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 10,
                    ),
                  ),
                  child: Slider(
                    key: ValueKey(key),
                    value: gain.clamp(0, 4),
                    min: 0,
                    max: 4,
                    divisions: 40,
                    activeColor: AfColors.indigo400,
                    inactiveColor: AfColors.surfaceHigh,
                    onChanged: (v) => notifier.setEqBand(key, v),
                    onChangeEnd: (_) => notifier.applyNow(),
                  ),
                ),
              ),
              SizedBox(
                width: 30,
                child: Text(
                  gain.toStringAsFixed(1),
                  textAlign: TextAlign.right,
                  style: AfTypography.mono.copyWith(
                    fontSize: 10,
                    color: AfColors.textTertiary,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
