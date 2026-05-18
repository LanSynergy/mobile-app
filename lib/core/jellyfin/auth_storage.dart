import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../utils/log.dart';
import 'models/server.dart';

/// Persists the active [JellyfinAuth] in flutter_secure_storage so the
/// access token survives app restarts and never lives in plain shared prefs.
class AuthStorage {
  static const _key = 'aetherfin.auth.v1';
  static const _deviceIdKey = 'aetherfin.deviceId.v1';
  static const _options = AndroidOptions(encryptedSharedPreferences: true);

  final FlutterSecureStorage _storage;
  AuthStorage([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage(aOptions: _options);

  /// Returns the stable per-install device ID. Generated on first call and
  /// persisted to encrypted shared prefs so Jellyfin sees the same device
  /// across app launches (avoiding duplicate-session noise) but a different
  /// device across re-installs (so a stale device record cannot collide
  /// with a fresh install).
  ///
  /// Jellyfin's `SessionManager` keys devices by this string. Reusing a
  /// hardcoded value across different installs is a known cause of the
  /// 500 "Error processing request" we hit on /Users/AuthenticateByName.
  Future<String> loadOrCreateDeviceId() async {
    final existing = await _storage.read(key: _deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    // base64url, strip padding so the result fits comfortably inside the
    // Authorization header without quoting concerns.
    final id = base64UrlEncode(bytes).replaceAll('=', '');
    await _storage.write(key: _deviceIdKey, value: id);
    return id;
  }

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
      'serverType': auth.serverType.name,
    };
    await _storage.write(key: _key, value: jsonEncode(json));
  }

  Future<JellyfinAuth?> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    // Decode defensively: a corrupt blob (partial write, mismatched schema
    // from an older build) used to throw and bubble all the way up to
    // main.dart, which then dropped the user into the fallback-device-id
    // path even when only the auth payload was bad. Return null instead so
    // the boot path treats it the same as "no auth stored" — user signs in
    // again — without losing the persistent device ID.
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        afLog('error', 'auth blob has unexpected top-level type; discarding');
        return null;
      }
      final m = decoded;
      final typeStr = m['serverType'] as String?;
      final serverType = typeStr == 'subsonic'
          ? ServerType.subsonic
          : ServerType.jellyfin;
      final baseUrl = m['baseUrl'] as String?;
      final userId = m['userId'] as String?;
      final userName = m['userName'] as String?;
      final accessToken = m['accessToken'] as String?;
      if (baseUrl == null ||
          userId == null ||
          userName == null ||
          accessToken == null) {
        afLog('error', 'auth blob missing required field; discarding');
        return null;
      }
      return JellyfinAuth(
        server: JellyfinServer(
          baseUrl: baseUrl,
          name: m['name'] as String? ??
              (serverType == ServerType.subsonic ? 'Navidrome' : 'Jellyfin'),
          version: m['version'] as String?,
          id: m['id'] as String?,
          isLocal: m['isLocal'] as bool? ?? false,
        ),
        userId: userId,
        userName: userName,
        accessToken: accessToken,
        serverType: serverType,
      );
    } catch (e, stack) {
      afLog('error', 'auth blob deserialization failed; discarding',
          error: e, stackTrace: stack);
      return null;
    }
  }

  Future<void> clear() async {
    await _storage.delete(key: _key);
  }
}
