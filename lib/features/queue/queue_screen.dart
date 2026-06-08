import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_shaders_ui/flutter_shaders_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/empty_state.dart';
import 'queue_actions.dart';
import 'queue_list_view.dart';

/// Live queue mirror. Watches `playerQueueProvider` so the list reflects
/// the actual player state — reorder / skip / play-new-album shows up
/// the moment the player applies it.
class QueueScreen extends ConsumerStatefulWidget {
  const QueueScreen({super.key});

  @override
  ConsumerState<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends ConsumerState<QueueScreen> {
  List<AfTrack> _items = const [];
  List<String> _lastQueueIds = const [];

  final _scrollController = ScrollController();
  bool _hasScrolledToActive = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final queueAsync = ref.watch(playerQueueProvider);
    final current = ref.watch(currentTrackProvider.select((t) => t?.id));
    final isBuffering = ref.watch(isBufferingProvider);

    final liveQueue = queueAsync.maybeWhen(
      data: (q) => q,
      orElse: () => const <AfTrack>[],
    );

    final liveIds = liveQueue.map((t) => t.id).toList(growable: false);
    if (!_listsMatch(liveIds, _lastQueueIds)) {
      _items = List<AfTrack>.from(liveQueue);
      _lastQueueIds = liveIds;
      _hasScrolledToActive = false;
    }

    if (!_hasScrolledToActive && _items.isNotEmpty && current != null) {
      _hasScrolledToActive = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final activeIdx = _items.indexWhere((t) => t.id == current);
        if (activeIdx < 0) return;
        const itemExtent = 48.0;
        const topPadding = AfSpacing.s16;
        final targetOffset =
            topPadding +
            (activeIdx * itemExtent) -
            (_scrollController.position.viewportDimension * 0.3);
        _scrollController.animateTo(
          targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
          duration: AfDurations.standard,
          curve: AfCurves.easeOut,
        );
      });
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronDown),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text('Queue', style: AfTypography.titleSmall),
        actions: [
          PopupMenuButton<QueueAction>(
            icon: const Icon(
              LucideIcons.ellipsisVertical,
              color: AfColors.textPrimary,
            ),
            onSelected: _onMenuAction,
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: QueueAction.shuffleAll,
                child: ListTile(
                  leading: Icon(LucideIcons.shuffle, size: 20),
                  title: Text('Shuffle all'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: QueueAction.shuffleNext,
                child: ListTile(
                  leading: Icon(LucideIcons.arrowDownWideNarrow, size: 20),
                  title: Text('Shuffle next'),
                  subtitle: Text('Shuffle only upcoming tracks'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: QueueAction.saveAsPlaylist,
                enabled: _items.isNotEmpty,
                child: const ListTile(
                  leading: Icon(LucideIcons.listPlus, size: 20),
                  title: Text('Save as playlist'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          const Positioned.fill(
            child: WaveBackground(
              color1: AfColors.surfaceCanvas,
              color2: AfColors.surfaceLow,
              amplitude: 0.1,
              speed: 0.2,
            ),
          ),
          SafeArea(
            child: _items.isEmpty
                ? const Center(
                    child: EmptyState(
                      icon: LucideIcons.listMusic,
                      title: 'Queue is empty',
                      body: 'Pick an album or track to start playback',
                    ),
                  )
                : RepaintBoundary(
                    child: QueueListView(
                      items: _items,
                      currentId: current,
                      isBuffering: isBuffering,
                      scrollController: _scrollController,
                      onReorder: _onReorder,
                      onDismiss: _onDismiss,
                      onTap: _onItemTap,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _onMenuAction(QueueAction action) async {
    switch (action) {
      case QueueAction.shuffleAll:
        final svc = ref.read(playerServiceProvider);
        await svc.setAfShuffleMode(true);
        break;
      case QueueAction.shuffleNext:
        final svc = ref.read(playerServiceProvider);
        await svc.setAfShuffleTail();
        break;
      case QueueAction.saveAsPlaylist:
        await saveQueueAsPlaylist(context, ref, _items);
        break;
    }
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      final item = _items.removeAt(oldIndex);
      _items.insert(newIndex, item);
      _lastQueueIds = _items.map((t) => t.id).toList(growable: false);
    });
    ref
        .read(playerServiceProvider)
        .reorderQueue(oldIndex, oldIndex < newIndex ? newIndex + 1 : newIndex);
  }

  void _onDismiss(int i, AfTrack t) {
    final removed = t;
    final svc = ref.read(playerServiceProvider);
    final actualIndex = svc.currentQueue.indexWhere((q) => q.id == removed.id);
    if (actualIndex < 0) return;

    setState(() {
      _items.removeAt(i);
      _lastQueueIds = _items.map((t) => t.id).toList(growable: false);
    });
    unawaited(svc.removeFromQueue(actualIndex));
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text('Removed "${removed.title}"'),
          duration: AfDurations.snackBarError,
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => _undoRemove(actualIndex, removed),
          ),
        ),
      );
  }

  void _onItemTap(int index) {
    final svc = ref.read(playerServiceProvider);
    svc.skipToQueueItem(index);
    svc.play();
  }

  static bool _listsMatch(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _undoRemove(int index, AfTrack track) {
    final mode = ref.read(appModeProvider) ?? AppMode.server;
    final backend = ref.read(musicBackendProvider);
    unawaited(
      ref
          .read(playerServiceProvider)
          .insertIntoQueue(
            index,
            track,
            resolveStreamUrl: (t) => resolveTrackStreamUrl(
              t,
              mode: mode,
              backend: backend,
              ref: ref,
            ),
          ),
    );
  }
}

enum QueueAction { shuffleAll, shuffleNext, saveAsPlaylist }
