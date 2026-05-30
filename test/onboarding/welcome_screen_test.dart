import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
          child: const MaterialApp(
            home: WelcomeScreen(),
          ),
        ),
      );

      // Verify basic rendering
      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.byType(SafeArea), findsOneWidget);
      expect(find.byType(Column), findsAtLeastNWidgets(1));
      expect(find.byType(Hero), findsOneWidget);
    });

    testWidgets('displays branding elements', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: WelcomeScreen(),
          ),
        ),
      );

      // Hero with logo mark
      expect(find.byType(Hero), findsOneWidget);
      // Mode cards with icons
      expect(find.byIcon(Icons.cloud_outlined), findsOneWidget);
      expect(find.byIcon(Icons.phone_android_rounded), findsOneWidget);
    });

    testWidgets('displays mode selection text', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: WelcomeScreen(),
          ),
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
          child: const MaterialApp(
            home: WelcomeScreen(),
          ),
        ),
      );

      expect(container.read(appModeProvider), isNull);
    });

    testWidgets('displays tagline', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: WelcomeScreen(),
          ),
        ),
      );

      expect(find.text('Music. Your way.'), findsOneWidget);
    });
  });
}
