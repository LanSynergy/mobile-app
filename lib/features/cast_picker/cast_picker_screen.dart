import 'package:flutter/material.dart';

import '../../design_tokens/tokens.dart';

/// Mockup 14 — Output picker (top sheet slides down from the top app bar).
class CastPickerScreen extends StatelessWidget {
  const CastPickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final outputs = const [
      ('This phone',  'Active',     Icons.smartphone_rounded, true),
      ('AirPods Pro', 'Connected',  Icons.headphones_rounded, false),
      ('Living Room', 'Cast',       Icons.speaker_group_rounded, false),
      ('Kitchen',     'Cast',       Icons.speaker_rounded, false),
    ];
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text('Output', style: AfTypography.titleMedium),
      ),
      body: SafeArea(
        child: ListView.separated(
          padding:
              const EdgeInsets.symmetric(horizontal: AfSpacing.s16),
          itemCount: outputs.length,
          separatorBuilder: (context, index) =>
              const SizedBox(height: AfSpacing.s8),
          itemBuilder: (context, i) {
            final (name, status, icon, active) = outputs[i];
            return ListTile(
              leading: Icon(icon,
                  color: active
                      ? AfColors.indigo300
                      : AfColors.textSecondary),
              title: Text(name, style: AfTypography.titleSmall),
              subtitle: Text(
                status,
                style: AfTypography.bodySmall.copyWith(
                  color: AfColors.textTertiary,
                ),
              ),
              trailing: active
                  ? const Icon(Icons.check_rounded,
                      color: AfColors.indigo300)
                  : null,
              tileColor: AfColors.surfaceBase,
              shape: const RoundedRectangleBorder(
                  borderRadius: AfRadii.borderMd),
              onTap: () => Navigator.maybePop(context),
            );
          },
        ),
      ),
    );
  }
}
