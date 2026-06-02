import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/local/app_mode_store.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../utils/log.dart';

/// Landing screen: server vs local mode selection.
///
/// Large serif "Aetherfin" title, tagline, two floating mode cards with
/// surfaceRaised background and accent border on hover.
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
          // Background gradient — deep black to surfaceCanvas
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF111111), // surfaceLow
                  Color(0xFF101010),
                  Color(0xFF0F0F0F),
                  Color(0xFF0E0E0E),
                  Color(0xFF0D0D0D),
                  Color(0xFF0C0C0C),
                  Color(0xFF0B0B0B),
                  Color(0xFF0A0A0A), // surfaceCanvas
                  Color(0xFF0A0A0A), // surfaceCanvas — flat after 30%
                ],
                stops: [0.0, 0.04, 0.09, 0.13, 0.17, 0.22, 0.26, 0.3, 1.0],
              ),
            ),
          ),

          // Radial glow behind logo — warm amber tint
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
                    AfColors.accentPrimary.withValues(alpha: 0.12),
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
                      borderRadius: AfRadii.borderRounded,
                      border: Border.all(
                        color: AfColors.accentPrimary.withValues(alpha: 0.3),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AfColors.accentPrimary.withValues(alpha: 0.15),
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

                // Serif "Aetherfin" title
                Text(
                  'Aetherfin',
                  style: AfTypography.display.copyWith(
                    color: AfColors.textPrimary,
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
                        icon: LucideIcons.cloud,
                        title: 'Stream from server',
                        subtitle: 'Jellyfin or Navidrome',
                        onTap: () async {
                          ref.read(appModeProvider.notifier).state =
                              AppMode.server;
                          await AppModeStore.save(AppMode.server);
                          if (context.mounted) {
                            await context.push('/onboarding/discover');
                          }
                        },
                      ),
                      const SizedBox(height: AfSpacing.s12),
                      _ModeCard(
                        icon: LucideIcons.folderOpen,
                        title: 'Play local files',
                        subtitle: 'Music on your device',
                        onTap: () async {
                          ref.read(appModeProvider.notifier).state =
                              AppMode.local;
                          await AppModeStore.save(AppMode.local);
                          if (context.mounted) {
                            await context.push('/onboarding/local-setup');
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

class _ModeCard extends StatefulWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  State<_ModeCard> createState() => _ModeCardState();
}

class _ModeCardState extends State<_ModeCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AfDurations.quick,
          curve: AfCurves.easeStandard,
          padding: const EdgeInsets.all(AfSpacing.s16),
          decoration: BoxDecoration(
            color: AfColors.surfaceRaised,
            borderRadius: AfRadii.borderLg,
            border: Border.all(
              color: _hovered ? AfColors.accentPrimary : AfColors.surfaceHigh,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AfColors.accentPrimary.withValues(alpha: 0.15),
                  borderRadius: AfRadii.borderMd,
                ),
                child: Icon(
                  widget.icon,
                  color: AfColors.accentPrimary,
                  size: 24,
                ),
              ),
              const SizedBox(width: AfSpacing.s16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title, style: AfTypography.titleSmall),
                    const SizedBox(height: AfSpacing.s2),
                    Text(
                      widget.subtitle,
                      style: AfTypography.bodySmall.copyWith(
                        color: AfColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                LucideIcons.chevronRight,
                color: _hovered
                    ? AfColors.accentPrimary
                    : AfColors.textTertiary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
