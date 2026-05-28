import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/local/app_mode_store.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';

/// Onboarding screen for local mode: pick a folder, scan it, then proceed.
class LocalSetupScreen extends ConsumerStatefulWidget {
  const LocalSetupScreen({super.key});

  @override
  ConsumerState<LocalSetupScreen> createState() => _LocalSetupScreenState();
}

class _LocalSetupScreenState extends ConsumerState<LocalSetupScreen> {
  String? _folderUri;
  String? _folderDisplay;
  bool _scanning = false;
  int _scannedCount = 0;
  int _totalCount = 0;
  String? _error;

  Future<void> _pickFolder() async {
    setState(() => _error = null);
    final library = ref.read(localLibraryProvider);
    final uri = await library.pickAndAddFolder();
    if (uri == null) return;
    final folders = await ref.read(localLibraryProvider).getFolders();
    final folder = folders.lastOrNull;
    setState(() {
      _folderUri = uri;
      _folderDisplay = folder?.displayPath ?? uri;
    });
  }

  Future<void> _startScan() async {
    if (_folderUri == null) return;
    setState(() {
      _scanning = true;
      _scannedCount = 0;
      _totalCount = 0;
      _error = null;
    });

    try {
      final count = await ref
          .read(localLibraryProvider)
          .scanFolder(
            _folderUri!,
            onProgress: (completed, total) {
              if (mounted) {
                setState(() {
                  _scannedCount = completed;
                  _totalCount = total;
                });
                ref.read(localScanProgressProvider.notifier).state = (
                  completed: completed,
                  total: total,
                );
              }
            },
          );

      if (!mounted) return;
      ref.read(localScanProgressProvider.notifier).state = null;

      if (count == 0 && _totalCount == 0) {
        setState(() {
          _scanning = false;
          _error = 'No audio files found in this folder.';
        });
        return;
      }

      setState(() => _scanning = false);
      // Invalidate local providers so home/library screens pick up the data.
      ref.invalidate(localAlbumsProvider);
      ref.invalidate(localArtistsProvider);
      ref.invalidate(localTracksProvider);
      ref.invalidate(localGenresProvider);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('af.local_onboarding_completed', true);

      if (mounted) {
        ref.read(localOnboardingCompletedProvider.notifier).state = true;
        context.go('/home');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _scanning = false;
          _error = 'Scan failed: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AfColors.surfaceCanvas,
      appBar: AppBar(
        backgroundColor: AfColors.surfaceCanvas,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () async {
            // Reset mode on back — user wants to re-decide at the
            // WelcomeScreen. This also prevents stale redirects on
            // app restart after going back.
            await AppModeStore.clear();
            if (context.mounted) {
              ref.read(appModeProvider.notifier).state = null;
              // null triggers resetRouterMode() in main.dart's modeSub,
              // clearing the router's _appMode and _localOnboardingCompleted.
              context.pop();
            }
          },
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AfSpacing.s24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AfSpacing.s24),
              Text(
                'Select music folder',
                style: AfTypography.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AfSpacing.s8),
              Text(
                'Pick a folder containing your music files. '
                'Aetherfin will scan it for audio.',
                style: AfTypography.bodyMedium.copyWith(
                  color: AfColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AfSpacing.s32),

              // Folder selection
              Material(
                color: AfColors.surfaceBase,
                borderRadius: AfRadii.borderLg,
                child: InkWell(
                  onTap: _scanning ? null : _pickFolder,
                  borderRadius: AfRadii.borderLg,
                  child: Padding(
                    padding: const EdgeInsets.all(AfSpacing.s16),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AfColors.indigo500.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.folder_open_rounded,
                            color: AfColors.indigo400,
                          ),
                        ),
                        const SizedBox(width: AfSpacing.s12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _folderUri != null
                                    ? 'Folder selected'
                                    : 'Tap to choose a folder',
                                style: AfTypography.bodyMedium,
                              ),
                              if (_folderDisplay != null)
                                Text(
                                  _folderDisplay!,
                                  style: AfTypography.bodySmall.copyWith(
                                    color: AfColors.textTertiary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        if (_folderUri == null)
                          const Icon(
                            Icons.add_rounded,
                            color: AfColors.textTertiary,
                          ),
                        if (_folderUri != null)
                          const Icon(
                            Icons.check_circle_rounded,
                            color: AfColors.semanticSuccess,
                          ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: AfSpacing.s24),

              // Scan progress
              if (_scanning) ...[
                LinearProgressIndicator(
                  value: _totalCount > 0 ? _scannedCount / _totalCount : null,
                  backgroundColor: AfColors.surfaceHigh,
                  valueColor: const AlwaysStoppedAnimation(AfColors.indigo500),
                  borderRadius: BorderRadius.circular(2),
                ),
                const SizedBox(height: AfSpacing.s8),
                Text(
                  _totalCount > 0
                      ? 'Scanning... $_scannedCount / $_totalCount'
                      : 'Scanning...',
                  style: AfTypography.bodySmall.copyWith(
                    color: AfColors.textTertiary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],

              // Error
              if (_error != null) ...[
                const SizedBox(height: AfSpacing.s12),
                Text(
                  _error!,
                  style: AfTypography.bodySmall.copyWith(
                    color: AfColors.semanticError,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],

              const Spacer(),

              // Scan button
              FilledButton(
                onPressed: _folderUri != null && !_scanning ? _startScan : null,
                style: FilledButton.styleFrom(
                  backgroundColor: AfColors.indigo600,
                  disabledBackgroundColor: AfColors.surfaceHigh,
                  padding: const EdgeInsets.symmetric(vertical: AfSpacing.s16),
                  shape: const RoundedRectangleBorder(
                    borderRadius: AfRadii.borderMd,
                  ),
                ),
                child: Text(
                  _scanning ? 'Scanning...' : 'Scan & continue',
                  style: AfTypography.bodyMedium.copyWith(
                    color: _folderUri != null && !_scanning
                        ? AfColors.textOnPrimary
                        : AfColors.textDisabled,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: AfSpacing.s32),
            ],
          ),
        ),
      ),
    );
  }
}
