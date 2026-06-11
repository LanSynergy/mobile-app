import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists Last.fm credentials in flutter_secure_storage so the
/// API secret and session key never live in plain shared prefs.
class LastFmStorage {
  LastFmStorage([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage(aOptions: _options);

  static const _apiKeyKey = 'aetherfin.lastfm.api_key.v1';
  static const _apiSecretKey = 'aetherfin.lastfm.api_secret.v1';
  static const _sessionKeyKey = 'aetherfin.lastfm.session_key.v1';
  static const _usernameKey = 'aetherfin.lastfm.username.v1';
  static const _scrobbleEnabledKey = 'aetherfin.lastfm.scrobble_enabled.v1';
  static const _options = AndroidOptions();

  final FlutterSecureStorage _storage;

  Future<void> saveApiKey(String val) =>
      _storage.write(key: _apiKeyKey, value: val);
  Future<void> saveApiSecret(String val) =>
      _storage.write(key: _apiSecretKey, value: val);
  Future<void> saveSessionKey(String val) =>
      _storage.write(key: _sessionKeyKey, value: val);
  Future<void> saveUsername(String val) =>
      _storage.write(key: _usernameKey, value: val);
  Future<void> saveScrobbleEnabled(bool val) =>
      _storage.write(key: _scrobbleEnabledKey, value: val.toString());

  Future<String> loadApiKey() async =>
      (await _storage.read(key: _apiKeyKey)) ?? '';
  Future<String> loadApiSecret() async =>
      (await _storage.read(key: _apiSecretKey)) ?? '';
  Future<String> loadSessionKey() async =>
      (await _storage.read(key: _sessionKeyKey)) ?? '';
  Future<String> loadUsername() async =>
      (await _storage.read(key: _usernameKey)) ?? '';
  Future<bool> loadScrobbleEnabled() async =>
      (await _storage.read(key: _scrobbleEnabledKey)) != 'false';

  Future<void> clear() async {
    await _storage.delete(key: _apiKeyKey);
    await _storage.delete(key: _apiSecretKey);
    await _storage.delete(key: _sessionKeyKey);
    await _storage.delete(key: _usernameKey);
    await _storage.delete(key: _scrobbleEnabledKey);
  }

  /// Migrate credentials from plain SharedPreferences to secure storage.
  /// Call once during boot; safe to call repeatedly (no-ops if already migrated).
  Future<void> migrateFromSharedPreferences() async {
    final prefs = await SharedPreferences.getInstance();

    final oldApiKey = prefs.getString('af.lastfm_api_key');
    final oldApiSecret = prefs.getString('af.lastfm_api_secret');
    final oldSessionKey = prefs.getString('af.lastfm_session_key');
    final oldUsername = prefs.getString('af.lastfm_username');
    final oldScrobble = prefs.getBool('af.lastfm_scrobble_enabled');

    if (oldApiKey != null && oldApiKey.isNotEmpty) {
      await _storage.write(key: _apiKeyKey, value: oldApiKey);
      await prefs.remove('af.lastfm_api_key');
    }
    if (oldApiSecret != null && oldApiSecret.isNotEmpty) {
      await _storage.write(key: _apiSecretKey, value: oldApiSecret);
      await prefs.remove('af.lastfm_api_secret');
    }
    if (oldSessionKey != null && oldSessionKey.isNotEmpty) {
      await _storage.write(key: _sessionKeyKey, value: oldSessionKey);
      await prefs.remove('af.lastfm_session_key');
    }
    if (oldUsername != null && oldUsername.isNotEmpty) {
      await _storage.write(key: _usernameKey, value: oldUsername);
      await prefs.remove('af.lastfm_username');
    }
    if (oldScrobble != null) {
      await _storage.write(
        key: _scrobbleEnabledKey,
        value: oldScrobble.toString(),
      );
      await prefs.remove('af.lastfm_scrobble_enabled');
    }
  }
}
