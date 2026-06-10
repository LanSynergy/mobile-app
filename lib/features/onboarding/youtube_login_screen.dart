import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/youtube/youtube_auth.dart';
import '../../design_tokens/tokens.dart';
import '../../utils/log.dart';
import '../../state/youtube_music_providers.dart';

/// WebView-based Google login screen for YouTube Music.
///
/// Opens m.youtube.com with a spoofed Chrome-Android UA to avoid Google's
/// "insecure browser" detection. Monitors CookieManager for SAPISID +
/// LOGIN_INFO to confirm successful login, then extracts dataSyncId
/// via JS injection.
class YouTubeLoginScreen extends ConsumerStatefulWidget {
  const YouTubeLoginScreen({super.key});

  @override
  ConsumerState<YouTubeLoginScreen> createState() => _YouTubeLoginScreenState();
}

class _YouTubeLoginScreenState extends ConsumerState<YouTubeLoginScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _isCompleting = false;
  String? _error;
  String? _dataSyncId;

  /// Native channel to read HttpOnly cookies from android.webkit.CookieManager.
  static const _ytAuthChannel = MethodChannel('aetherfin.youtube_auth');

  // Chrome-Android UA — strips wv + Version to avoid Google's embedded browser block.
  static const _chromeUserAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(_chromeUserAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: _onPageStarted,
          onPageFinished: _onPageFinished,
        ),
      )
      // Navigate to music.youtube.com — if already logged in, _tryCompleteLogin
      // fires immediately. If not, Google login flow starts from here.
      ..loadRequest(Uri.parse('https://music.youtube.com'));
  }

  void _onPageStarted(String url) {
    afLog('youtube', 'WebView page started: $url');
  }

  Future<void> _onPageFinished(String url) async {
    if (!mounted || _isCompleting) return;

    if (mounted && _isLoading) {
      setState(() => _isLoading = false);
    }

    // Once we reach music.youtube.com, try to extract cookies + dataSyncId.
    if (url.contains('music.youtube.com')) {
      await _tryCompleteLogin();
    }

    // Also try JS extraction on any page to get dataSyncId early.
    await _extractDataSyncId();
  }

  /// Extract dataSyncId from window.yt.config_ via JS injection.
  Future<void> _extractDataSyncId() async {
    try {
      final result = await _controller.runJavaScriptReturningResult(
        "window.yt && window.yt.config_ && window.yt.config_.DATASYNC_ID || ''",
      );
      final raw = result.toString();
      if (raw.isNotEmpty && raw != "''" && raw != '""' && raw != 'null') {
        // Strip surrounding quotes if present
        final cleaned = raw.replaceAll(RegExp(r"^[']+|[']+$"), '');
        if (cleaned.contains('||')) {
          _dataSyncId = cleaned.substringBefore('||');
        } else {
          _dataSyncId = cleaned;
        }
        afLog('youtube', 'dataSyncId extracted: $_dataSyncId');
      }
    } on Exception catch (e) {
      afLog('youtube', 'dataSyncId extraction failed', error: e);
    }
  }

  /// Attempt to complete login by reading cookies from native CookieManager.
  Future<void> _tryCompleteLogin() async {
    if (_isCompleting) return;
    _isCompleting = true;

    try {
      // Read ALL cookies (including HttpOnly) from android.webkit.CookieManager.
      final rawCookies = await _ytAuthChannel.invokeMethod<String>(
        'getCookies',
        {'url': 'https://music.youtube.com'},
      );
      if (rawCookies == null || rawCookies.isEmpty) {
        afLog('youtube', 'No cookies from CookieManager');
        if (mounted) {
          setState(() {
            _error = 'No cookies found. Please try again.';
            _isCompleting = false;
          });
        }
        return;
      }

      // Parse cookie string into map
      final cookies = <String, String>{};
      for (final part in rawCookies.split('; ')) {
        final idx = part.indexOf('=');
        if (idx > 0) {
          cookies[part.substring(0, idx)] = part.substring(idx + 1);
        }
      }

      // Check for required auth cookies
      final hasSapisid = cookies.containsKey('SAPISID') ||
          cookies.containsKey('__Secure-3PAPISID');
      final hasLoginInfo = cookies.containsKey('LOGIN_INFO');
      final hasSid = cookies.containsKey('SID');

      afLog(
        'youtube',
        'CookieManager cookies: ${cookies.length} '
        'SAPISID=$hasSapisid LOGIN_INFO=$hasLoginInfo SID=$hasSid',
      );

      if (!hasSapisid || !hasLoginInfo) {
        if (mounted) {
          setState(() {
            _error = 'Login incomplete. Please complete the sign-in process.';
            _isCompleting = false;
          });
        }
        return;
      }

      // Extract email from LOGIN_INFO cookie
      String email = '';
      try {
        final loginInfo = cookies['LOGIN_INFO'] ?? '';
        email = _decodeLoginInfo(loginInfo) ?? '';
      } on Exception catch (e) {
        afLog('youtube', 'Email extraction failed', error: e);
      }

      // Save auth bundle
      final authBundle = YouTubeAuthBundle(
        cookies: cookies,
        email: email,
        displayName: email.split('@').first,
        dataSyncId: _dataSyncId,
      );

      await ref.read(youtubeAuthProvider.notifier).save(authBundle);
      afLog(
        'youtube',
        'Login completed: email=$email cookies=${cookies.length}',
      );

      if (mounted) {
        context.go('/home');
      }
    } on Exception catch (e, stack) {
      afLog(
        'aetherfin:error',
        'Login completion failed',
        error: e,
        stackTrace: stack,
      );
      if (mounted) {
        setState(() {
          _error = 'Login failed: ${e.toString().substring(0, 100)}';
          _isCompleting = false;
        });
      }
    }
  }

  /// Try to extract email from LOGIN_INFO cookie.
  String? _decodeLoginInfo(String cookie) {
    try {
      // LOGIN_INFO is URL-safe base64. Decode and look for @ symbol pattern.
      final normalized = cookie.replaceAll('-', '+').replaceAll('_', '/');
      final padded = normalized + ('=' * (4 - normalized.length % 4));
      final bytes = Uri.decodeComponent(padded);
      // Look for email pattern in the decoded bytes
      final emailMatch = RegExp(r'[\w.+-]+@[\w.-]+\.\w+').firstMatch(bytes);
      return emailMatch?.group(0);
    } on Exception {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AfColors.surfaceCanvas,
      appBar: AppBar(
        backgroundColor: AfColors.surfaceBase,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AfColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Sign in to YouTube Music',
          style: TextStyle(color: AfColors.textPrimary),
        ),
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AfColors.textSecondary,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AfSpacing.s12),
              color: Colors.red.withValues(alpha: 0.15),
              child: Text(
                _error!,
                style: AfTypography.bodySmall.copyWith(
                  color: Colors.red.shade300,
                ),
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (_isLoading)
                  const Center(
                    child: CircularProgressIndicator(
                      color: AfColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Extension to add `substringBefore` to String.
extension _StringExt on String {
  String substringBefore(String delimiter) {
    final idx = indexOf(delimiter);
    return idx == -1 ? this : substring(0, idx);
  }
}
