/// A single parametric EQ band with adjustable frequency, gain, and Q.
class ParametricBand {
  const ParametricBand({
    required this.frequency,
    this.gain = 0.0,
    this.q = 1.0,
    this.enabled = true,
  });

  /// Center frequency in Hz (20–20000).
  final double frequency;

  /// Gain in dB (-24.0 to +24.0).
  final double gain;

  /// Q factor / bandwidth (0.3 to 12.0).
  /// Lower Q = wider band, higher Q = narrower/surgical.
  final double q;

  /// Whether this band is active.
  final bool enabled;

  // ── Serialization ──────────────────────────────────────────────────────

  factory ParametricBand.fromJson(Map<String, dynamic> json) => ParametricBand(
    frequency: (json['frequency'] as num).toDouble(),
    gain: (json['gain'] as num).toDouble(),
    q: (json['q'] as num).toDouble(),
    enabled: json['enabled'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {
    'frequency': frequency,
    'gain': gain,
    'q': q,
    'enabled': enabled,
  };

  // ── Lavfi serialization ────────────────────────────────────────────────

  /// Convert to lavfi equalizer filter string.
  /// Returns empty string if disabled or gain is effectively zero.
  String toLavfiString() {
    if (!enabled || gain.abs() < 0.05) return '';
    return 'lavfi-equalizer=f=${frequency.toStringAsFixed(1)}'
        ':t=q'
        ':w=${q.toStringAsFixed(2)}'
        ':g=${gain.toStringAsFixed(1)}';
  }

  // ── Defaults ───────────────────────────────────────────────────────────

  /// Standard 5-band defaults (logarithmic spacing across 20 Hz – 20 kHz).
  static const kDefaultBands = [
    (frequency: 60.0, q: 0.7), // Sub-bass
    (frequency: 230.0, q: 0.7), // Bass warmth
    (frequency: 910.0, q: 1.0), // Midrange
    (frequency: 3500.0, q: 1.0), // Presence
    (frequency: 12000.0, q: 0.7), // Air / brilliance
  ];

  /// Create default band at given index.
  static ParametricBand defaultAt(int index) {
    final d = kDefaultBands[index];
    return ParametricBand(frequency: d.frequency, q: d.q);
  }

  /// Create a flat (default) set of 5 bands.
  static List<ParametricBand> defaultBands() => List.generate(5, defaultAt);
}

/// A preset for the parametric EQ.
class ParametricPreset {
  const ParametricPreset({required this.name, required this.bands});

  final String name;
  final List<ParametricBand> bands;

  factory ParametricPreset.fromJson(Map<String, dynamic> json) =>
      ParametricPreset(
        name: json['name'] as String,
        bands: (json['bands'] as List)
            .map((b) => ParametricBand.fromJson(b as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
    'name': name,
    'bands': bands.map((b) => b.toJson()).toList(),
  };
}
