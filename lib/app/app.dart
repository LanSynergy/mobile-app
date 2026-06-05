import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_shaders_ui/flutter_shaders_ui.dart';

import '../design_tokens/colors.dart';
import '../state/animated_spectral.dart';
import '../utils/log.dart';
import '../widgets/global_mini_player_overlay.dart';
import 'router.dart';
import 'theme.dart';

/// Root widget. Uses [appRouter] directly — a module-level singleton that
/// is never recreated. This prevents go_router's internal
/// [StatefulNavigationShell] from receiving a new key on auth state changes,
/// which was the cause of the recurring "Duplicate GlobalKey" crash.
///
/// Auth redirects are handled by [_authRefresh] inside router.dart, which
/// is notified by a [ProviderContainer] listener wired in main.dart.
class AetherfinApp extends ConsumerWidget {
  const AetherfinApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    afLog('boot', 'AetherfinApp.build');
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );

    return AnimatedSpectralScope(child: _AetherfinRouter());
  }
}

class _AetherfinRouter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Spectral>(
      valueListenable: animatedSpectral,
      builder: (context, spectral, _) {
        final theme = buildNocturneThemeFromSpectral(spectral);
        return MaterialApp.router(
          title: 'Aetherfin',
          debugShowCheckedModeBanner: false,
          themeMode: ThemeMode.dark,
          darkTheme: theme,
          theme: theme,
          routerConfig: appRouter,
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            final clamped = mq.textScaler.clamp(
              minScaleFactor: 0.85,
              maxScaleFactor: 1.3,
            );
            return MediaQuery(
              data: mq.copyWith(textScaler: clamped),
              child: Stack(
                children: [
                  child ?? const SizedBox.shrink(),
                  const GlobalMiniPlayerOverlay(),

                  // Offscreen shader warmup — triggers Skia GPU shader
                  // compilation for BackdropFilter blur and WaveBackground
                  // on the first frame, preventing jank when these are
                  // first used during navigation.
                  const _ShaderWarmUp(),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Renders the heaviest GPU shaders offscreen on the first frame so Skia
/// compiles them while the user is looking at the splash/welcome screen.
/// Removed automatically after the first paint via [State].
class _ShaderWarmUp extends StatefulWidget {
  const _ShaderWarmUp();
  @override
  State<_ShaderWarmUp> createState() => _ShaderWarmUpState();
}

class _ShaderWarmUpState extends State<_ShaderWarmUp> {
  bool _done = false;

  @override
  void initState() {
    super.initState();
    // Defer removal to the next frame so the first paint triggers shader
    // compilation before the widget tree removes it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _done = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return const SizedBox.shrink();

    return Offstage(
      offstage: true,
      child: Stack(
        children: [
          // Warm up the WaveBackground GLSL shader (used in AppShell + queue).
          const SizedBox(
            width: 1,
            height: 1,
            child: WaveBackground(
              color1: AfColors.surfaceCanvas,
              color2: AfColors.surfaceCanvas,
              amplitude: 0.0,
              speed: 0.0,
            ),
          ),
          // Warm up BackdropFilter blur at the sigma values used by the app
          // (miniplayer: 24, top bar: 30, glass cards: 16).
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: const SizedBox(width: 1, height: 1),
            ),
          ),
        ],
      ),
    );
  }
}
