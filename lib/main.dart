import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/audio/player_service.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize the OS-integrated audio session up front. Without this the
  // lock-screen / media-controls surface never appears (non-negotiable
  // §4.3 — "lock screen + media controls required").
  final handler = AfPlayerService();
  await AudioService.init(
    builder: () => handler,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'dev.aetherfin.audio',
      androidNotificationChannelName: 'Aetherfin playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      notificationColor: Color(0xFF332C7A),
    ),
  );

  runApp(
    ProviderScope(
      overrides: [
        playerServiceProvider.overrideWithValue(handler),
      ],
      child: const AetherfinApp(),
    ),
  );
}
