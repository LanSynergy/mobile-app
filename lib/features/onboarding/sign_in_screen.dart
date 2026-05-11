import 'package:dio/dio.dart';
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
      final client = JellyfinClient(
        server: widget.server,
        deviceId: ref.read(deviceIdProvider),
      );
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
    } catch (e, stack) {
      // ignore: avoid_print
      print('aetherfin:error sign-in failed: $e');
      if (e is DioException) {
        // ignore: avoid_print
        print('aetherfin:error url: ${e.requestOptions.uri}');
        // ignore: avoid_print
        print('aetherfin:error status: ${e.response?.statusCode}');
        // ignore: avoid_print
        print('aetherfin:error body: ${e.response?.data}');
        // ignore: avoid_print
        print('aetherfin:error headers: ${e.response?.headers.map}');
      }
      // ignore: avoid_print
      print('aetherfin:error stack: $stack');
      setState(() {
        _error = _humanizeError(e);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Translate raw exception text into something the user can act on.
  /// Falls back to the full exception string so we never hide what's wrong
  /// behind a generic 'check your username' message.
  String _humanizeError(Object e) {
    if (e is DioException) {
      final status = e.response?.statusCode;
      final url = e.requestOptions.uri.toString();
      if (status == 401 || status == 403) {
        return 'Wrong username or password (HTTP $status from $url).';
      }
      if (status != null) {
        // Trim body to first 240 chars so a giant HTML 500 page doesn't
        // swamp the input field's helper text. Full body is in logcat.
        final raw = e.response?.data?.toString() ?? '';
        final body =
            raw.length > 240 ? '${raw.substring(0, 240)}…' : raw;
        return 'HTTP $status from $url\n'
            '${body.isNotEmpty ? body : "(no body)"}';
      }
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return 'Connection timed out reaching ${widget.server.baseUrl}.';
        case DioExceptionType.connectionError:
          return 'Could not reach ${widget.server.baseUrl}. ${e.message ?? ""}';
        case DioExceptionType.badCertificate:
          return 'TLS certificate rejected for ${widget.server.baseUrl}.';
        default:
          return '${e.type.name}: ${e.message ?? e.error ?? "unknown"}';
      }
    }
    return e.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            // Onboarding navigates with context.go() (which replaces the
            // stack), so pop is a no-op. Route home to the discovery step
            // explicitly instead.
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/onboarding/discover');
            }
          },
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
