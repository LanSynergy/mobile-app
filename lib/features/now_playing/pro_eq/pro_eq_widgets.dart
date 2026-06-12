import 'package:flutter/material.dart';

import '../../../core/audio/player_settings_store.dart' show EqPreset;
import '../../../design_tokens/pro_audio.dart';
import '../../../utils/frequency_response_painter.dart';
import '../../../utils/graphic_eq_painter.dart';
import '../eq_preset.dart';
import '../parametric_band.dart';

// ═════════════════════════════════════════════════════════════════════════════
// Section Panel
// ═════════════════════════════════════════════════════════════════════════════

/// Rack-panel section container with title bar.
class ProSectionPanel extends StatelessWidget {
  const ProSectionPanel({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ProAudioColors.bgPanel,
        borderRadius: BorderRadius.circular(ProAudioSpacing.panelRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Title bar
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: ProAudioSpacing.panelPadding,
              vertical: ProAudioSpacing.controlGap * 2,
            ),
            decoration: const BoxDecoration(
              color: ProAudioColors.bgOverlay,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(ProAudioSpacing.panelRadius),
                topRight: Radius.circular(ProAudioSpacing.panelRadius),
              ),
            ),
            child: Text(title, style: ProAudioTypography.sectionHeader),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(ProAudioSpacing.panelPadding),
            child: child,
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Stereo Peak Meter
// ═════════════════════════════════════════════════════════════════════════════

/// Horizontal stereo peak meter with green/yellow/red zones.
class ProStereoPeakMeter extends StatelessWidget {
  const ProStereoPeakMeter({
    super.key,
    required this.leftLevel,
    required this.rightLevel,
    this.showPeakHold = true,
  });

  final double leftLevel;
  final double rightLevel;
  final bool showPeakHold;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildMeterBar('L', leftLevel),
        const SizedBox(height: 2),
        _buildMeterBar('R', rightLevel),
      ],
    );
  }

  Widget _buildMeterBar(String channel, double level) {
    return Row(
      children: [
        SizedBox(
          width: 12,
          child: Text(channel, style: ProAudioTypography.dbLabel),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  // Background
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: ProAudioColors.bgPrimary,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                  // Level bar with gradient zones
                  Container(
                    height: 4,
                    width: constraints.maxWidth * level.clamp(0.0, 1.0),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          ProAudioColors.meterGreen,
                          ProAudioColors.meterGreen,
                          ProAudioColors.meterYellow,
                          ProAudioColors.meterRed,
                        ],
                        stops: [0.0, 0.5, 0.75, 1.0],
                      ),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Frequency Response View
// ═════════════════════════════════════════════════════════════════════════════

/// Interactive frequency response curve with draggable band nodes.
class ProFrequencyResponseView extends StatefulWidget {
  const ProFrequencyResponseView({
    super.key,
    required this.bands,
    required this.selectedBand,
    required this.accentColor,
    required this.onBandChanged,
    required this.onBandSelected,
  });

  final List<ParametricBand> bands;
  final int selectedBand;
  final Color accentColor;
  final void Function(int index, ParametricBand band) onBandChanged;
  final void Function(int? index) onBandSelected;

  @override
  State<ProFrequencyResponseView> createState() =>
      _ProFrequencyResponseViewState();
}

class _ProFrequencyResponseViewState extends State<ProFrequencyResponseView> {
  int? _draggingBand;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: _handlePanStart,
      onPanUpdate: _handlePanUpdate,
      onPanEnd: (_) => setState(() => _draggingBand = null),
      child: CustomPaint(
        painter: FrequencyResponsePainter(
          bands: widget.bands,
          selectedBand: _draggingBand ?? widget.selectedBand,
          accentColor: widget.accentColor,
        ),
        size: Size.infinite,
      ),
    );
  }

  void _handlePanStart(DragStartDetails details) {
    _draggingBand = _bandAtPosition(details.localPosition);
    if (_draggingBand != null) {
      widget.onBandSelected(_draggingBand);
    }
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (_draggingBand == null) return;
    final band = widget.bands[_draggingBand!];
    final newGain = (band.gain - details.delta.dy * 0.5).clamp(-24.0, 24.0);
    final newFreq = FrequencyResponsePainter.normalizedToFreq(
      (details.localPosition.dx / (context.size?.width ?? 400)).clamp(0.0, 1.0),
    ).clamp(20.0, 20000.0);
    widget.onBandChanged(
      _draggingBand!,
      ParametricBand(
        frequency: newFreq,
        gain: newGain,
        q: band.q,
        enabled: band.enabled,
      ),
    );
  }

  int? _bandAtPosition(Offset pos) {
    final width = context.size?.width ?? 400;
    final height = context.size?.height ?? 160;
    for (var i = 0; i < widget.bands.length; i++) {
      if (!widget.bands[i].enabled) continue;
      final handleX =
          FrequencyResponsePainter.freqToNormalized(widget.bands[i].frequency) *
          width;
      final handleY = FrequencyResponsePainter.dbToY(
        widget.bands[i].gain,
        height,
      );
      final handlePos = Offset(handleX, handleY);
      if ((handlePos - pos).distance < 20) return i;
    }
    return null;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Parametric Controls
// ═════════════════════════════════════════════════════════════════════════════

/// 5-band parametric EQ controls with gain/frequency/Q sliders.
class ProParametricControls extends StatelessWidget {
  const ProParametricControls({
    super.key,
    required this.bands,
    required this.selectedBand,
    required this.onBandSelected,
    required this.onBandChanged,
  });

  final List<ParametricBand> bands;
  final int selectedBand;
  final ValueChanged<int> onBandSelected;
  final void Function(int index, ParametricBand band) onBandChanged;

  @override
  Widget build(BuildContext context) {
    final displayBands = bands.take(5).toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Band selector tabs
        Row(
          children: List.generate(displayBands.length, (i) {
            final isSelected = i == selectedBand;
            return Expanded(
              child: GestureDetector(
                onTap: () => onBandSelected(i),
                child: Container(
                  height: 24,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? ProAudioColors.accentFocus.withValues(alpha: 0.3)
                        : ProAudioColors.bgSurface,
                    borderRadius: BorderRadius.circular(
                      ProAudioSpacing.controlRadius,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${i + 1}',
                    style: ProAudioTypography.readout.copyWith(
                      color: isSelected
                          ? ProAudioColors.activeNode
                          : ProAudioColors.textDim,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: ProAudioSpacing.controlGap * 4),

        // Selected band controls
        if (selectedBand < displayBands.length) ...[
          _buildControl(
            label: 'Freq',
            value: displayBands[selectedBand].frequency,
            min: 20,
            max: 20000,
            suffix: 'Hz',
            onChanged: (v) => onBandChanged(
              selectedBand,
              ParametricBand(
                frequency: v,
                gain: displayBands[selectedBand].gain,
                q: displayBands[selectedBand].q,
                enabled: displayBands[selectedBand].enabled,
              ),
            ),
          ),
          const SizedBox(height: ProAudioSpacing.controlGap * 2),
          _buildControl(
            label: 'Gain',
            value: displayBands[selectedBand].gain,
            min: -24,
            max: 24,
            suffix: 'dB',
            onChanged: (v) => onBandChanged(
              selectedBand,
              ParametricBand(
                frequency: displayBands[selectedBand].frequency,
                gain: v,
                q: displayBands[selectedBand].q,
                enabled: displayBands[selectedBand].enabled,
              ),
            ),
          ),
          const SizedBox(height: ProAudioSpacing.controlGap * 2),
          _buildControl(
            label: 'Q',
            value: displayBands[selectedBand].q,
            min: 0.3,
            max: 12,
            suffix: '',
            onChanged: (v) => onBandChanged(
              selectedBand,
              ParametricBand(
                frequency: displayBands[selectedBand].frequency,
                gain: displayBands[selectedBand].gain,
                q: v,
                enabled: displayBands[selectedBand].enabled,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildControl({
    required String label,
    required double value,
    required double min,
    required double max,
    required String suffix,
    required ValueChanged<double> onChanged,
  }) {
    final displayValue = label == 'Freq'
        ? (value >= 1000
              ? '${(value / 1000).toStringAsFixed(1)}k'
              : '${value.toInt()}')
        : label == 'Gain'
        ? '${value >= 0 ? '+' : ''}${value.toStringAsFixed(1)}'
        : value.toStringAsFixed(1);

    return Row(
      children: [
        SizedBox(
          width: 40,
          child: Text(label, style: ProAudioTypography.controlLabel),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              activeTrackColor: ProAudioColors.accentFocus,
              inactiveTrackColor: ProAudioColors.bgSurface,
              thumbColor: ProAudioColors.activeNode,
              overlayColor: ProAudioColors.accentFocus.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 60,
          child: Text(
            '$displayValue $suffix',
            style: ProAudioTypography.readout,
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Graphic EQ Controls
// ═════════════════════════════════════════════════════════════════════════════

/// 18-band graphic EQ with vertical faders and frequency labels.
class ProGraphicEqControls extends StatelessWidget {
  const ProGraphicEqControls({
    super.key,
    required this.bands,
    required this.gains,
    required this.enabled,
    this.selectedBand,
    required this.onEnabledChanged,
    required this.onGainChanged,
    required this.onBandSelected,
  });

  final Map<String, String> bands;
  final Map<String, double> gains;
  final bool enabled;
  final int? selectedBand;
  final ValueChanged<bool> onEnabledChanged;
  final void Function(String key, double gain) onGainChanged;
  final ValueChanged<int?> onBandSelected;

  @override
  Widget build(BuildContext context) {
    final keys = bands.keys.toList();
    final values = bands.values.toList();
    final gainValues = keys.map((k) => gains[k] ?? 1.0).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Toggle
        Row(
          children: [
            const Text('Enable', style: ProAudioTypography.controlLabel),
            const Spacer(),
            Switch(
              value: enabled,
              onChanged: onEnabledChanged,
              activeThumbColor: ProAudioColors.accentFocus,
            ),
          ],
        ),
        const SizedBox(height: ProAudioSpacing.controlGap * 4),

        // Vertical faders
        SizedBox(
          height: 120,
          child: CustomPaint(
            painter: GraphicEqPainter(
              bands: values,
              gains: gainValues,
              accentColor: ProAudioColors.accentFocus,
              enabled: enabled,
              selectedBand: selectedBand,
            ),
            size: Size.infinite,
          ),
        ),

        // dB grid labels on left
        // Frequency labels are drawn by the painter
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Tone Controls
// ═════════════════════════════════════════════════════════════════════════════

/// Bass and treble tone controls.
class ProToneControls extends StatelessWidget {
  const ProToneControls({
    super.key,
    required this.bass,
    required this.treble,
    required this.onChanged,
  });

  final double bass;
  final double treble;
  final void Function(double bass, double treble) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildToneSlider(
          label: 'Bass',
          value: bass,
          onChanged: (v) => onChanged(v, treble),
        ),
        const SizedBox(height: ProAudioSpacing.controlGap * 2),
        _buildToneSlider(
          label: 'Treble',
          value: treble,
          onChanged: (v) => onChanged(bass, v),
        ),
      ],
    );
  }

  Widget _buildToneSlider({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(label, style: ProAudioTypography.controlLabel),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              activeTrackColor: ProAudioColors.accentFocus,
              inactiveTrackColor: ProAudioColors.bgSurface,
              thumbColor: ProAudioColors.activeNode,
              overlayColor: ProAudioColors.accentFocus.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: value.clamp(-12.0, 12.0),
              min: -12,
              max: 12,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 50,
          child: Text(
            '${value >= 0 ? '+' : ''}${value.toStringAsFixed(0)} dB',
            style: ProAudioTypography.readout,
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Preset Chips
// ═════════════════════════════════════════════════════════════════════════════

/// Horizontal scrolling row of EQ preset chips.
class ProPresetChips extends StatelessWidget {
  const ProPresetChips({
    super.key,
    required this.activePreset,
    required this.onApply,
  });

  final String? activePreset;
  final void Function(String name, EqPreset preset) onApply;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: kBuiltInPresets.entries.map((entry) {
          final isActive = activePreset == entry.key;
          return Padding(
            padding: const EdgeInsets.only(
              right: ProAudioSpacing.controlGap * 4,
            ),
            child: ChoiceChip(
              label: Text(entry.key),
              selected: isActive,
              onSelected: (_) => onApply(entry.key, entry.value),
              selectedColor: ProAudioColors.accentFocus.withValues(alpha: 0.3),
              backgroundColor: ProAudioColors.bgSurface,
              labelStyle: ProAudioTypography.controlLabel.copyWith(
                color: isActive
                    ? ProAudioColors.activeNode
                    : ProAudioColors.textDim,
              ),
              side: isActive
                  ? const BorderSide(
                      color: ProAudioColors.accentFocus,
                      width: 1.5,
                    )
                  : const BorderSide(color: ProAudioColors.bgSurface),
            ),
          );
        }).toList(),
      ),
    );
  }
}
