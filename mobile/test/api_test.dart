import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:dama_mobile/game/game.dart';
import 'package:dama_mobile/models/room.dart';
import 'package:dama_mobile/services/api.dart';
import 'package:dama_mobile/services/session_store.dart';

const code = 'ABCDEFG234';
Map<String, dynamic> roomJson({int revision = 0}) => {
  'code': code,
  'createdAt': 1700000000000,
  'updatedAt': 1700000000000,
  'revision': revision,
  'members': [
    {
      'id': 'host',
      'name': 'ئارام',
      'role': 'white',
      'lastSeen': DateTime.now().millisecondsSinceEpoch,
    },
    {
      'id': 'friend',
      'name': 'شوان',
      'role': 'black',
      'lastSeen': DateTime.now().millisecondsSinceEpoch,
    },
  ],
  'game': newGame('game-1').toJson(),
  'started': true,
  'drawOffer': null,
  'rematchVotes': [],
  'me': 'host',
  'messages': [],
  'results': [],
};
http.Response response(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test('all endpoints use the existing authenticated web protocol', () async {
    final requests = <http.Request>[];
    final api = DamaApi(
      serverUrl: 'https://dama.example',
      token: 'a' * 43,
      client: MockClient((request) async {
        requests.add(request);
        expect(request.headers['x-player-token'], 'a' * 43);
        expect(request.headers.containsKey('origin'), false);
        if (request.url.path == '/api/status') {
          return response({'mode': 'redis', 'passwordRequired': true});
        }
        if (request.method == 'PATCH' &&
            jsonDecode(request.body)['type'] == 'leave') {
          return response({'left': true});
        }
        return response(roomJson(), request.method == 'POST' ? 201 : 200);
      }),
    );
    expect((await api.getStatus()).passwordRequired, true);
    expect(
      (await api.createRoom(name: 'ئارام', password: 'test-only')).code,
      code,
    );
    await api.joinRoom('abcd efg234', name: 'شوان', spectator: true);
    await api.getRoom(code);
    await api.action(code, {'type': 'message', 'text': 'سڵاو'});
    await api.leaveRoom(code);
    expect(requests.map((request) => '${request.method} ${request.url.path}'), [
      'GET /api/status',
      'POST /api/rooms',
      'POST /api/rooms/$code',
      'GET /api/rooms/$code',
      'PATCH /api/rooms/$code',
      'PATCH /api/rooms/$code',
    ]);
    expect(jsonDecode(requests[1].body), {
      'name': 'ئارام',
      'password': 'test-only',
    });
    expect(jsonDecode(requests[2].body)['role'], 'spectator');
    expect(jsonDecode(requests[4].body)['text'], 'سڵاو');
  });

  test('API errors keep the server message and typed status', () async {
    final api = DamaApi(
      client: MockClient(
        (_) async => response({'error': 'وشەی نهێنی دروست نییە.'}, 401),
      ),
    );
    await expectLater(
      api.createRoom(name: 'test'),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'status', 401)
            .having(
              (error) => error.message,
              'message',
              'وشەی نهێنی دروست نییە.',
            ),
      ),
    );
  });

  test(
    'invalid JSON and malformed room data become useful typed errors',
    () async {
      final htmlApi = DamaApi(
        client: MockClient(
          (_) async => http.Response('<html>bad gateway</html>', 502),
        ),
      );
      await expectLater(
        htmlApi.getStatus(),
        throwsA(
          isA<ApiException>().having(
            (error) => error.statusCode,
            'status',
            502,
          ),
        ),
      );
      final malformed = DamaApi(
        client: MockClient((_) async => response({'code': code})),
      );
      await expectLater(
        malformed.getRoom(code),
        throwsA(
          isA<ApiException>().having(
            (error) => error.statusCode,
            'status',
            502,
          ),
        ),
      );
    },
  );

  test('timeout also covers waiting for the initial HTTP connection', () async {
    final delayed = Completer<http.Response>();
    final api = DamaApi(
      timeout: const Duration(milliseconds: 5),
      client: MockClient((_) => delayed.future),
    );
    await expectLater(
      api.getStatus(),
      throwsA(
        isA<ApiException>().having((error) => error.statusCode, 'status', 0),
      ),
    );
    delayed.complete(response({'mode': 'redis', 'passwordRequired': false}));
  });

  test('URL and room-code validation rejects ambiguous destinations', () {
    expect(
      normalizeServerUrl(' https://dama.example/ '),
      'https://dama.example',
    );
    expect(normalizeRoomCode('abcd-efg234'), code);
    for (final url in [
      'dama.example',
      'file:///etc/passwd',
      'https://user:secret@dama.example',
      'https://dama.example/?room=abc',
    ]) {
      expect(() => normalizeServerUrl(url), throwsA(isA<ApiException>()));
    }
    expect(() => normalizeRoomCode('short'), throwsA(isA<ApiException>()));
    expect(normalizeRoomCode('https://dama.example/?room=abcd-efg234'), code);
    expect(
      normalizeRoomCode('http://localhost:3000/?room=ABCDEFG234#board'),
      code,
    );
    expect(
      () => normalizeRoomCode('https://dama.example/?other=ABCDEFG234'),
      throwsA(isA<ApiException>()),
    );
    expect(
      () => normalizeRoomCode(
        'https://dama.example/?room=ABCDEFG234&room=BCDEFGH234',
      ),
      throwsA(isA<ApiException>()),
    );
  });

  test(
    'pasted invite extracts the room without redirecting the player token',
    () async {
      final api = DamaApi(
        serverUrl: 'https://configured.example',
        token: 'a' * 43,
        client: MockClient((request) async {
          expect(request.url.host, 'configured.example');
          expect(request.url.path, '/api/rooms/$code');
          expect(request.headers['x-player-token'], 'a' * 43);
          return response(roomJson());
        }),
      );
      await api.joinRoom(
        'https://different.example/?room=ABCDEFG234',
        name: 'test',
      );
    },
  );

  test(
    'old rooms receive empty chat/history without leaking player tokens',
    () {
      final json = roomJson()
        ..remove('messages')
        ..remove('results');
      final room = RoomSnapshot.fromJson(json);
      expect(room.messages, isEmpty);
      expect(room.results, isEmpty);
      expect(room.self?.color, PlayerColor.white);
      expect(room.members.first.isOnline(), true);
      expect(room.createdAt.isUtc, true);
    },
  );

  test(
    'player tokens contain 32 cryptographically random bytes and no padding',
    () {
      final first = createPlayerToken(), second = createPlayerToken();
      expect(first, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
      expect(base64Url.decode(base64Url.normalize(first)).length, 32);
      expect(first, isNot(second));
    },
  );
}
