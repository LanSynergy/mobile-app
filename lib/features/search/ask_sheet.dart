import 'package:flutter/material.dart';

import '../../design_tokens/tokens.dart';

/// "Ask your library" sheet — opens from the bottom of Search.
///
/// Per §9.1, the AI surface is calm: a single full-width text field, a
/// brief disclosure, and a results list that fades in as it streams.
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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    setState(() => _running = true);
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    return Padding(
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
                Text('Ask your library',
                    style: AfTypography.titleMedium),
              ],
            ),
            const SizedBox(height: AfSpacing.s8),
            Text(
              'Describe what you’re in the mood for. Aetherfin runs the '
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
              decoration: const InputDecoration(
                hintText:
                    'e.g. “quiet things to read by, recorded after 2020”',
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
    );
  }
}
