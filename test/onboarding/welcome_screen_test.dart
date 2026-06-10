import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:aetherfin/features/onboarding/welcome_screen.dart';
import 'package:aetherfin/state/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WelcomeScreen', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: WelcomeScreen()),
        ),
      );

      // Verify basic rendering
      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.byType(SafeArea), findsOneWidget);
      expect(find.byType(Column), findsAtLeastNWidgets(1));
    });

    testWidgets('displays branding elements', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: WelcomeScreen()),
        ),
      );

      // Mode cards with Lucide icons
      expect(find.byIcon(LucideIcons.cloud), findsOneWidget);
      expect(find.byIcon(LucideIcons.smartphone), findsOneWidget);
    });

    testWidgets('displays mode selection text', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: WelcomeScreen()),
        ),
      );

      expect(find.text('How do you listen?'), findsOneWidget);
      expect(find.text('Stream from server'), findsOneWidget);
      expect(find.text('Jellyfin or Navidrome'), findsOneWidget);
      expect(find.text('Play local files'), findsOneWidget);
      expect(find.text('Music on your device'), findsOneWidget);
    });

    testWidgets('initial app mode is null', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: WelcomeScreen()),
        ),
      );

      expect(container.read(appModeProvider), isNull);
    });

    testWidgets('displays tagline', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: WelcomeScreen()),
        ),
      );

      expect(find.text('Music. Your way.'), findsOneWidget);
    });
  });
}
