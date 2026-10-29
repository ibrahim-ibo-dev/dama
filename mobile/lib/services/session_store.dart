import 'dart:convert';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class SessionStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
  Future<String?> readToken(String serverUrl);
  Future<void> writeToken(String serverUrl, String token);
}

/// Only non-sensitive preferences use SharedPreferences. Per-server player
/// capabilities stay in Keychain/Android encrypted secure storage.
class SecureSessionStore implements SessionStore {
  SecureSessionStore({
    FlutterSecureStorage? secureStorage,
    SharedPreferences? preferences,
  }) : _secure = secureStorage ?? const FlutterSecureStorage(),
       _preferences = preferences;
  final FlutterSecureStorage _secure;
  SharedPreferences? _preferences;
  Future<SharedPreferences> get _prefs async =>
      _preferences ??= await SharedPreferences.getInstance();
  String _tokenKey(String serverUrl) =>
      'dama.identity.${base64Url.encode(utf8.encode(serverUrl)).replaceAll('=', '')}';
  @override
  Future<String?> read(String key) async => (await _prefs).getString(key);
  @override
  Future<void> write(String key, String value) async {
    await (await _prefs).setString(key, value);
  }

  @override
  Future<void> remove(String key) async {
    await (await _prefs).remove(key);
  }

  @override
  Future<String?> readToken(String serverUrl) =>
      _secure.read(key: _tokenKey(serverUrl));
  @override
  Future<void> writeToken(String serverUrl, String token) =>
      _secure.write(key: _tokenKey(serverUrl), value: token);
}

class MemorySessionStore implements SessionStore {
  MemorySessionStore({Map<String, String>? values, Map<String, String>? tokens})
    : values = {...?values},
      tokens = {...?tokens};
  final Map<String, String> values;
  final Map<String, String> tokens;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> readToken(String serverUrl) async => tokens[serverUrl];
  @override
  Future<void> writeToken(String serverUrl, String token) async {
    tokens[serverUrl] = token;
  }
}

String createPlayerToken() {
  final random = Random.secure();
  return base64Url
      .encode(List<int>.generate(32, (_) => random.nextInt(256)))
      .replaceAll('=', '');
}
