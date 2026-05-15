import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/jellyfin/client.dart';
import '../../core/jellyfin/discovery.dart';
import '../../core/jellyfin/models/server.dart';
import '../../core/subsonic/client.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../utils/log.dart';
import '../../widgets/press_scale.dart';

/// Mockup 02 — Server discovery.
///
///   Top: indigo gradient hero, brand mark in top-left (animates from
///   the previous screen via a Hero), "Find your server" title, body.
///   Middle: scanning indicator → list of `_jellyfin._tcp.local` servers.
///   Bottom: "Enter manually" affordance with URL input.
class ServerDiscoveryScreen extends ConsumerStatefulWidget {
  const ServerDiscoveryScreen({super.key});

  @override
  ConsumerState<ServerDiscoveryScreen> createState() =>
      _ServerDiscoveryScreenState();
}

class _ServerDiscoveryScreenState extends ConsumerState<ServerDiscoveryScreen> {
  StreamSubscription<JellyfinServer>? _sub;
  final _manualController = TextEditingController(text: 'http://');
  bool _scanning = true;
  String? _manualError;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  void _startScan() {
    setState(() => _scanning = true);
    ref.read(discoveredServersProvider.notifier).state = const [];
    _sub?.cancel();
    _sub = JellyfinDiscovery().scan().listen(
      (s) {
        final current = ref.read(discoveredServersProvider);
        if (!current.contains(s)) {
          ref.read(discoveredServersProvider.notifier).state = [...current, s];
        }
      },
      onError: (_) {},
      onDone: () => mounted ? setState(() => _scanning = false) : null,
    );
    Future.delayed(const Duration(seconds: 6), () {
      if (mounted) setState(() => _scanning = false);
    });
  }

  Future<void> _useManual() async {
    final raw = _manualController.text.trim();
    if (raw.isEmpty) return;
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      setState(() => _manualError = 'That URL doesn’t look right.');
      return;
    }
    setState(() => _manualError = null);

    // Preserve any base path the user pasted (e.g. https://media.example.com/jellyfin),
    // and strip a trailing slash so we don't construct doubled slashes
    // when Dio joins relative paths.
    final basePath = uri.path.replaceAll(RegExp(r'/+$'), '');
    final server = JellyfinServer(
      baseUrl: '${uri.scheme}://${uri.host}'
          '${uri.hasPort ? ':${uri.port}' : ''}'
          '$basePath',
      name: uri.host,
      isLocal: false,
    );

    // Try Jellyfin first, then Navidrome/Subsonic
    final jellyfinClient = JellyfinClient(
      server: server,
      deviceId: ref.read(deviceIdProvider),
    );
    try {
      final resolved = await jellyfinClient.publicInfo();
      _continueWith(resolved);
      return;
    } catch (_) {
      // Not a Jellyfin server — try Subsonic/Navidrome below
    } finally {
      jellyfinClient.close();
    }

    // Probe Subsonic ping.view — Navidrome responds with a Subsonic
    // API envelope even on bad credentials, confirming the server type.
    try {
      final testClient = SubsonicClient(
        server: server,
        username: '',
        password: '',
      );
      try {
        await testClient.ping();
      } on SubsonicApiError {
        // Expected — wrong/empty creds but the Subsonic envelope arrived
      }
      testClient.close();
      _continueWith(server.copyWith(
        name: 'Navidrome',
        isReachable: true,
      ), serverType: ServerType.subsonic);
    } catch (e, stack) {
      afLog(
        'error',
        'server discovery failed',
        error: e,
        stackTrace: stack,
      );
      setState(() =>
          _manualError = 'Couldn’t reach ${server.baseUrl}. $e');
    }
  }

  void _continueWith(JellyfinServer s, {ServerType serverType = ServerType.jellyfin}) {
    ref.read(discoveredServersProvider.notifier).state = [s];
    context.go('/onboarding/sign-in', extra: (server: s, serverType: serverType));
  }

  @override
  void dispose() {
    _sub?.cancel();
    _manualController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final servers = ref.watch(discoveredServersProvider);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            // We arrive here via `context.go()` from WelcomeScreen, which
            // replaces the stack — so `pop()` raises GoError("nothing to
            // pop"). Route home explicitly when the stack is empty.
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
        ),
        title: Text(
          'Find your server',
          style: AfTypography.titleMedium,
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AfSpacing.gutterGenerous,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AfSpacing.s8),
              Text(
                _scanning
                    ? 'Scanning your network for servers…'
                    : 'Pick a server, or enter its address.',
                style: AfTypography.bodyMedium.copyWith(
                  color: AfColors.textSecondary,
                ),
              ),
              const SizedBox(height: AfSpacing.s24),
              if (_scanning && servers.isEmpty)
                const Center(
                  child: SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                ),
              for (final s in servers) ...[
                _ServerCard(server: s, onTap: () => _continueWith(s)),
                const SizedBox(height: AfSpacing.s12),
              ],
              if (!_scanning && servers.isEmpty)
                Text(
                  'No servers found. Make sure your server (Jellyfin '
                  'or Navidrome) is running and on the same Wi-Fi, then '
                  'enter its URL below.',
                  style: AfTypography.bodyMedium.copyWith(
                    color: AfColors.textTertiary,
                  ),
                ),
              const Spacer(),
              const Divider(color: AfColors.surfaceLow),
              const SizedBox(height: AfSpacing.s16),
              Text(
                'Or enter manually',
                style: AfTypography.label.copyWith(
                  color: AfColors.textTertiary,
                ),
              ),
              const SizedBox(height: AfSpacing.s8),
              TextField(
                controller: _manualController,
                keyboardType: TextInputType.url,
                autocorrect: false,
                style: AfTypography.bodyLarge,
                decoration: InputDecoration(
                  hintText: 'http://192.168.1.10:8096',
                  errorText: _manualError,
                ),
                onSubmitted: (_) => _useManual(),
              ),
              const SizedBox(height: AfSpacing.s12),
              ElevatedButton(
                onPressed: _useManual,
                child: const Text('Continue'),
              ),
              const SizedBox(height: AfSpacing.s24),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServerCard extends StatelessWidget {
  final JellyfinServer server;
  final VoidCallback onTap;
  const _ServerCard({required this.server, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return PressScale(
      ensureHitTarget: false,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AfSpacing.s16),
        decoration: BoxDecoration(
          color: AfColors.surfaceBase,
          borderRadius: AfRadii.borderLg,
          border: Border.all(color: AfColors.surfaceHigh, width: 1),
        ),
        child: Row(
          children: [
            const Icon(Icons.dns_outlined, color: AfColors.indigo300),
            const SizedBox(width: AfSpacing.s16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(server.name, style: AfTypography.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    server.baseUrl,
                    style: AfTypography.bodySmall.copyWith(
                      color: AfColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AfColors.textTertiary),
          ],
        ),
      ),
    );
  }
}
