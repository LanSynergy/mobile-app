import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final showLabels = ref.watch(showNavLabelsProvider);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: Text('Settings', style: AfTypography.titleMedium),
      ),
      body: SafeArea(
        child: ListView(
          padding:
              const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
          children: [
            _SectionLabel('Server'),
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: Text(auth?.server.name ?? 'Not connected'),
              subtitle: auth == null
                  ? null
                  : Text(
                      auth.server.baseUrl,
                      style: AfTypography.bodySmall.copyWith(
                        color: AfColors.textTertiary,
                      ),
                    ),
              trailing: const Icon(Icons.chevron_right_rounded),
              tileColor: AfColors.surfaceBase,
              shape: const RoundedRectangleBorder(
                  borderRadius: AfRadii.borderMd),
              onTap: () => context.go('/onboarding/discover'),
            ),
            const SizedBox(height: AfSpacing.s24),
            _SectionLabel('Appearance'),
            SwitchListTile.adaptive(
              value: showLabels,
              onChanged: (v) =>
                  ref.read(showNavLabelsProvider.notifier).state = v,
              title: const Text('Always show tab labels'),
              subtitle: Text(
                'Default is icon-only with the active capsule indicator.',
                style: AfTypography.bodySmall.copyWith(
                  color: AfColors.textTertiary,
                ),
              ),
              activeColor: AfColors.indigo500,
              tileColor: AfColors.surfaceBase,
              shape: const RoundedRectangleBorder(
                  borderRadius: AfRadii.borderMd),
            ),
            const SizedBox(height: AfSpacing.s24),
            _SectionLabel('About'),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('Aetherfin v0.1.0'),
              subtitle: Text(
                'Jellyfin-backed music player. FOSS.',
                style: AfTypography.bodySmall.copyWith(
                  color: AfColors.textTertiary,
                ),
              ),
              tileColor: AfColors.surfaceBase,
              shape: const RoundedRectangleBorder(
                  borderRadius: AfRadii.borderMd),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AfSpacing.s4, AfSpacing.s8, AfSpacing.s4, AfSpacing.s8),
      child: Text(
        label.toUpperCase(),
        style: AfTypography.label.copyWith(
          color: AfColors.textTertiary,
        ),
      ),
    );
  }
}
