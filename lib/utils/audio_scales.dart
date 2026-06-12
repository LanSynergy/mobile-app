import 'dart:math';

import 'package:flutter/material.dart';

/// Audio utility for professional EQ — frequency mapping, dB conversion,
/// haptic thresholds, and band color coding.
///
/// All pure functions — no Flutter widget dependencies. Testable in isolation.
abstract final class AudioScales {
  // ── Constants ──────────────────────────────────────────────────────────────
  static const double minFreq = 20.0;
  static const double maxFreq = 20000.0;
  static final double _logRange = log(maxFreq / minFreq);

  /// ISO 1/3-octave center frequencies for frequency snapping.
  static const List<double> isoFrequencies = [
    20,
    25,
    31.5,
    40,
    50,
    63,
    80,
    100,
    125,
    160,
    200,
    250,
    315,
    400,
    500,
    630,
    800,
    1000,
    1250,
    1600,
    2000,
    2500,
    3150,
    4000,
    5000,
    6300,
    8000,
    10000,
    12500,
    16000,
    20000,
  ];

  // ── Frequency normalization (logarithmic) ──────────────────────────────────

  /// Maps frequency (Hz) to normalized 0.0–1.0 position.
  /// Uses logarithmic scale: 20 Hz → 20 kHz.
  static double freqToNormalized(double freq) {
    return (log(freq / minFreq) / _logRange).clamp(0.0, 1.0);
  }

  /// Maps normalized position (0.0–1.0) back to frequency (Hz).
  static double normalizedToFreq(double normalized) {
    return minFreq *
        pow(maxFreq / minFreq, normalized.clamp(0.0, 1.0)).toDouble();
  }

  /// Maps frequency to screen X coordinate.
  static double freqToX(double freq, double width) =>
      freqToNormalized(freq) * width;

  /// Maps screen X coordinate to frequency.
  static double xToFreq(double x, double width) => normalizedToFreq(x / width);

  // ── dB ↔ Y coordinate mapping ─────────────────────────────────────────────

  /// Maps dB gain to screen Y coordinate.
  /// 0 dB is center, positive = up, negative = down.
  static double dbToY(double db, double height, {double dbRange = 12.0}) {
    final center = height / 2;
    return center - (db / dbRange) * center;
  }

  /// Maps screen Y coordinate to dB gain.
  static double yToDb(double y, double height, {double dbRange = 12.0}) {
    final center = height / 2;
    return ((center - y) / center) * dbRange;
  }

  // ── dB ↔ multiplier conversion ────────────────────────────────────────────

  /// Converts multiplier (1.0 = unity) to dB: 20 * log10(multiplier).
  static double multiplierToDb(double multiplier) {
    if (multiplier <= 0) return -double.infinity;
    return 20 * log(multiplier) / ln10;
  }

  /// Converts dB to multiplier: 10^(dB/20).
  static double dbToMultiplier(double db) {
    return pow(10, db / 20).toDouble();
  }

  // ── Band colors (frequency-coded) ─────────────────────────────────────────

  /// Returns a frequency-coded color for a band at the given frequency.
  /// Red (bass) → Orange → Yellow → Green → Blue (treble).
  static Color bandColorForFrequency(double freq) {
    final normalized = freqToNormalized(freq);
    // Hue: 0 (red) → 240 (blue) across the frequency range
    final hue = normalized * 240;
    return HSVColor.fromAHSV(1.0, hue, 0.8, 0.9).toColor();
  }

  // ── Snap-to-value (dB) ────────────────────────────────────────────────────

  /// Snaps dB value to finer resolution when moving slowly.
  /// Slow velocity (< 50): snap to 0.1 dB.
  /// Fast velocity (≥ 50): snap to 1 dB.
  static double snapToValue(double value, {double velocity = 0}) {
    const slowThreshold = 50.0;
    if (velocity.abs() < slowThreshold) {
      return (value * 10).round() / 10.0;
    }
    return value.roundToDouble();
  }

  /// Snaps frequency to the nearest ISO standard value (logarithmic distance).
  static double snapToIsoFrequency(double freq) {
    double closest = isoFrequencies.first;
    double minDiff = double.infinity;
    for (final stdFreq in isoFrequencies) {
      final diff = (log(freq) - log(stdFreq)).abs();
      if (diff < minDiff) {
        minDiff = diff;
        closest = stdFreq;
      }
    }
    return closest;
  }

  // ── Haptic feedback detection ──────────────────────────────────────────────

  /// Returns true if a haptic feedback should trigger.
  /// Triggers on whole-dB threshold crossing or 0 dB crossing.
  static bool shouldTriggerHaptic(double oldValue, double newValue) {
    // Crossed a whole dB value (floor differs)
    if (oldValue.floor() != newValue.floor()) {
      return true;
    }
    // Crossed 0 dB (unity)
    if ((oldValue > 0 && newValue <= 0) || (oldValue < 0 && newValue >= 0)) {
      return true;
    }
    return false;
  }
}
