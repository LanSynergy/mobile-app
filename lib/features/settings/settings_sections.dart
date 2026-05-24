import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/audio/player_settings_store.dart';
import '../../core/audio/player_service.dart';
import '../../state/providers.dart';
import '../../design_tokens/tokens.dart';
import 'settings_widgets.dart';

void launchSettingsUrl(String url) {
  launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

class MusicFoldersCard extends ConsumerStatefulWidget {
  const MusicFoldersCard({super.key});
  @override
  ConsumerState<MusicFoldersCard> createState() => MusicFoldersCardState();
}

class MusicFoldersCardState extends ConsumerState<MusicFoldersCard> {
  List<({String uri, String displayPath})> _folders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    final lib = ref.read(localLibraryProvider);
    final folders = await lib.getFolders();
    if (mounted) setState(() { _folders = folders; _loading = false; });
  }

  Future<void> _addFolder() async {
    final lib = ref.read(localLibraryProvider);
    final uri = await lib.pickAndAddFolder();
    if (uri != null) {
      await _loadFolders();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Scanning new folder...')),
        );
        await lib.scanFolder(uri);
        ref.invalidate(localAlbumsProvider);
        ref.invalidate(localArtistsProvider);
        ref.invalidate(localTracksProvider);
        ref.invalidate(localGenresProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Scan complete')),
          );
        }
      }
    }
  }

  Future<void> _removeFolder(String uri) async {
    final lib = ref.read(localLibraryProvider);
    await lib.removeFolder(uri);
    await _loadFolders();
    ref.invalidate(localAlbumsProvider);
    ref.invalidate(localArtistsProvider);
    ref.invalidate(localTracksProvider);
    ref.invalidate(localGenresProvider);
  }

  Future<void> _rescan() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Scanning all folders...')),
    );
    final lib = ref.read(localLibraryProvider);
    final count = await lib.scanAll();
    ref.invalidate(localAlbumsProvider);
    ref.invalidate(localArtistsProvider);
    ref.invalidate(localTracksProvider);
    ref.invalidate(localGenresProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Scan complete — $count tracks updated')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsGroup(
      children: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(AfSpacing.s16),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          for (final folder in _folders)
            SettingsTile(
              icon: LucideIcons.folder,
              iconColor: AfColors.textSecondary,
              title: folder.displayPath,
              trailing: IconButton(
                icon: const Icon(LucideIcons.circleMinus,
                    color: AfColors.semanticError, size: 20),
                onPressed: () => _removeFolder(folder.uri),
              ),
            ),
          SettingsTile(
            icon: LucideIcons.plus,
            iconColor: AfColors.textSecondary,
            title: 'Add folder',
            subtitle: 'Pick another music folder',
            onTap: _addFolder,
          ),
          SettingsTile(
            icon: LucideIcons.refreshCcw,
            iconColor: AfColors.textSecondary,
            title: 'Re-scan library',
            subtitle: 'Check for new or changed files',
            onTap: _rescan,
          ),
        ],
      ],
    );
  }
}

class PrefetchToggle extends StatefulWidget {
  const PrefetchToggle({super.key, required this.svc});
  final AfPlayerService svc;

  @override
  State<PrefetchToggle> createState() => PrefetchToggleState();
}

class PrefetchToggleState extends State<PrefetchToggle> {
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    _enabled = widget.svc.prefetchPlaylist;
  }

  @override
  Widget build(BuildContext context) {
    return SettingsSwitchTile(
      icon: LucideIcons.download,
      iconColor: AfColors.textSecondary,
      title: 'Prefetch next track',
      subtitle: 'Pre-load next playlist entry in background',
      value: _enabled,
      onChanged: (v) {
        setState(() => _enabled = v);
        unawaited(widget.svc.setPrefetchPlaylist(v));
        unawaited(PlayerSettingsStore.savePrefetchPlaylist(v));
      },
    );
  }
}

class ArtworkPulseSwitch extends ConsumerWidget {
  const ArtworkPulseSwitch({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(artworkPulseEnabledProvider);
    return SettingsSwitchTile(
      icon: LucideIcons.sparkles,
      iconColor: AfColors.textSecondary,
      title: 'Artwork pulse',
      subtitle: 'Scale artwork on kick drums',
      value: enabled,
      onChanged: (v) {
        ref.read(artworkPulseEnabledProvider.notifier).state = v;
        unawaited(PlayerSettingsStore.saveArtworkPulse(v));
      },
    );
  }
}
