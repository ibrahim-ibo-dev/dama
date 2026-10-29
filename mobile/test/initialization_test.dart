import 'dart:async';
import 'dart:convert';

import 'package:dama_mobile/game/bot.dart';
import 'package:dama_mobile/game/game.dart';
import 'package:dama_mobile/services/api.dart';
import 'package:dama_mobile/services/session_store.dart';
import 'package:dama_mobile/state/dama_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const server = 'https://native.example';

http.Response response(Object data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

http.Response roomResponse() => response({
  'code': 'ABCDEFG234',
  'createdAt': 1700000000000,
  'updatedAt': 1700000000000,
  'revision': 0,
  'members': [
    {'id': 'host', 'name': 'تۆ', 'role': 'white', 'lastSeen': 1700000000000},
  ],
  'game': newGame('online-game').toJson(),
  'started': false,
  'drawOffer': null,
  'rematchVotes': [],
  'me': 'host',
  'messages': [],
  'results': [],
});

class ControlledStore extends MemorySessionStore {
  ControlledStore({super.values, super.tokens});
  final gates = <String, Completer<String?>>{};
  final readSignals = <String, Completer<void>>{};
  bool failPreferences = false;
  bool failTokenRead = false;
  bool failTokenWrite = false;
  int tokenWrites = 0;

  @override
  Future<String?> read(String key) async {
    final signal = readSignals[key];
    if (signal != null && !signal.isCompleted) signal.complete();
    if (failPreferences) throw StateError('Preference backend unavailable');
    if (gates[key] case final gate?) return gate.future;
    return super.read(key);
  }

  @override
  Future<void> write(String key, String value) async {
    if (failPreferences) throw StateError('Preference write unavailable');
    return super.write(key, value);
  }

  @override
  Future<void> remove(String key) async {
    if (failPreferences) throw StateError('Preference removal unavailable');
    return super.remove(key);
  }

  @override
  Future<String?> readToken(String serverUrl) async {
    if (failTokenRead) throw StateError('Keychain locked');
    return super.readToken(serverUrl);
  }

  @override
  Future<void> writeToken(String serverUrl, String token) async {
    tokenWrites++;
    if (failTokenWrite) throw StateError('Secure write unavailable');
    return super.writeToken(serverUrl, token);
  }
}

DamaController controller(
  ControlledStore store,
  Future<http.Response> Function(http.Request) handler,
) => DamaController(
  api: DamaApi(client: MockClient(handler), serverUrl: server),
  store: store,
  autoPoll: false,
  observeLifecycle: false,
);

void main() {
  test(
    'early solo play cannot strand initialization or later online entry',
    () async {
      final gate = Completer<String?>();
      final store = ControlledStore(values: {'dama.botLevel': 'easy'})
        ..gates['dama.server'] = gate;
      final value = controller(store, (request) async {
        if (request.url.path == '/api/status') {
          return response({'mode': 'redis', 'passwordRequired': false});
        }
        if (request.method == 'POST') return roomResponse();
        return response({'left': true});
      });
      addTearDown(value.dispose);
      final initialization = value.initialize();
      value.startSolo(level: BotLevel.hard);
      final gameId = value.game!.id;
      gate.complete(server);
      await initialization;
      expect(value.initializing, false);
      expect(value.mode, GameMode.bot);
      expect(value.game!.id, gameId);
      expect(value.botLevel, BotLevel.hard);
      expect(await value.leave(), true);
      value.setName('ئارام');
      expect(await value.createRoom(), true);
      expect(value.mode, GameMode.online);
    },
  );

  test(
    'delayed persisted preferences cannot overwrite a new name or level',
    () async {
      final nameGate = Completer<String?>();
      final nameRead = Completer<void>();
      final store = ControlledStore(values: {'dama.botLevel': 'easy'})
        ..gates['dama.name'] = nameGate
        ..readSignals['dama.name'] = nameRead;
      final value = controller(
        store,
        (_) async => response({'mode': 'redis', 'passwordRequired': false}),
      );
      addTearDown(value.dispose);
      final initialization = value.initialize();
      await nameRead.future;
      value.setName('ناوی نوێ');
      value.startSolo(level: BotLevel.hard);
      nameGate.complete('ناوی کۆن');
      await initialization;
      expect(value.name, 'ناوی نوێ');
      expect(value.botLevel, BotLevel.hard);
      expect(value.initializing, false);
    },
  );

  test(
    'late startup status cannot replace solo with a restored online room',
    () async {
      final pending = Completer<http.Response>();
      final called = Completer<void>();
      var roomReads = 0;
      final store = ControlledStore(values: {'dama.room': 'ABCDEFG234'});
      final value = controller(store, (request) async {
        if (request.url.path == '/api/status') {
          called.complete();
          return pending.future;
        }
        roomReads++;
        return roomResponse();
      });
      addTearDown(value.dispose);
      final initialization = value.initialize();
      await called.future;
      value.startHotseat();
      pending.complete(response({'mode': 'redis', 'passwordRequired': false}));
      await initialization;
      expect(value.mode, GameMode.hotseat);
      expect(value.room, isNull);
      expect(roomReads, 0);
      expect(value.initializing, false);
    },
  );

  test(
    'server switch supersedes delayed startup configuration and identity',
    () async {
      final gate = Completer<String?>();
      final store = ControlledStore()..gates['dama.server'] = gate;
      final hosts = <String>[];
      final value = controller(store, (request) async {
        hosts.add(request.url.host);
        return response({'mode': 'redis', 'passwordRequired': false});
      });
      addTearDown(value.dispose);
      final initialization = value.initialize();
      expect(await value.setServerUrl('https://new.example'), true);
      gate.complete('https://stale.example');
      await initialization;
      expect(value.serverUrl, 'https://new.example');
      expect(value.initializing, false);
      expect(hosts, ['new.example']);
      expect(store.tokens.keys, ['https://new.example']);
    },
  );

  test(
    'secure write failure keeps an authenticated in-memory capability',
    () async {
      final store = ControlledStore()..failTokenWrite = true;
      final seenTokens = <String>[];
      final value = controller(store, (request) async {
        seenTokens.add(request.headers['x-player-token']!);
        return request.method == 'POST'
            ? roomResponse()
            : response({'mode': 'redis', 'passwordRequired': false});
      });
      addTearDown(value.dispose);
      await value.initialize();
      expect(value.initializing, false);
      expect(value.status?.mode, 'redis');
      expect(value.error, isNotNull);
      value.setName('ئارام');
      expect(await value.createRoom(), true);
      expect(seenTokens.length, 2);
      expect(seenTokens.first, matches(RegExp(r'^[A-Za-z0-9_-]{32,128}$')));
      expect(seenTokens.last, seenTokens.first);
      expect(store.tokens, isEmpty);
    },
  );

  test(
    'a failed secure read must not overwrite an existing unknown identity',
    () async {
      final oldToken = 's' * 43;
      final store = ControlledStore(tokens: {server: oldToken})
        ..failTokenRead = true;
      final value = controller(
        store,
        (_) async => response({'mode': 'redis', 'passwordRequired': false}),
      );
      addTearDown(value.dispose);
      await value.initialize();
      expect(value.status?.mode, 'redis');
      expect(value.error, isNotNull);
      expect(store.tokenWrites, 0);
      expect(store.tokens[server], oldToken);
    },
  );

  test(
    'preference failures do not undo successful create or leave actions',
    () async {
      final store = ControlledStore()..failPreferences = true;
      final value = controller(store, (request) async {
        if (request.url.path == '/api/status') {
          return response({'mode': 'redis', 'passwordRequired': false});
        }
        if (request.method == 'POST') return roomResponse();
        return response({'left': true});
      });
      addTearDown(value.dispose);
      await value.initialize();
      expect(value.status?.mode, 'redis');
      value.setName('ئارام');
      expect(await value.createRoom(), true);
      expect(value.mode, GameMode.online);
      expect(value.error, isNotNull);
      expect(await value.leave(), true);
      expect(value.mode, GameMode.lobby);
      expect(value.room, isNull);
      expect(value.busy, false);
    },
  );

  test(
    'lobby refresh retries status after initialization network failure',
    () async {
      var calls = 0;
      final value = controller(ControlledStore(), (_) async {
        if (calls++ == 0) return response({'error': 'offline'}, 503);
        return response({'mode': 'redis', 'passwordRequired': false});
      });
      addTearDown(value.dispose);
      await value.initialize();
      expect(value.status, isNull);
      expect(value.connected, false);
      await value.refresh();
      expect(value.status?.mode, 'redis');
      expect(value.connected, true);
      expect(value.error, isNull);
    },
  );

  test(
    'late failed status retry cannot mark the replacement server offline',
    () async {
      final pending = Completer<http.Response>();
      final called = Completer<void>();
      var firstServerCalls = 0;
      final value = controller(ControlledStore(), (request) async {
        if (request.url.host == 'native.example' && firstServerCalls++ > 0) {
          called.complete();
          return pending.future;
        }
        return response({'mode': 'redis', 'passwordRequired': false});
      });
      addTearDown(value.dispose);
      await value.initialize();
      final retry = value.refresh();
      await called.future;
      expect(await value.setServerUrl('https://new.example'), true);
      pending.complete(response({'error': 'old-server-offline'}, 503));
      await retry;
      expect(value.serverUrl, 'https://new.example');
      expect(value.status?.mode, 'redis');
      expect(value.connected, true);
      expect(value.error, isNull);
    },
  );

  test('disposal invalidates delayed startup before any API call', () async {
    final gate = Completer<String?>();
    final store = ControlledStore()..gates['dama.server'] = gate;
    var requests = 0;
    final value = controller(store, (_) async {
      requests++;
      return response({'mode': 'redis', 'passwordRequired': false});
    });
    final initialization = value.initialize();
    value.dispose();
    gate.complete(server);
    await initialization;
    expect(requests, 0);
  });
  test(
    'retry restores a saved seat after a transient startup room failure',
    () async {
      var roomReads = 0;
      final store = ControlledStore(values: {'dama.room': 'ABCDEFG234'});
      final value = controller(store, (request) async {
        if (request.url.path == '/api/status') {
          return response({'mode': 'redis', 'passwordRequired': false});
        }
        roomReads++;
        return roomReads == 1
            ? response({'error': 'temporary'}, 503)
            : roomResponse();
      });
      await value.initialize();
      expect(value.room, isNull);
      expect(value.savedRoomCode, 'ABCDEFG234');
      await value.refresh();
      expect(value.mode, GameMode.online);
      expect(value.room?.code, 'ABCDEFG234');
      expect(value.connected, isTrue);
      value.dispose();
    },
  );
}
