import 'package:flutter/material.dart';

import '../design_tokens/tokens.dart';

/// Parses a hex color string (6 or 8 digits, optional #) into a [Color].
/// Returns [fallback] if the string is malformed.
Color parseHexColor(String hex, {Color fallback = AfColors.accentPrimary}) {
  try {
    final cleaned = hex.replaceFirst('#', '');
    if (cleaned.length != 6 && cleaned.length != 8) return fallback;
    final value = int.parse(
      cleaned.length == 6 ? 'FF$cleaned' : cleaned,
      radix: 16,
    );
    return Color(value);
  } catch (_) {
    return fallback;
  }
}
