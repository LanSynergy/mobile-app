import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'theme.dart';

class AetherfinApp extends ConsumerWidget {
  const AetherfinApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ignore: avoid_print
    print('aetherfin:boot AetherfinApp.build');
    // Edge-to-edge canvas: the app draws under the status/nav bars.
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );

    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Aetherfin',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: buildNocturneTheme(),
      // Dark-only at v1 (per non-negotiable §4.1).
      theme: buildNocturneTheme(),
      routerConfig: router,
      builder: (context, child) {
        // Clamp text scaling to 0.85–1.30 so layouts don't break, while
        // still honoring user accessibility preferences (spec §11.8).
        final mq = MediaQuery.of(context);
        final clamped = mq.textScaler.clamp(
          minScaleFactor: 0.85,
          maxScaleFactor: 1.3,
        );
        return MediaQuery(
          data: mq.copyWith(textScaler: clamped),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
