import 'parametric_band.dart';

/// Built-in parametric EQ presets.
const kParametricPresets = <String, ParametricPreset>{
  'Flat': ParametricPreset(
    name: 'Flat',
    bands: [
      ParametricBand(frequency: 60, gain: 0, q: 0.7),
      ParametricBand(frequency: 230, gain: 0, q: 0.7),
      ParametricBand(frequency: 910, gain: 0, q: 1.0),
      ParametricBand(frequency: 3500, gain: 0, q: 1.0),
      ParametricBand(frequency: 12000, gain: 0, q: 0.7),
    ],
  ),
  'Vocal Presence': ParametricPreset(
    name: 'Vocal Presence',
    bands: [
      ParametricBand(frequency: 230, gain: -2, q: 1.0),
      ParametricBand(frequency: 910, gain: 1, q: 1.0),
      ParametricBand(frequency: 3500, gain: 3, q: 1.2),
      ParametricBand(frequency: 12000, gain: 1, q: 0.7),
    ],
  ),
  'Remove Resonance': ParametricPreset(
    name: 'Remove Resonance',
    bands: [ParametricBand(frequency: 800, gain: -6, q: 8.0)],
  ),
  'Air Boost': ParametricPreset(
    name: 'Air Boost',
    bands: [ParametricBand(frequency: 12000, gain: 3, q: 0.7)],
  ),
  'Low Cut': ParametricPreset(
    name: 'Low Cut',
    bands: [ParametricBand(frequency: 80, gain: -12, q: 0.5)],
  ),
  'Scooped': ParametricPreset(
    name: 'Scooped',
    bands: [
      ParametricBand(frequency: 230, gain: -3, q: 1.0),
      ParametricBand(frequency: 910, gain: -4, q: 1.2),
      ParametricBand(frequency: 3500, gain: 2, q: 1.0),
    ],
  ),
};
