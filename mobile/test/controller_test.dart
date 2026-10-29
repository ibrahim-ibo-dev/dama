import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:dama_mobile/game/bot.dart';
import 'package:dama_mobile/game/game.dart';
import 'package:dama_mobile/services/api.dart';
import 'package:dama_mobile/services/session_store.dart';
import 'package:dama_mobile/state/dama_controller.dart';

const code = 'ABCDEFG234';
Map<String, dynamic> roomJson({
  String code = code,
  int revision = 0,
  GameState? game,
}) => {
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
  'game': (game ?? newGame('game-1')).toJson(),
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
typedef Handler = Future<http.Response> Function(http.Request request);
DamaController controller(
  Handler handler, {
  MemorySessionStore? store,
  BotRunner? botRunner,
  bool autoPoll = false,
  Duration pollInterval = const Duration(seconds: 2),
}) => DamaController(
  api: DamaApi(
    client: MockClient(
      (request) async => request.url.path == '/api/status'
          ? response({'mode': 'redis', 'passwordRequired': false})
          : handler(request),
    ),
    serverUrl: 'https://dama.example',
  ),
  store: store ?? MemorySessionStore(),
  autoPoll: autoPoll,
  pollInterval: pollInterval,
  observeLifecycle: false,
  botRunner: botRunner,
);
Future<void> enter(DamaController value) async {
  await value.initialize();
  value.setName('ئارام');
  expect(await value.createRoom(), true);
}

Map<String, dynamic> body(http.Request request) =>
    (jsonDecode(request.body) as Map).cast<String, dynamic>();

void main() {
  test('reconnect restores server, secure identity, room and role', () async {
    final store = MemorySessionStore(
      values: {
        'dama.server': 'https://saved.example',
        'dama.room': code,
        'dama.name': 'ئارام',
      },
      tokens: {'https://saved.example': 's' * 43},
    );
    final value = controller((request) async {
      expect(request.url.host, 'saved.example');
      expect(request.headers['x-player-token'], 's' * 43);
      return response(roomJson());
    }, store: store);
    addTearDown(value.dispose);
    await value.initialize();
    expect(value.mode, GameMode.online);
    expect(value.room?.code, code);
    expect(value.myColor, PlayerColor.white);
    expect(value.name, 'ئارام');
    expect(value.serverUrl, 'https://saved.example');
    expect(value.canPlay, true);
    expect(store.values.values.contains('s' * 43), false);
  });

  test('switching server uses a different secure identity', () async {
    final seenTokens = <String>[];
    final store = MemorySessionStore();
    final api = DamaApi(
      serverUrl: 'https://first.example',
      client: MockClient((request) async {
        seenTokens.add(request.headers['x-player-token']!);
        return response({'mode': 'redis', 'passwordRequired': false});
      }),
    );
    final value = DamaController(
      api: api,
      store: store,
      autoPoll: false,
      observeLifecycle: false,
    );
    addTearDown(value.dispose);
    await value.initialize();
    expect(await value.setServerUrl('https://second.example'), true);
    expect(seenTokens.length, 2);
    expect(seenTokens[0], isNot(seenTokens[1]));
    expect(store.tokens.length, 2);
    expect(store.values['dama.server'], 'https://second.example');
  });

  test(
    'only one move mutation is sent while the first one is pending',
    () async {
      final pending = Completer<http.Response>();
      var moveRequests = 0;
      final original = newGame('game-1');
      final value = controller((request) async {
        if (request.method == 'POST') return response(roomJson());
        if (body(request)['type'] == 'move') {
          moveRequests++;
          return pending.future;
        }
        return response(roomJson());
      });
      addTearDown(value.dispose);
      await enter(value);
      final move = legalMoves(original.board, PlayerColor.white).first;
      final first = value.play(move);
      expect(value.busy, true);
      expect(await value.play(move), false);
      pending.complete(
        response(
          roomJson(revision: 1, game: playMove(original, move.from, move.path)),
        ),
      );
      expect(await first, true);
      expect(moveRequests, 1);
      expect(value.game?.ply, 1);
      expect(value.busy, false);
    },
  );

  test('late chat response cannot restore a room after leaving', () async {
    final pending = Completer<http.Response>();
    final value = controller((request) async {
      if (request.method == 'POST') return response(roomJson());
      final type = body(request)['type'];
      if (type == 'message') return pending.future;
      if (type == 'leave') return response({'left': true});
      return response(roomJson());
    });
    addTearDown(value.dispose);
    await enter(value);
    final sent = value.sendMessage('سڵاو');
    expect(value.chatBusy, true);
    expect(await value.leave(), true);
    pending.complete(response(roomJson(revision: 1)));
    expect(await sent, false);
    expect(value.room, null);
    expect(value.mode, GameMode.lobby);
    expect(value.busy, false);
    expect(value.chatBusy, false);
  });

  test(
    'late refresh from an earlier room cannot replace a newer room',
    () async {
      final pending = Completer<http.Response>();
      var entries = 0;
      final value = controller((request) async {
        if (request.method == 'POST') {
          return response(roomJson(code: entries++ == 0 ? code : 'BCDEFGH234'));
        }
        final type = body(request)['type'];
        if (type == 'heartbeat') return pending.future;
        if (type == 'leave') return response({'left': true});
        return response(roomJson());
      });
      addTearDown(value.dispose);
      await enter(value);
      final refresh = value.refresh();
      expect(await value.leave(), true);
      expect(await value.createRoom(), true);
      pending.complete(response(roomJson(revision: 99)));
      await refresh;
      expect(value.room?.code, 'BCDEFGH234');
      expect(value.room?.revision, 0);
    },
  );

  test('expired rooms become offline but can always be left locally', () async {
    final value = controller(
      (request) async => request.method == 'POST'
          ? response(roomJson())
          : response({'error': 'ڕوومەکە نەدۆزرایەوە.'}, 404),
    );
    addTearDown(value.dispose);
    await enter(value);
    await value.refresh();
    expect(value.connected, false);
    expect(value.sessionExpired, true);
    expect(value.canPlay, false);
    expect(await value.leave(), true);
    expect(value.room, null);
    expect(value.error, null);
  });

  test(
    'foreground lifecycle pauses polling and resumes with a heartbeat',
    () async {
      var calls = 0;
      final resumed = Completer<void>();
      final value = controller(
        (request) async {
          if (request.method == 'POST') return response(roomJson());
          calls++;
          if (!resumed.isCompleted) resumed.complete();
          return response(roomJson(revision: calls));
        },
        autoPoll: true,
        pollInterval: const Duration(milliseconds: 10),
      );
      addTearDown(value.dispose);
      await enter(value);
      value.setForeground(false);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(calls, 0);
      value.setForeground(true);
      await resumed.future;
      value.setForeground(false);
      final stoppedAt = calls;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(calls, stoppedAt);
    },
  );

  test('hotseat supports both colors, undo and a local resignation', () async {
    final value = controller((_) async => response(roomJson()));
    addTearDown(value.dispose);
    await value.initialize();
    value.startHotseat();
    final firstId = value.game!.id;
    final move = legalMoves(value.game!.board, PlayerColor.white).first;
    expect(await value.play(move), true);
    expect(value.game?.turn, PlayerColor.black);
    expect(value.canPlay, true);
    value.undo();
    expect(value.game?.ply, 0);
    expect(value.game?.turn, PlayerColor.white);
    expect(await value.resign(), true);
    expect(value.game?.winner, 'black');
    expect(await value.rematch(), true);
    expect(value.game?.winner, null);
    expect(value.game?.id, isNot(firstId));
  });

  test(
    'undo invalidates a pending bot analysis and never applies its late move',
    () async {
      final pending = Completer<BotAnalysis>(), started = Completer<Board>();
      final value = controller(
        (_) async => response(roomJson()),
        botRunner: (board, color, level) async {
          started.complete(board);
          return pending.future;
        },
      );
      addTearDown(value.dispose);
      await value.initialize();
      value.startSolo(level: BotLevel.hard);
      expect(
        await value.play(
          legalMoves(value.game!.board, PlayerColor.white).first,
        ),
        true,
      );
      final analyzed = await started.future;
      expect(value.botThinking, true);
      expect(value.canPlay, false);
      value.undo();
      pending.complete(
        BotAnalysis(
          move: legalMoves(analyzed, PlayerColor.black).first,
          score: 0,
          depth: 1,
          nodes: 1,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(value.game?.ply, 0);
      expect(value.game?.turn, PlayerColor.white);
      expect(value.botThinking, false);
      expect(value.canPlay, true);
    },
  );

  test(
    'solo bot replies and undo restores the complete human/bot round',
    () async {
      final finished = Completer<void>();
      final value = controller(
        (_) async => response(roomJson()),
        botRunner: (board, color, level) async => BotAnalysis(
          move: legalMoves(board, color).first,
          score: 0,
          depth: 1,
          nodes: 1,
        ),
      );
      addTearDown(value.dispose);
      await value.initialize();
      value.startSolo();
      value.addListener(() {
        if (value.game?.ply == 2 && !finished.isCompleted) finished.complete();
      });
      expect(
        await value.play(
          legalMoves(value.game!.board, PlayerColor.white).first,
        ),
        true,
      );
      await finished.future;
      expect(value.game?.turn, PlayerColor.white);
      expect(value.myColor, PlayerColor.white);
      value.undo();
      expect(value.game?.ply, 0);
      expect(value.canUndo, false);
    },
  );
}
