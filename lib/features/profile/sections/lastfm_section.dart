import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../design_tokens/tokens.dart';
import '../../../state/providers.dart';

/// Call-to-action card prompting the user to connect to Last.fm.
class LastFmConnectionCTA extends ConsumerWidget {
  const LastFmConnectionCTA({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spectral = ref.watch(currentSpectralProvider.select((s) => s.muted));
    return Container(
      margin: const EdgeInsets.only(bottom: AfSpacing.s16),
      padding: const EdgeInsets.all(AfSpacing.s16),
      decoration: BoxDecoration(
        borderRadius: AfRadii.borderMd,
        gradient: LinearGradient(
          colors: [spectral, AfColors.semanticError],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                LucideIcons.radio,
                color: AfColors.textOnPrimary,
                size: 20,
              ),
              const SizedBox(width: AfSpacing.s8),
              Text(
                'Connect to Last.fm',
                style: AfTypography.titleSmall.copyWith(
                  color: AfColors.textOnPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AfSpacing.s8),
          Text(
            'Sync your listening habits globally, unlock detailed statistics, and get smart recommendations.',
            style: AfTypography.bodySmall.copyWith(
              color: AfColors.textOnPrimary.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: AfSpacing.s12),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: spectral,
              padding: const EdgeInsets.symmetric(
                horizontal: AfSpacing.s16,
                vertical: AfSpacing.s8,
              ),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => context.push('/settings'),
            child: const Text('Connect now'),
          ),
        ],
      ),
    );
  }
}
