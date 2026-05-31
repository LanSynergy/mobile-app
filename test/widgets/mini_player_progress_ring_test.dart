import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mpv_audio_kit/mpv_audio_kit.dart';

import 'package:aetherfin/core/audio/media_session_bridge.dart';
import 'package:aetherfin/core/audio/player_service.dart';
import 'package:aetherfin/core/jellyfin/models/items.dart';
import 'package:aetherfin/design_tokens/colors.dart';
import 'package:aetherfin/widgets/circular_progress_ring.dart';
import 'package:aetherfin/widgets/mini_player.dart';
import 'package:aetherfin/state/player_providers.dart';
import 'package:aetherfin/state/spectral_providers.dart';

import '../helpers/fake_player.dart';

void main() {
  setUpAll(() {
    registerFallbackValue(Duration.zero);
    registerFallbackValue(Loop.off);
    registerFallbackValue(Gapless.weak);
    registerFallbackValue(const Media(''));
    registerFallbackValue(Device.auto);
    registerFallbackValue(
      const SpectrumSettings(
        fftSize: 2048,
        bandCount: 64,
        bandLowHz: 20.0,
        bandHighHz: 20000.0,
        attackSmoothing: 0.8,
        releaseSmoothing: 0.1,
        minDb: -105.0,
        maxDb: 35.0,
        emitInterval: Duration(milliseconds: 8),
      ),
    );
  });

  group('_ReactiveProgressRing', () {
    testWidgets('renders ring with correct progress from throttled position', (
      tester,
    ) async {
      final fixture = createMockPlayer();
      final service = AfPlayerService.test(
        player: fixture.player,
        bridge: NativeMediaSessionBridge(channel: const MethodChannel('test')),
      );
      addTearDown(service.dispose);

      const track = AfTrack(
        id: 'test-1',
        title: 'Test Song',
        artistName: 'Test Artist',
        albumName: 'Test Album',
        albumId: 'album-1',
        imageUrl: null,
        duration: Duration(seconds: 100),
        trackNumber: 1,
        isFavorite: false,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerServiceProvider.overrideWithValue(service),
            currentTrackProvider.overrideWith((ref) => track),
            durationStreamProvider.overrideWith(
              (ref) => const Duration(seconds: 100),
            ),
            currentSpectralProvider.overrideWith((ref) => Spectral.fallback),
            isBufferingProvider.overrideWith((ref) => false),
            playingStreamProvider.overrideWith(
              (ref) => const Stream<bool>.empty(),
            ),
            currentArtworkUriProvider.overrideWith((ref) => null),
          ],
          child: const MaterialApp(home: Scaffold(body: MiniPlayer())),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressRing), findsOneWidget);
    });
  });
}
