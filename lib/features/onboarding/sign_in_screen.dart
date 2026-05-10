import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/jellyfin/client.dart';
import '../../core/jellyfin/models/server.dart';
import '../../design_tokens/tokens.dart';
import '../../state/providers.dart';
import '../../widgets/server_pill.dart';

class SignInScreen extends ConsumerStatefulWidget {
  final JellyfinServer server;
  const SignInScreen({super.key, required this.server});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _useToken = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final client = JellyfinClient(server: widget.server);
      final JellyfinAuth auth;
      if (_useToken) {
        // For "API token" path the user pastes a long-lived token. We
        // ask for the username alongside it so we have a stable user ID
        // for `/Users/{userId}/...` calls.
        auth = JellyfinAuth(
          server: widget.server,
          userId: _user.text.trim(),
          userName: _user.text.trim(),
          accessToken: _pass.text.trim(),
        );
      } else {
        auth = await client.authenticate(
          username: _user.text.trim(),
          password: _pass.text,
        );
      }
      await ref.read(authProvider.notifier).save(auth);
      if (!mounted) return;
      context.go('/onboarding/scope');
    } catch (_) {
      setState(() {
        _error = 'Couldn’t sign in. Check your username and password.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: Text('Sign in', style: AfTypography.titleMedium),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AfSpacing.s16),
            child: Center(
              child: ServerPill(
                state: ServerPillState.connectedOther,
                label: widget.server.name,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: AfSpacing.gutterGenerous),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AfSpacing.s16),
              Text(
                _useToken
                    ? 'Paste a Jellyfin API token. Find these under '
                        'Dashboard → API Keys on your server.'
                    : 'Enter your Jellyfin username and password.',
                style: AfTypography.bodyMedium.copyWith(
                  color: AfColors.textSecondary,
                ),
              ),
              const SizedBox(height: AfSpacing.s24),
              TextField(
                controller: _user,
                autocorrect: false,
                textCapitalization: TextCapitalization.none,
                decoration: const InputDecoration(hintText: 'Username'),
              ),
              const SizedBox(height: AfSpacing.s12),
              TextField(
                controller: _pass,
                obscureText: !_useToken,
                autocorrect: false,
                decoration: InputDecoration(
                  hintText: _useToken ? 'API token' : 'Password',
                  errorText: _error,
                ),
                onSubmitted: (_) => _busy ? null : _submit(),
              ),
              const SizedBox(height: AfSpacing.s12),
              Row(
                children: [
                  Switch.adaptive(
                    value: _useToken,
                    onChanged: (v) => setState(() => _useToken = v),
                    activeColor: AfColors.indigo500,
                  ),
                  const SizedBox(width: AfSpacing.s8),
                  Expanded(
                    child: Text(
                      'Use API token instead',
                      style: AfTypography.bodyMedium,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : const Text('Sign in'),
              ),
              const SizedBox(height: AfSpacing.s24),
            ],
          ),
        ),
      ),
    );
  }
}
