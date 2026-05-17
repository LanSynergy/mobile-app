import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/track_row.dart';

/// Sort options for the queue.
enum QueueSortOption {
  defaultOrder('Default'),
  titleAsc('A-Z'),
  titleDesc('Z-A'),
  artistAsc('Artist A-Z'),
  artistDesc('Artist Z-A'),
  albumAsc('Album A-Z'),
  albumDesc('Album Z-A');

  final String label;
  const QueueSortOption(this.label);
}

/// Live queue mirror. Watches `playerQueueProvider` (a broadcast stream
/// on top of `AfPlayerService.queueStream`) so the list reflects the
/// actual player state — reorder / skip / play-new-album shows up the
/// moment the player applies it, without snapshotting `DemoLibrary`.
class QueueScreen extends ConsumerStatefulWidget {
  const QueueScreen({super.key});

  @override
  ConsumerState<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends ConsumerState<QueueScreen> {
  /// Local mutable mirror of the player queue — needed because
  /// `ReorderableListView` requires synchronous list mutation in its
  /// `onReorder` callback. Refreshed whenever the player emits a new
  /// queue snapshot.
  List<AfTrack> _items = const [];
  List<String> _lastQueueIds = const [];

  /// Current sort option for the queue display.
  QueueSortOption _sortOption = QueueSortOption.defaultOrder;

  /// Key for the currently playing item — used to scroll to it on open.
  final _scrollController = ScrollController();
  bool _hasScrolledToActive = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Original queue order before sorting - needed to restore "Default" sort.
  List<AfTrack> _originalItems = const [];

  /// Apply the current sort option to _items.
  void _applySort() {
    if (_sortOption == QueueSortOption.defaultOrder) {
      // Restore original order
      _items = List<AfTrack>.from(_originalItems);
      return;
    }

    final sorted = List<AfTrack>.from(_items);
    switch (_sortOption) {
      case QueueSortOption.titleAsc:
        sorted.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case QueueSortOption.titleDesc:
        sorted.sort((a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()));
        break;
      case QueueSortOption.artistAsc:
        sorted.sort((a, b) => a.artistName.toLowerCase().compareTo(b.artistName.toLowerCase()));
        break;
      case QueueSortOption.artistDesc:
        sorted.sort((a, b) => b.artistName.toLowerCase().compareTo(a.artistName.toLowerCase()));
        break;
      case QueueSortOption.albumAsc:
        sorted.sort((a, b) => a.albumName.toLowerCase().compareTo(b.albumName.toLowerCase()));
        break;
      case QueueSortOption.albumDesc:
        sorted.sort((a, b) => b.albumName.toLowerCase().compareTo(a.albumName.toLowerCase()));
        break;
      default:
        break;
    }
    _items = sorted;
  }

  /// Handle reorder callback - only works when not sorted.
  void _onReorder(int oldIndex, int newIndex) {
    if (_sortOption != QueueSortOption.defaultOrder) return;
    // Apply the standard ReorderableListView adjustment
    // before touching either the local mirror or the player.
    if (newIndex > oldIndex) newIndex -= 1;
    setState(() {
      final item = _items.removeAt(oldIndex);
      _items.insert(newIndex, item);
    });
    // Update original items to match
    _originalItems = List<AfTrack>.from(_items);
    // Sync the player's ConcatenatingAudioSource so
    // skip-next/prev honour the new order. The adjusted
    // indices are passed directly — reorderQueue expects
    // the post-adjustment values.
    ref.read(playerServiceProvider).reorderQueue(oldIndex, newIndex);
  }

  @override
  Widget build(BuildContext context) {
    final queueAsync = ref.watch(playerQueueProvider);
    final current = ref.watch(currentTrackProvider);

    final liveQueue = queueAsync.maybeWhen(
      data: (q) => q,
      orElse: () => const <AfTrack>[],
    );

    // Sync our mutable mirror whenever the player's queue identity
    // changes (compared as ID sequence so a reorder we just performed
    // doesn't get clobbered the moment the stream re-emits the new
    // order back at us).
    final liveIds = liveQueue.map((t) => t.id).toList(growable: false);
    if (!_listsMatch(liveIds, _lastQueueIds)) {
      _originalItems = List<AfTrack>.from(liveQueue);
      _items = List<AfTrack>.from(liveQueue);
      _lastQueueIds = liveIds;
      _hasScrolledToActive = false; // re-scroll on queue change
      // Re-apply sort if not default
      if (_sortOption != QueueSortOption.defaultOrder) {
        _applySort();
      }
    }

    // Scroll to the active track after the first frame.
    if (!_hasScrolledToActive && _items.isNotEmpty && current != null) {
      _hasScrolledToActive = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final activeIdx = _items.indexWhere((t) => t.id == current.id);
        if (activeIdx < 0) return;
        // Each item is ~48dp (compact row 44dp + 4dp vertical padding).
        const itemExtent = 48.0;
        final targetOffset = (activeIdx * itemExtent) -
            (_scrollController.position.viewportDimension * 0.3);
        _scrollController.animateTo(
          targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text('Queue', style: AfTypography.titleSmall),
        actions: [
          Consumer(builder: (context, ref, _) {
            final shuffleOn = ref.watch(shuffleModeProvider).maybeWhen(
                  data: (v) => v,
                  orElse: () => false,
                );
            return IconButton(
              icon: Icon(
                Icons.shuffle_rounded,
                color: shuffleOn
                    ? AfColors.indigo300
                    : AfColors.textPrimary,
              ),
              tooltip: shuffleOn ? 'Shuffle on' : 'Shuffle',
              onPressed: () {
                final svc = ref.read(playerServiceProvider);
                svc.setAfShuffleMode(!svc.isShuffleEnabled);
              },
            );
          }),
          IconButton(
            icon: const Icon(Icons.lyrics_outlined),
            onPressed: () => context.push('/lyrics'),
            tooltip: 'Lyrics',
          ),
          PopupMenuButton<QueueSortOption>(
            icon: const Icon(Icons.sort_rounded),
            tooltip: 'Sort queue',
            initialValue: _sortOption,
            onSelected: (option) {
              setState(() {
                _sortOption = option;
                _applySort();
              });
            },
            itemBuilder: (context) => QueueSortOption.values
                .map((option) => PopupMenuItem<QueueSortOption>(
                      value: option,
                      child: Row(
                        children: [
                          if (_sortOption == option)
                            const Icon(Icons.check, size: 18, color: AfColors.indigo400)
                          else
                            const SizedBox(width: 18),
                          const SizedBox(width: 8),
                          Text(option.label, style: AfTypography.bodyMedium),
                        ],
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
      body: SafeArea(
        child: _items.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AfSpacing.gutterGenerous,
                  ),
                  child: Text(
                    'Queue is empty. Pick an album or track to start playback.',
                    style: AfTypography.bodyMedium.copyWith(
                      color: AfColors.textTertiary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ReorderableListView.builder(
                scrollController: _scrollController,
                padding: const EdgeInsets.symmetric(
                    horizontal: AfSpacing.s16, vertical: AfSpacing.s8),
                itemCount: _items.length,
                buildDefaultDragHandles: _sortOption == QueueSortOption.defaultOrder,
                onReorder: _onReorder,
                itemBuilder: (context, i) {
                  final t = _items[i];
                  final active = current?.id == t.id;
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
                            onTap: () {
                              // Jump to and play the selected track
                              final svc = ref.read(playerServiceProvider);
                              svc.skipToQueueItem(i);
                              svc.play();
                            },
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

  static bool _listsMatch(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
