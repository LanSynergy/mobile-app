import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/jellyfin/models/items.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../utils/display_error.dart';
import '../../widgets/af_dialog.dart';
import '../../widgets/track_context_menu.dart';
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
            icon: const Icon(Icons.playlist_add_rounded),
            onPressed: _items.isEmpty ? null : _saveQueueAsPlaylist,
            tooltip: 'Save queue as playlist',
          ),
          IconButton(
            icon: const Icon(Icons.lyrics_outlined),
            onPressed: () => context.push('/lyrics'),
            tooltip: 'Lyrics',
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
                buildDefaultDragHandles: false,
                onReorder: (oldIndex, newIndex) {
                  // Apply the standard ReorderableListView adjustment
                  // before touching either the local mirror or the player.
                  if (newIndex > oldIndex) newIndex -= 1;
                  setState(() {
                    final item = _items.removeAt(oldIndex);
                    _items.insert(newIndex, item);
                    // Keep `_lastQueueIds` in lockstep with the local
                    // mirror so the player's echoed queue (same order,
                    // arrives ~one frame later) doesn't trip the
                    // "identity changed" branch above — which would
                    // overwrite `_items` and re-fire the scroll-to-
                    // active animation, yanking the viewport away from
                    // whatever the user just dropped.
                    _lastQueueIds = _items
                        .map((t) => t.id)
                        .toList(growable: false);
                  });
                  // Sync the player's ConcatenatingAudioSource so
                  // skip-next/prev honour the new order. The adjusted
                  // indices are passed directly — reorderQueue expects
                  // the post-adjustment values.
                  ref
                      .read(playerServiceProvider)
                      .reorderQueue(oldIndex, newIndex);
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
                          horizontal: AfSpacing.s24),
                      color: AfColors.semanticError.withValues(alpha: 0.18),
                      child: const Icon(
                        Icons.delete_outline_rounded,
                        color: AfColors.semanticError,
                      ),
                    ),
                    confirmDismiss: (_) async {
                      if (active) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'Skip to remove the currently playing track.'),
                            duration: Duration(seconds: 2),
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
                            duration: const Duration(seconds: 4),
                            action: SnackBarAction(
                              label: 'Undo',
                              onPressed: () =>
                                  _undoRemove(actualIndex, removed),
                            ),
                          ),
                        );
                    },
                    child: Padding(
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
                              onLongPress: () =>
                                  showTrackContextMenu(context, ref, t),
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
    String resolve(AfTrack t) {
      if (mode == AppMode.local) return t.id;
      if (cacheEnabled) {
        final cachedUri = cache.cachedFileUri(t.id);
        if (cachedUri != null) return cachedUri;
      }
      if (backend != null) {
        final maxBitrate = ref.read(maxBitrateProvider);
        return backend.trackStreamUrl(t.id, maxBitrateKbps: maxBitrate == 0 ? null : maxBitrate);
      }
      return 'about:blank';
    }

    unawaited(
      ref.read(playerServiceProvider).insertIntoQueue(
            index,
            track,
            resolveStreamUrl: resolve,
          ),
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
        child: Column(
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
                border: OutlineInputBorder(),
              ),
              onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
            ),
            const SizedBox(height: AfSpacing.s24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.of(context).pop(controller.text.trim()),
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
        SnackBar(
          content: Text('Saved as "$name" · ${snapshot.length} tracks'),
        ),
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
