import 'parametric_band.dart';

/// Built-in parametric EQ presets.
const kParametricPresets = <String, ParametricPreset>{
  'Flat': ParametricPreset(
    name: 'Flat',
    bands: [
      ParametricBand(frequency: 31, gain: 0, q: 0.7),
      ParametricBand(frequency: 62, gain: 0, q: 0.7),
      ParametricBand(frequency: 125, gain: 0, q: 0.8),
      ParametricBand(frequency: 250, gain: 0, q: 0.9),
      ParametricBand(frequency: 500, gain: 0, q: 1.0),
      ParametricBand(frequency: 1000, gain: 0, q: 1.0),
      ParametricBand(frequency: 2000, gain: 0, q: 1.0),
      ParametricBand(frequency: 4000, gain: 0, q: 1.2),
      ParametricBand(frequency: 8000, gain: 0, q: 0.9),
      ParametricBand(frequency: 16000, gain: 0, q: 0.7),
    ],
  ),
  'Vocal Presence': ParametricPreset(
    name: 'Vocal Presence',
    bands: [
      ParametricBand(frequency: 250, gain: -2, q: 0.9),
      ParametricBand(frequency: 1000, gain: 1, q: 1.0),
      ParametricBand(frequency: 4000, gain: 3, q: 1.2),
      ParametricBand(frequency: 8000, gain: 1, q: 0.9),
    ],
  ),
  'Remove Resonance': ParametricPreset(
    name: 'Remove Resonance',
    bands: [ParametricBand(frequency: 1000, gain: -6, q: 8.0)],
  ),
  'Air Boost': ParametricPreset(
    name: 'Air Boost',
    bands: [ParametricBand(frequency: 16000, gain: 3, q: 0.7)],
  ),
  'Low Cut': ParametricPreset(
    name: 'Low Cut',
    bands: [ParametricBand(frequency: 62, gain: -12, q: 0.5)],
  ),
  'Scooped': ParametricPreset(
    name: 'Scooped',
    bands: [
      ParametricBand(frequency: 250, gain: -3, q: 0.9),
      ParametricBand(frequency: 1000, gain: -4, q: 1.0),
      ParametricBand(frequency: 4000, gain: 2, q: 1.2),
    ],
  ),
};
