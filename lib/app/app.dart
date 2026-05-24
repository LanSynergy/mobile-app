import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import '../utils/log.dart';
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

    final accent = ref.watch(pastelAccentColorProvider);
    final theme = buildNocturneThemeFromAccent(accent);

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
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
