import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../design_tokens/tokens.dart';
import '../../utils/log.dart';

/// Welcome screen — first screen on fresh install.
/// "Get started" navigates to mode selection (server vs local).
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
                  onTap: () => context.go('/onboarding/mode'),
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
