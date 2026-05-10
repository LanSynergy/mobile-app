import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design_tokens/tokens.dart';

/// Mockup 13 — Sleep timer.
class SleepTimerScreen extends ConsumerStatefulWidget {
  const SleepTimerScreen({super.key});

  @override
  ConsumerState<SleepTimerScreen> createState() =>
      _SleepTimerScreenState();
}

class _SleepTimerScreenState extends ConsumerState<SleepTimerScreen> {
  int? _selectedMinutes;

  static const _presets = [5, 10, 15, 30, 45, 60];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text('Sleep timer', style: AfTypography.titleMedium),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AfSpacing.gutterGenerous),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AfSpacing.s8),
              Text(
                'Pause playback after a quiet interval.',
                style: AfTypography.bodyMedium.copyWith(
                  color: AfColors.textSecondary,
                ),
              ),
              const SizedBox(height: AfSpacing.s24),
              Wrap(
                spacing: AfSpacing.s12,
                runSpacing: AfSpacing.s12,
                children: [
                  for (final m in _presets)
                    ChoiceChip(
                      label: Text('$m min'),
                      selected: _selectedMinutes == m,
                      onSelected: (_) =>
                          setState(() => _selectedMinutes = m),
                      selectedColor: AfColors.indigo600,
                      backgroundColor: AfColors.surfaceBase,
                      labelStyle: AfTypography.bodyMedium.copyWith(
                        color: _selectedMinutes == m
                            ? AfColors.textOnPrimary
                            : AfColors.textPrimary,
                      ),
                    ),
                  ChoiceChip(
                    label: const Text('End of track'),
                    selected: _selectedMinutes == 0,
                    onSelected: (_) =>
                        setState(() => _selectedMinutes = 0),
                    selectedColor: AfColors.indigo600,
                    backgroundColor: AfColors.surfaceBase,
                    labelStyle: AfTypography.bodyMedium.copyWith(
                      color: _selectedMinutes == 0
                          ? AfColors.textOnPrimary
                          : AfColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: _selectedMinutes == null
                    ? null
                    : () => Navigator.maybePop(context),
                child: Text(
                  _selectedMinutes == null
                      ? 'Pick a time'
                      : 'Set timer',
                ),
              ),
              const SizedBox(height: AfSpacing.s24),
            ],
          ),
        ),
      ),
    );
  }
}
