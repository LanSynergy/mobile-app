import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../utils/log.dart';

/// Cookie-based authentication bundle for YouTube Music.
///
/// Stores Google session cookies captured from a WebView login flow.
/// Used to generate SAPISIDHASH headers for authenticated InnerTube requests.
class YouTubeAuthBundle {
  const YouTubeAuthBundle({
    required this.cookies,
    required this.email,
    this.displayName = '',
    this.dataSyncId,
    this.profileUrl,
  });

  factory YouTubeAuthBundle.fromJson(Map<String, dynamic> json) =>
      YouTubeAuthBundle(
        cookies: Map<String, String>.from(json['cookies'] as Map? ?? {}),
        email: json['email'] as String? ?? '',
        displayName: json['displayName'] as String? ?? '',
        dataSyncId: json['dataSyncId'] as String?,
        profileUrl: json['profileUrl'] as String?,
      );

  final Map<String, String> cookies;
  final String email;
  final String displayName;
  final String? dataSyncId;
  final String? profileUrl;

  bool get isValid =>
      cookies.containsKey('SAPISID') ||
      cookies.containsKey('__Secure-3PAPISID');

  String get cookieString =>
      cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

  String? get authorizationHeader {
    final sapisid = cookies['SAPISID'] ?? cookies['__Secure-3PAPISID'];
    if (sapisid == null || sapisid.isEmpty) return null;

    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final input = '$timestamp $sapisid https://music.youtube.com';
    final hash = sha1.convert(utf8.encode(input));
    return 'SAPISIDHASH ${timestamp}_$hash';
  }

  Map<String, dynamic> toJson() => {
    'cookies': cookies,
    'email': email,
    'displayName': displayName,
    'dataSyncId': dataSyncId,
    'profileUrl': profileUrl,
  };
}

/// Persists YouTube Music cookie-based auth in flutter_secure_storage.
class YouTubeAuthStorage {
  YouTubeAuthStorage([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage(aOptions: _options);

  static const _key = 'aetherfin.youtube.auth.v1';
  static const _options = AndroidOptions(encryptedSharedPreferences: true);

  final FlutterSecureStorage _storage;

  Future<void> save(YouTubeAuthBundle auth) async {
    await _storage.write(key: _key, value: jsonEncode(auth.toJson()));
  }

  Future<YouTubeAuthBundle?> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final bundle = YouTubeAuthBundle.fromJson(decoded);
      return bundle.isValid ? bundle : null;
    } on Exception catch (e, stack) {
      afLog(
        'aetherfin:error',
        'YouTube auth deserialization failed; discarding',
        error: e,
        stackTrace: stack,
      );
      return null;
    }
  }

  Future<void> clear() async {
    await _storage.delete(key: _key);
  }
}
