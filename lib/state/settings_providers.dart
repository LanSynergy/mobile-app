import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/jellyfin/models/server.dart';

final reducedMotionProvider = Provider.autoDispose<bool>((ref) {
  try {
    return WidgetsBinding.instance.accessibilityFeatures.reduceMotion;
  } catch (_) {
    return false;
  }
});

final discoveredServersProvider = StateProvider<List<JellyfinServer>>((ref) => const <JellyfinServer>[]);

final artworkPulseEnabledProvider = StateProvider<bool>((ref) => true);
