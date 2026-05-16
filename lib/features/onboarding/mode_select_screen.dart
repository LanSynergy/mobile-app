import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/local/app_mode_store.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';

/// Onboarding screen where the user picks between Server mode and Local mode.
class ModeSelectScreen extends ConsumerWidget {
  const ModeSelectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AfColors.surfaceCanvas,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),
              Text(
                'How do you listen?',
                style: AfTypography.display,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AfSpacing.s12),
              Text(
                'Choose how Aetherfin accesses your music.',
                style: AfTypography.bodyMedium.copyWith(
                  color: AfColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              _ModeCard(
                icon: Icons.dns_outlined,
                iconColor: AfColors.indigo400,
                title: 'Connect to server',
                subtitle: 'Stream from Jellyfin or Navidrome',
                onTap: () async {
                  ref.read(appModeProvider.notifier).state = AppMode.server;
                  await AppModeStore.save(AppMode.server);
                  if (context.mounted) context.go('/onboarding/discover');
                },
              ),
              const SizedBox(height: AfSpacing.s16),
              _ModeCard(
                icon: Icons.folder_outlined,
                iconColor: AfColors.semanticSuccess,
                title: 'Play local files',
                subtitle: 'Pick a folder on your device',
                onTap: () async {
                  ref.read(appModeProvider.notifier).state = AppMode.local;
                  await AppModeStore.save(AppMode.local);
                  if (context.mounted) context.go('/onboarding/local-setup');
                },
              ),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AfColors.surfaceBase,
      borderRadius: AfRadii.borderLg,
      child: InkWell(
        onTap: onTap,
        borderRadius: AfRadii.borderLg,
        child: Padding(
          padding: const EdgeInsets.all(AfSpacing.s24),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 24),
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
              const Icon(Icons.chevron_right_rounded,
                  color: AfColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}
