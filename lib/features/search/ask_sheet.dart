import 'package:flutter/material.dart';

import '../../design_tokens/tokens.dart';

/// "Ask your library" sheet — opens from the bottom of Search.
///
/// Per §9.1, the AI surface is calm: a single full-width text field, a
/// brief disclosure, and a results list that fades in as it streams.
///
/// Current implementation is a placeholder (mock delay). The architecture
/// is designed to accept a real LLM/semantic backend:
///   • _running guard prevents duplicate concurrent requests (finding 5)
///   • Input is trimmed + length-limited before submission (finding 6)
///   • Sheet is keyboard-aware with scroll container (finding 14)
class AskSheet extends StatefulWidget {
  const AskSheet({super.key});

  static Future<void> show(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AfColors.surfaceHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: AfRadii.rXl,
          topRight: AfRadii.rXl,
        ),
      ),
      builder: (_) => const AskSheet(),
    );
  }

  @override
  State<AskSheet> createState() => _AskSheetState();
}

class _AskSheetState extends State<AskSheet> {
  final _controller = TextEditingController();
  bool _running = false;

  /// Maximum characters accepted in the query field.
  /// Prevents memory pressure and future LLM token-cost abuse.
  static const _maxQueryLength = 300;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    // Guard against duplicate concurrent requests (double-tap, etc.).
    if (_running) return;

    final query = _controller.text.trim();
    // Validate: non-empty after trim.
    if (query.isEmpty) return;

    setState(() => _running = true);
    try {
      // TODO: replace with real semantic/LLM search call.
      // Architecture notes for future integration:
      //   • Pass query (already trimmed, length-limited) to backend.
      //   • Use CancelableOperation or a generation counter to discard
      //     stale results if the user submits again before this resolves.
      //   • Add rate limiting / token budgeting at the call site.
      //   • Surface errors via setState(_error = ...) not silent swallow.
      await Future.delayed(const Duration(milliseconds: 1200));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    // SingleChildScrollView + constrained max height handles:
    //   • keyboard push-up (viewInsets.bottom padding)
    //   • landscape phones / split-screen (maxHeight constraint)
    //   • accessibility text scaling (scroll instead of clip)
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: viewInsets.bottom),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AfSpacing.gutterGenerous,
            AfSpacing.s16,
            AfSpacing.gutterGenerous,
            AfSpacing.s24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome_rounded,
                      color: AfColors.indigo300),
                  const SizedBox(width: AfSpacing.s8),
                  Text('Ask your library', style: AfTypography.titleMedium),
                ],
              ),
              const SizedBox(height: AfSpacing.s8),
              Text(
                'Describe what you\'re in the mood for. Aetherfin runs the '
                'query against your library only.',
                style: AfTypography.bodySmall
                    .copyWith(color: AfColors.textSecondary),
              ),
              const SizedBox(height: AfSpacing.s16),
              TextField(
                controller: _controller,
                autofocus: true,
                minLines: 1,
                maxLines: 3,
                maxLength: _maxQueryLength,
                textInputAction: TextInputAction.send,
                decoration: const InputDecoration(
                  hintText:
                      'e.g. "quiet things to read by, recorded after 2020"',
                  counterText: '', // hide the built-in counter
                ),
                onSubmitted: (_) => _ask(),
              ),
              const SizedBox(height: AfSpacing.s16),
              if (_running)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AfSpacing.s24),
                  child: Center(
                    child: SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  ),
                )
              else
                ElevatedButton(
                  onPressed: _ask,
                  child: const Text('Ask'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
