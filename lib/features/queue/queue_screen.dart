import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_shaders_ui/flutter_shaders_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../utils/display_error.dart';
import '../../widgets/af_dialog.dart';
import '../../widgets/track_context_menu.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/track_row.dart';

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

  /// Key for the currently playing item — used to scroll to it on open.
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
    final current = ref.watch(currentTrackProvider);
    final isBuffering = ref.watch(isBufferingProvider);

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
      _items = List<AfTrack>.from(liveQueue);
      _lastQueueIds = liveIds;
      _hasScrolledToActive = false; // re-scroll on queue change
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
        // Account for list top padding.
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
            onSelected: (action) async {
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
                  await _saveQueueAsPlaylist();
                  break;
              }
            },
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
          // Full-bleed background — GPU shader
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
                    child: ReorderableListView.builder(
                      scrollController: _scrollController,
                      padding: const EdgeInsets.only(
                        top: AfSpacing.s16,
                        bottom: AfSpacing.s8,
                        left: AfSpacing.s16,
                        right: AfSpacing.s16,
                      ),
                      itemCount: _items.length,
                      buildDefaultDragHandles: false,
                      onReorderItem: (oldIndex, newIndex) {
                        // Flutter's _handleReorderItem already adjusted
                        // newIndex (newIndex-- when newIndex > oldIndex),
                        // so newIndex is correct for the post-removal list.
                        // Engine.reorder does its OWN adjustment, so
                        // compensate by passing the pre-adjustment value.
                        setState(() {
                          final item = _items.removeAt(oldIndex);
                          _items.insert(newIndex, item);
                          _lastQueueIds = _items
                              .map((t) => t.id)
                              .toList(growable: false);
                        });
                        ref
                            .read(playerServiceProvider)
                            .reorderQueue(
                              oldIndex,
                              oldIndex < newIndex ? newIndex + 1 : newIndex,
                            );
                      },
                      itemBuilder: (context, i) {
                        final t = _items[i];
                        final active = current?.id == t.id;
                        // Dismissible handles horizontal swipe; the
                        // ReorderableDragStartListener handles vertical drag —
                        // they never compete because the gestures are on
                        // perpendicular axes.
                        return Dismissible(
                          key: ValueKey('q-${t.id}-$i'),
                          direction: active
                              ? DismissDirection.none
                              : DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.symmetric(
                              horizontal: AfSpacing.s24,
                            ),
                            color: AfColors.semanticError.withValues(
                              alpha: 0.25,
                            ),
                            child: const Icon(
                              LucideIcons.trash2,
                              color: AfColors.semanticError,
                            ),
                          ),
                          confirmDismiss: (_) async {
                            if (active) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Skip to remove the currently playing track.',
                                  ),
                                  duration: AfDurations.snackBarInfo,
                                ),
                              );
                              return false;
                            }
                            unawaited(HapticFeedback.lightImpact());
                            return true;
                          },
                          onDismissed: (_) {
                            final removed = t;
                            // Resolve the actual index from the player's
                            // current queue — the closure index `i` may be
                            // stale if the queue changed between build and
                            // dismiss (e.g. track advanced, reorder).
                            final svc = ref.read(playerServiceProvider);
                            final actualIndex = svc.currentQueue.indexWhere(
                              (q) => q.id == removed.id,
                            );
                            if (actualIndex < 0) return;

                            // Optimistic local update so the swipe animation
                            // completes without the row springing back.
                            setState(() {
                              _items.removeAt(i);
                              _lastQueueIds = _items
                                  .map((t) => t.id)
                                  .toList(growable: false);
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
                                    onPressed: () =>
                                        _undoRemove(actualIndex, removed),
                                  ),
                                ),
                              );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: AfSpacing.s4,
                            ),
                            child: Container(
                              decoration: active
                                  ? const BoxDecoration(
                                      color: AfColors.surfaceBase,
                                      borderRadius: AfRadii.borderMd,
                                    )
                                  : null,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TrackRow(
                                      track: t,
                                      density: TrackRowDensity.compact,
                                      isActive: active,
                                      isBuffering: active && isBuffering,
                                      showHeart: false,
                                      onTap: () {
                                        // Jump to and play the selected track
                                        final svc = ref.read(
                                          playerServiceProvider,
                                        );
                                        svc.skipToQueueItem(i);
                                        svc.play();
                                      },
                                      onLongPress: () =>
                                          showTrackContextMenu(context, ref, t),
                                    ),
                                  ),
                                  ReorderableDragStartListener(
                                    index: i,
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: AfSpacing.s8,
                                      ),
                                      child: Icon(
                                        LucideIcons.gripVertical,
                                        color: AfColors.textTertiary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
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

  /// Re-insert a track at [index] after a swipe-to-remove.
  ///
  /// Resolves the stream URL the same way [PlayActions.playQueue]
  /// does — backend.trackStreamUrl in server mode, the AfTrack.id
  /// itself (a content:// URI) in local mode. The player's
  /// `insertIntoQueue` keeps `_currentIndex` correct.
  void _undoRemove(int index, AfTrack track) {
    final mode = ref.read(appModeProvider);
    final backend = ref.read(musicBackendProvider);
    final cache = ref.read(offlineCacheServiceProvider);
    final cacheEnabled = ref.read(offlineCacheEnabledProvider);
    FutureOr<String> resolve(AfTrack t) async {
      if (mode == AppMode.local) return t.id;
      if (cacheEnabled) {
        final cachedUri = await cache.cachedFileUri(t.id);
        if (cachedUri != null) return cachedUri;
      }
      if (backend != null) {
        final maxBitrate = ref.read(maxBitrateProvider);
        return backend.trackStreamUrl(
          t.id,
          maxBitrateKbps: maxBitrate == 0 ? null : maxBitrate,
        );
      }
      return 'about:blank';
    }

    unawaited(
      ref
          .read(playerServiceProvider)
          .insertIntoQueue(index, track, resolveStreamUrl: resolve),
    );
  }

  /// Prompts for a name and creates a new playlist containing every
  /// track currently in the queue. The default name is "Queue ·
  /// YYYY-MM-DD HH:mm" so distinct saves never collide visually.
  ///
  /// Works in both local and server modes — both backends implement
  /// `MusicBackend.createPlaylist`. Returns silently when the queue
  /// is empty (the AppBar button is also disabled in that case).
  Future<void> _saveQueueAsPlaylist() async {
    if (_items.isEmpty) return;
    final backend = ref.read(musicBackendProvider);
    if (backend == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to save playlists')),
      );
      return;
    }

    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final defaultName =
        'Queue · ${now.year}-${two(now.month)}-${two(now.day)} '
        '${two(now.hour)}:${two(now.minute)}';
    final controller = TextEditingController(text: defaultName);
    final String? name;
    try {
      name = await showBlurDialog<String>(
        context: context,
        builder: (context, dismiss) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Save queue as playlist', style: AfTypography.titleMedium),
            const SizedBox(height: AfSpacing.s16),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Playlist name',
                border: OutlineInputBorder(
                  borderRadius: AfRadii.borderSm,
                  borderSide: BorderSide(color: AfColors.surfaceHigh),
                ),
              ),
              onSubmitted: (v) => dismiss(v.trim()),
            ),
            const SizedBox(height: AfSpacing.s24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => dismiss(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => dismiss(controller.text.trim()),
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }

    if (name == null || name.isEmpty || !mounted) return;

    final snapshot = List<String>.from(_items.map((t) => t.id));
    try {
      await backend.createPlaylist(name, snapshot);
      ref.invalidate(allPlaylistsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved as "$name" · ${snapshot.length} tracks')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(displayError(e, prefix: 'Failed to save queue')),
        ),
      );
    }
  }
}

enum QueueAction { shuffleAll, shuffleNext, saveAsPlaylist }
