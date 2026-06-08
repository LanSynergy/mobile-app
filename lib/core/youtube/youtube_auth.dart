import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../utils/log.dart';

/// Google OAuth2 tokens for YouTube Music access.
class YouTubeAuth {
  const YouTubeAuth({
    required this.accessToken,
    required this.refreshToken,
    required this.email,
    required this.displayName,
    this.expiry,
  });

  factory YouTubeAuth.fromJson(Map<String, dynamic> json) => YouTubeAuth(
    accessToken: json['accessToken'] as String,
    refreshToken: json['refreshToken'] as String,
    email: json['email'] as String,
    displayName: json['displayName'] as String? ?? '',
    expiry: json['expiry'] != null
        ? DateTime.parse(json['expiry'] as String)
        : null,
  );

  final String accessToken;
  final String refreshToken;
  final String email;
  final String displayName;
  final DateTime? expiry;

  bool get isExpired {
    if (expiry == null) return true;
    return DateTime.now().isAfter(expiry!);
  }

  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'email': email,
    'displayName': displayName,
    'expiry': expiry?.toIso8601String(),
  };
}

/// Persists YouTube Music Google OAuth tokens in flutter_secure_storage.
class YouTubeAuthStorage {
  YouTubeAuthStorage([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage(aOptions: _options);

  static const _key = 'aetherfin.youtube.auth.v1';
  static const _options = AndroidOptions(encryptedSharedPreferences: true);

  final FlutterSecureStorage _storage;

  Future<void> save(YouTubeAuth auth) async {
    await _storage.write(key: _key, value: jsonEncode(auth.toJson()));
  }

  Future<YouTubeAuth?> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return YouTubeAuth.fromJson(decoded);
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
