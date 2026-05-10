import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/demo/demo_library.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/track_row.dart';

class QueueScreen extends ConsumerStatefulWidget {
  const QueueScreen({super.key});

  @override
  ConsumerState<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends ConsumerState<QueueScreen> {
  late final List _items;

  @override
  void initState() {
    super.initState();
    final current = ref.read(currentTrackProvider);
    _items = current == null
        ? DemoLibrary.tracks.take(10).toList()
        : [current, ...DemoLibrary.tracks.where((t) => t.id != current.id).take(9)];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text('Queue', style: AfTypography.titleSmall),
        actions: [
          IconButton(
            icon: const Icon(Icons.shuffle_rounded),
            onPressed: () {},
            tooltip: 'Shuffle',
          ),
          IconButton(
            icon: const Icon(Icons.lyrics_outlined),
            onPressed: () => context.go('/lyrics'),
            tooltip: 'Lyrics',
          ),
        ],
      ),
      body: SafeArea(
        child: ReorderableListView.builder(
          padding: const EdgeInsets.symmetric(
              horizontal: AfSpacing.s16, vertical: AfSpacing.s8),
          itemCount: _items.length,
          buildDefaultDragHandles: false,
          onReorder: (oldIndex, newIndex) {
            setState(() {
              if (newIndex > oldIndex) newIndex -= 1;
              final item = _items.removeAt(oldIndex);
              _items.insert(newIndex, item);
            });
          },
          itemBuilder: (context, i) {
            final t = _items[i];
            final active = i == 0;
            return Padding(
              key: ValueKey(t.id),
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: TrackRow(
                      track: t,
                      density: TrackRowDensity.compact,
                      isActive: active,
                      showHeart: false,
                    ),
                  ),
                  ReorderableDragStartListener(
                    index: i,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: AfSpacing.s8),
                      child: Icon(Icons.drag_indicator_rounded,
                          color: AfColors.textTertiary),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
