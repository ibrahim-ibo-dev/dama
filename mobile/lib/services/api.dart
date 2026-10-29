import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/room.dart';

const defaultServerUrl = String.fromEnvironment(
  'DAMA_SERVER_URL',
  defaultValue: 'https://dama.ibrahim-eng.dev',
);

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode = 0});
  final String message;
  final int statusCode;
  int get status => statusCode;
  bool get sessionMissing =>
      statusCode == 401 || statusCode == 403 || statusCode == 404;
  bool get isNetworkError => statusCode == 0 || statusCode >= 500;
  @override
  String toString() => message;
}

String normalizeServerUrl(String input) {
  final uri = Uri.tryParse(input.trim());
  if (uri == null ||
      !const ['https', 'http'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw const ApiException(
      'لینکی سێرڤەرەکە دروست نییە؛ بە https:// دەست پێ بکە.',
      statusCode: 400,
    );
  }
  return uri.toString().replaceFirst(RegExp(r'/+$'), '');
}

String normalizeRoomCode(String input) {
  var candidate = input.trim();
  final link = Uri.tryParse(candidate);
  if (link != null && const ['https', 'http'].contains(link.scheme)) {
    final codes = link.queryParametersAll['room'];
    if (codes == null || codes.length != 1) {
      throw const ApiException(
        'لینکی بانگهێشت کۆدی ڕوومێکی دروستی تێدا نییە.',
        statusCode: 400,
      );
    }
    // An invite contributes only its code. It never changes the configured
    // server, so pasting a link cannot redirect the player's capability.
    candidate = codes.single;
  }
  final code = candidate.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
  if (!RegExp(r'^[A-HJ-NP-Z2-9]{10}$').hasMatch(code)) {
    throw const ApiException(
      'کۆدی ڕووم دەبێت ١٠ پیت و ژمارە بێت.',
      statusCode: 400,
    );
  }
  return code;
}

/// HTTP speaks the same authenticated room protocol as the Next.js web client.
class DamaApi {
  DamaApi({
    http.Client? client,
    String serverUrl = defaultServerUrl,
    String token = '',
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _serverUrl = normalizeServerUrl(serverUrl),
       _token = token;
  final http.Client _client;
  final bool _ownsClient;
  final Duration timeout;
  String _serverUrl;
  String _token;
  String get serverUrl => _serverUrl;
  void configure({required String serverUrl, required String token}) {
    _serverUrl = normalizeServerUrl(serverUrl);
    _token = token;
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final headers = {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'x-player-token': _token,
    };
    final uri = Uri.parse('$_serverUrl$path');
    try {
      final request = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) request.body = jsonEncode(body);
      final response = await (() async {
        final streamed = await _client.send(request);
        return http.Response.fromStream(streamed);
      })().timeout(timeout);
      dynamic decoded;
      try {
        decoded = jsonDecode(utf8.decode(response.bodyBytes));
      } on FormatException {
        throw ApiException(
          'سێرڤەر وەڵامی دروستی نەدایەوە. دووبارە هەوڵ بدەوە.',
          statusCode: response.statusCode >= 400 ? response.statusCode : 502,
        );
      }
      if (decoded is! Map) {
        throw const ApiException(
          'دۆخی یارییەکە دروست نییە. دووبارە هەوڵ بدەوە.',
          statusCode: 502,
        );
      }
      final data = decoded.cast<String, dynamic>();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          data['error'] is String
              ? data['error'] as String
              : 'داواکارییەکە سەرکەوتوو نەبوو.',
          statusCode: response.statusCode,
        );
      }
      return data;
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException('وەڵامی سێرڤەر درەنگ کەوت. دووبارە هەوڵ بدەوە.');
    } catch (_) {
      throw const ApiException(
        'پەیوەندی بە سێرڤەر نەکرا. ئینتەرنێتەکەت بپشکنە.',
      );
    }
  }

  Future<T> _decode<T>(
    Future<Map<String, dynamic>> source,
    T Function(Map<String, dynamic>) parser,
  ) async {
    final json = await source;
    try {
      return parser(json);
    } catch (_) {
      throw const ApiException(
        'دۆخی یارییەکە دروست نییە. پەڕەکە نوێ بکەرەوە.',
        statusCode: 502,
      );
    }
  }

  Future<ServerStatus> getStatus() =>
      _decode(_request('GET', '/api/status'), ServerStatus.fromJson);
  Future<RoomSnapshot> createRoom({
    required String name,
    String password = '',
  }) => _decode(
    _request('POST', '/api/rooms', {'name': name, 'password': password}),
    RoomSnapshot.fromJson,
  );
  Future<RoomSnapshot> joinRoom(
    String code, {
    required String name,
    String password = '',
    bool spectator = false,
  }) => _decode(
    _request('POST', '/api/rooms/${normalizeRoomCode(code)}', {
      'name': name,
      'password': password,
      'role': spectator ? 'spectator' : 'player',
    }),
    RoomSnapshot.fromJson,
  );
  Future<RoomSnapshot> getRoom(String code) => _decode(
    _request('GET', '/api/rooms/${normalizeRoomCode(code)}'),
    RoomSnapshot.fromJson,
  );
  Future<RoomSnapshot> action(String code, Map<String, dynamic> action) =>
      _decode(
        _request('PATCH', '/api/rooms/${normalizeRoomCode(code)}', action),
        RoomSnapshot.fromJson,
      );
  Future<void> leaveRoom(String code) async {
    await _request('PATCH', '/api/rooms/${normalizeRoomCode(code)}', {
      'type': 'leave',
    });
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
