import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../core/local/app_mode_store.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../utils/log.dart';

/// Full-bleed welcome screen with gradient background and floating mode cards.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    afLog('boot', 'WelcomeScreen.build');
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AfColors.indigo900,
                  AfColors.indigo950,
                  AfColors.surfaceCanvas,
                  AfColors.surfaceCanvas,
                ],
                stops: [0.0, 0.3, 0.55, 1.0],
              ),
            ),
          ),

          // Radial glow behind logo
          Positioned(
            top: -80,
            left: 0,
            right: 0,
            height: 400,
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.8,
                  colors: [
                    AfColors.indigo600.withValues(alpha: 0.3),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Content
          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 2),

                // Logo + branding
                Hero(
                  tag: 'aetherfin-mark',
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AfColors.surfaceBase.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AfColors.indigo400.withValues(alpha: 0.3),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AfColors.indigo500.withValues(alpha: 0.3),
                          blurRadius: 40,
                          spreadRadius: 8,
                        ),
                      ],
                    ),
                    child: Center(
                      child: SvgPicture.asset(
                        'assets/brand/logo-mark.svg',
                        width: 40,
                        height: 40,
                        colorFilter: const ColorFilter.mode(
                          AfColors.textOnPrimary,
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AfSpacing.s24),
                SvgPicture.asset(
                  'assets/brand/wordmark.svg',
                  width: 160,
                  colorFilter: const ColorFilter.mode(
                    AfColors.textOnPrimary,
                    BlendMode.srcIn,
                  ),
                ),
                const SizedBox(height: AfSpacing.s12),
                Text(
                  'Music. Your way.',
                  style: AfTypography.bodyLarge.copyWith(
                    color: AfColors.textSecondary,
                  ),
                ),

                const Spacer(flex: 3),

                // Floating mode cards
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AfSpacing.s24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'How do you listen?',
                        style: AfTypography.titleSmall.copyWith(
                          color: AfColors.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AfSpacing.s16),
                      _ModeCard(
                        icon: Icons.cloud_outlined,
                        iconGradient: const [
                          AfColors.indigo400,
                          AfColors.indigo600,
                        ],
                        title: 'Stream from server',
                        subtitle: 'Jellyfin or Navidrome',
                        onTap: () async {
                          ref.read(appModeProvider.notifier).state =
                              AppMode.server;
                          await AppModeStore.save(AppMode.server);
                          if (context.mounted) {
                            context.go('/onboarding/discover');
                          }
                        },
                      ),
                      const SizedBox(height: AfSpacing.s12),
                      _ModeCard(
                        icon: Icons.phone_android_rounded,
                        iconGradient: const [
                          AfColors.semanticSuccess,
                          Color(0xFF2D9B5E),
                        ],
                        title: 'Play local files',
                        subtitle: 'Music on your device',
                        onTap: () async {
                          ref.read(appModeProvider.notifier).state =
                              AppMode.local;
                          await AppModeStore.save(AppMode.local);
                          if (context.mounted) {
                            context.go('/onboarding/local-setup');
                          }
                        },
                      ),
                    ],
                  ),
                ),
                SizedBox(height: bottomPadding + AfSpacing.s32),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final List<Color> iconGradient;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.iconGradient,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AfColors.surfaceBase,
      borderRadius: AfRadii.borderLg,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AfSpacing.s16),
          decoration: BoxDecoration(
            border: Border.all(
              color: AfColors.surfaceHigh,
              width: 1,
            ),
            borderRadius: AfRadii.borderLg,
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: iconGradient,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: AfSpacing.s16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AfTypography.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AfTypography.bodySmall.copyWith(
                        color: AfColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_rounded,
                color: AfColors.textTertiary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
