import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../design_tokens/tokens.dart';
import '../../utils/log.dart';

/// Mockup 01 — Welcome.
///
///   Centered brand mark (56dp) over a soft indigo gradient.
///   Wordmark below the mark.
///   Tagline "Music. Your way."
///   Primary CTA "Get started" → Server discovery.
///   Secondary "Skip — try demo" → Home (uses bundled demo library).
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    afLog('boot', 'WelcomeScreen.build');
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.4),
            radius: 1.2,
            colors: [AfColors.indigo800, AfColors.surfaceCanvas],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AfSpacing.gutterGenerous,
              vertical: AfSpacing.s32,
            ),
            child: Column(
              children: [
                const Spacer(),
                Hero(
                  tag: 'aetherfin-mark',
                  child: SvgPicture.asset(
                    'assets/brand/logo-mark.svg',
                    width: 56,
                    height: 56,
                    colorFilter: const ColorFilter.mode(
                      AfColors.textOnPrimary,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
                const SizedBox(height: AfSpacing.s24),
                SvgPicture.asset(
                  'assets/brand/wordmark.svg',
                  width: 180,
                  colorFilter: const ColorFilter.mode(
                    AfColors.textOnPrimary,
                    BlendMode.srcIn,
                  ),
                ),
                const SizedBox(height: AfSpacing.s16),
                Text(
                  'Music. Your way.',
                  textAlign: TextAlign.center,
                  style: AfTypography.bodyLarge.copyWith(
                    color: AfColors.textSecondary,
                  ),
                ),
                const Spacer(),
                _PrimaryCta(
                  label: 'Get started',
                  onTap: () => context.go('/onboarding/discover'),
                ),
                const SizedBox(height: AfSpacing.s12),
                TextButton(
                  onPressed: () => context.go('/home'),
                  child: const Text('Skip — try with demo library'),
                ),
                const SizedBox(height: AfSpacing.s24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PrimaryCta extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PrimaryCta({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        child: Text(label),
      ),
    );
  }
}
