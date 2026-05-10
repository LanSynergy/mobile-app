import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'models/server.dart';

/// Persists the active [JellyfinAuth] in flutter_secure_storage so the
/// access token survives app restarts and never lives in plain shared prefs.
class AuthStorage {
  static const _key = 'aetherfin.auth.v1';
  static const _options = AndroidOptions(encryptedSharedPreferences: true);

  final FlutterSecureStorage _storage;
  AuthStorage([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage(aOptions: _options);

  Future<void> save(JellyfinAuth auth) async {
    final json = {
      'baseUrl': auth.server.baseUrl,
      'name': auth.server.name,
      'version': auth.server.version,
      'id': auth.server.id,
      'isLocal': auth.server.isLocal,
      'userId': auth.userId,
      'userName': auth.userName,
      'accessToken': auth.accessToken,
    };
    await _storage.write(key: _key, value: jsonEncode(json));
  }

  Future<JellyfinAuth?> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    final m = jsonDecode(raw) as Map<String, dynamic>;
    return JellyfinAuth(
      server: JellyfinServer(
        baseUrl: m['baseUrl'] as String,
        name: m['name'] as String? ?? 'Jellyfin',
        version: m['version'] as String?,
        id: m['id'] as String?,
        isLocal: m['isLocal'] as bool? ?? false,
      ),
      userId: m['userId'] as String,
      userName: m['userName'] as String,
      accessToken: m['accessToken'] as String,
    );
  }

  Future<void> clear() async {
    await _storage.delete(key: _key);
  }
}
