import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppMode { server, local }

final appModeProvider = StateProvider<AppMode?>((ref) => null);

final localScanProgressProvider = StateProvider<({int completed, int total})?>(
  (ref) => null,
);

final localOnboardingCompletedProvider = StateProvider<bool>((ref) => false);
