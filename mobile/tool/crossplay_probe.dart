// Real protocol smoke test: Dart's native API client vs a browser-shaped HTTP
// client, sharing disposable rooms on the unchanged Next.js backend.
// Run from mobile/: dart run tool/crossplay_probe.dart --server http://localhost:3000
// Optional shared room password comes only from DAMA_SITE_PASSWORD.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:dama_mobile/game/game.dart';
import 'package:dama_mobile/models/room.dart';
import 'package:dama_mobile/services/api.dart';

String _token() {
  final random = Random.secure();
  return base64Url
      .encode(List.generate(32, (_) => random.nextInt(256)))
      .replaceAll('=', '');
}

abstract class _Peer {
  Future<RoomSnapshot> create(String name, String password);
  Future<RoomSnapshot> join(
    String code,
    String name,
    String password, {
    bool spectator = false,
  });
  Future<RoomSnapshot> get(String code);
  Future<RoomSnapshot> act(String code, Map<String, dynamic> action);
  Future<void> leave(String code);
  void close();
}

class _NativePeer implements _Peer {
  _NativePeer(String server)
    : api = DamaApi(serverUrl: server, token: _token());
  final DamaApi api;
  @override
  Future<RoomSnapshot> create(String name, String password) =>
      api.createRoom(name: name, password: password);
  @override
  Future<RoomSnapshot> join(
    String code,
    String name,
    String password, {
    bool spectator = false,
  }) =>
      api.joinRoom(code, name: name, password: password, spectator: spectator);
  @override
  Future<RoomSnapshot> get(String code) => api.getRoom(code);
  @override
  Future<RoomSnapshot> act(String code, Map<String, dynamic> action) =>
      api.action(code, action);
  @override
  Future<void> leave(String code) => api.leaveRoom(code);
  @override
  void close() => api.close();
}

class _WebPeer implements _Peer {
  _WebPeer(this.server) : _identity = _token();
  final String server;
  final String _identity;
  final http.Client _client = http.Client();
  Future<Map<String, dynamic>> _request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final request = http.Request(method, Uri.parse('$server$path'));
    request.headers.addAll({
      'accept': 'application/json',
      'content-type': 'application/json',
      'origin': Uri.parse(server).origin,
      'x-player-token': _identity,
    });
    if (body != null) request.body = jsonEncode(body);
    final response = await (() async => http.Response.fromStream(
      await _client.send(request),
    ))().timeout(const Duration(seconds: 15));
    final decoded = jsonObject(jsonDecode(utf8.decode(response.bodyBytes)));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        decoded['error'] is String
            ? decoded['error'] as String
            : 'Web-shaped request failed.',
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }

  @override
  Future<RoomSnapshot> create(String name, String password) async =>
      RoomSnapshot.fromJson(
        await _request('POST', '/api/rooms', {
          'name': name,
          'password': password,
        }),
      );
  @override
  Future<RoomSnapshot> join(
    String code,
    String name,
    String password, {
    bool spectator = false,
  }) async => RoomSnapshot.fromJson(
    await _request('POST', '/api/rooms/${normalizeRoomCode(code)}', {
      'name': name,
      'password': password,
      'role': spectator ? 'spectator' : 'player',
    }),
  );
  @override
  Future<RoomSnapshot> get(String code) async => RoomSnapshot.fromJson(
    await _request('GET', '/api/rooms/${normalizeRoomCode(code)}'),
  );
  @override
  Future<RoomSnapshot> act(String code, Map<String, dynamic> action) async =>
      RoomSnapshot.fromJson(
        await _request(
          'PATCH',
          '/api/rooms/${normalizeRoomCode(code)}',
          action,
        ),
      );
  @override
  Future<void> leave(String code) async {
    await _request('PATCH', '/api/rooms/${normalizeRoomCode(code)}', {
      'type': 'leave',
    });
  }

  @override
  void close() => _client.close();
}

class _Seat {
  const _Seat(this.peer, this.code);
  final _Peer peer;
  final String code;
}

class _ProbeFailure implements Exception {
  const _ProbeFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class _Probe {
  _Probe(this.server, this.password);
  final String server;
  final String password;
  final List<_Peer> _peers = [];
  final List<_Seat> _seats = [];
  final Set<String> checks = {};
  int assertions = 0, roomsCreated = 0, cleanupLeft = 0, cleanupFailed = 0;
  String? storageMode;
  _NativePeer native() {
    final peer = _NativePeer(server);
    _peers.add(peer);
    return peer;
  }

  _WebPeer web() {
    final peer = _WebPeer(server);
    _peers.add(peer);
    return peer;
  }

  void check(bool condition, String label) {
    if (!condition) throw _ProbeFailure(label);
    assertions++;
    checks.add(label);
  }

  Future<void> rejected(
    Future<Object?> Function() action,
    int status,
    String label,
  ) async {
    try {
      await action();
    } on ApiException catch (error) {
      check(error.statusCode == status, label);
      return;
    }
    throw _ProbeFailure('$label: request unexpectedly succeeded.');
  }

  String canonical(RoomSnapshot room) => jsonEncode({
    'id': room.game.id,
    'board': room.game.board,
    'turn': room.game.turn.name,
    'ply': room.game.ply,
    'winner': room.game.winner,
    'reason': room.game.reason,
    'lastMove': room.game.lastMove?.toJson(),
  });
  Map<String, dynamic> moveAction(GameState game, DamaMove move) => {
    'type': 'move',
    'from': move.from,
    'path': move.path,
    'ply': game.ply,
    'gameId': game.id,
  };

  Future<void> run() async {
    final nativeWhite = native(), webBlack = web();
    final status = await nativeWhite.api.getStatus();
    storageMode = status.mode;
    check(status.onlineAvailable, 'server-ready');
    if (status.passwordRequired && password.isEmpty) {
      throw const _ProbeFailure(
        'This server requires DAMA_SITE_PASSWORD in the environment.',
      );
    }
    await exercise(nativeWhite, webBlack, 'native-create-web-join');
    await exercise(web(), native(), 'web-create-native-join');
  }

  Future<void> exercise(_Peer white, _Peer black, String direction) async {
    final created = await white.create('Probe White', password);
    _seats.add(_Seat(white, created.code));
    roomsCreated++;
    final joined = await black.join(created.code, 'Probe Black', password);
    _seats.add(_Seat(black, created.code));
    final code = created.code;
    check(
      created.self?.color == PlayerColor.white &&
          joined.self?.color == PlayerColor.black &&
          joined.started,
      direction,
    );
    final whiteId = created.me, blackId = joined.me;

    final observer = native(), observerTwo = web();
    final observed = await observer.join(
      code,
      'Probe Spectator One',
      password,
      spectator: true,
    );
    _seats.add(_Seat(observer, code));
    final fourth = await observerTwo.join(
      code,
      'Probe Spectator Two',
      password,
      spectator: true,
    );
    _seats.add(_Seat(observerTwo, code));
    check(
      observed.self?.role == 'spectator' && fourth.members.length == 4,
      'spectator-join',
    );
    final extra = native();
    await rejected(
      () => extra.join(code, 'Probe Fifth', password, spectator: true),
      409,
      'four-member-cap',
    );

    final before = await white.get(code);
    final firstMove = legalMoves(before.game.board, PlayerColor.white).first;
    final firstAction = moveAction(before.game, firstMove);
    await rejected(
      () => observer.act(code, firstAction),
      403,
      'spectator-cannot-move',
    );
    final first = await white.act(code, firstAction);
    final predictedWhite = playMove(
      before.game,
      firstMove.from,
      firstMove.path,
    );
    check(
      first.game.ply == 1 &&
          first.game.turn == PlayerColor.black &&
          jsonEncode(first.game.board) == jsonEncode(predictedWhite.board),
      'white-move-matches-native-rules',
    );

    final secondMove = legalMoves(first.game.board, PlayerColor.black).first;
    final second = await black.act(code, moveAction(first.game, secondMove));
    final predictedBlack = playMove(
      first.game,
      secondMove.from,
      secondMove.path,
    );
    check(
      second.game.ply == 2 &&
          second.game.turn == PlayerColor.white &&
          jsonEncode(second.game.board) == jsonEncode(predictedBlack.board),
      'black-move-matches-native-rules',
    );
    final whiteView = await white.get(code),
        blackView = await black.get(code),
        spectatorView = await observer.get(code);
    check(
      canonical(whiteView) == canonical(blackView) &&
          canonical(whiteView) == canonical(spectatorView),
      'identical-cross-client-state',
    );
    await rejected(
      () => white.act(code, firstAction),
      409,
      'stale-move-rejected',
    );
    check((await white.get(code)).game.ply == 2, 'stale-move-not-replayed');

    await observer.act(code, {
      'type': 'message',
      'text': 'سڵاو · crossplay probe',
      'name': 'Spoofed',
      'memberId': whiteId,
    });
    final chatWhite = await white.get(code), chatBlack = await black.get(code);
    final message = chatWhite.messages.last;
    check(
      message.memberId == observed.me &&
          message.name == 'Probe Spectator One' &&
          message.text == 'سڵاو · crossplay probe',
      'server-authorized-spectator-chat',
    );
    check(
      chatBlack.messages.last.id == message.id,
      'cross-client-chat-delivery',
    );

    final offered = await white.act(code, {
      'type': 'draw',
      'gameId': second.game.id,
    });
    check(offered.drawOffer == 'white', 'draw-offer-shared');
    final drawn = await black.act(code, {
      'type': 'draw',
      'gameId': second.game.id,
    });
    check(
      drawn.game.winner == 'draw' &&
          drawn.game.reason == 'agreement' &&
          drawn.results.where((item) => item.gameId == second.game.id).length ==
              1 &&
          drawn.results.last.winnerId == null,
      'agreed-draw-recorded-once',
    );
    await white.act(code, {'type': 'rematch', 'gameId': second.game.id});
    final rematch = await black.act(code, {
      'type': 'rematch',
      'gameId': second.game.id,
    });
    check(
      rematch.game.id != second.game.id &&
          rematch.game.ply == 0 &&
          rematch.game.winner == null,
      'agreed-rematch',
    );
    check(
      rematch.members.where((member) => member.id == whiteId).single.role ==
              'black' &&
          rematch.members.where((member) => member.id == blackId).single.role ==
              'white',
      'rematch-swaps-colors',
    );

    // The original white peer now owns black. Its resignation awards the
    // original black peer by stable member ID, regardless of current color.
    final resigned = await white.act(code, {
      'type': 'resign',
      'gameId': rematch.game.id,
    });
    check(
      resigned.game.winner == 'white' &&
          resigned.results.last.winnerId == blackId &&
          resigned.winsFor(blackId) == 1 &&
          resigned.winsFor(whiteId) == 0 &&
          resigned.draws == 1,
      'stable-member-score-after-color-swap',
    );
    final finalWhite = await white.get(code),
        finalBlack = await black.get(code);
    check(
      canonical(finalWhite) == canonical(finalBlack) &&
          finalWhite.results.length == 2 &&
          finalBlack.results.last.winnerId == blackId,
      'final-cross-client-result',
    );
  }

  Future<void> cleanup() async {
    for (final seat in _seats.reversed) {
      try {
        await seat.peer.leave(seat.code);
        cleanupLeft++;
      } on ApiException catch (error) {
        if (error.sessionMissing) {
          cleanupLeft++;
        } else {
          cleanupFailed++;
        }
      } catch (_) {
        cleanupFailed++;
      }
    }
    for (final peer in _peers) {
      peer.close();
    }
  }
}

Future<void> main(List<String> args) async {
  var server = 'http://localhost:3000';
  _Probe? probe;
  Object? failure;
  try {
    for (var i = 0; i < args.length; i++) {
      if (args[i] == '--server' && i + 1 < args.length) {
        server = args[++i];
      } else if (args[i].startsWith('--server=')) {
        server = args[i].substring('--server='.length);
      } else {
        throw const _ProbeFailure(
          'Usage: dart run tool/crossplay_probe.dart [--server http://localhost:3000]',
        );
      }
    }
    server = normalizeServerUrl(server);
    probe = _Probe(server, Platform.environment['DAMA_SITE_PASSWORD'] ?? '');
    await probe.run();
  } catch (error) {
    failure = error;
  } finally {
    await probe?.cleanup();
  }
  final success = failure == null && probe != null && probe.cleanupFailed == 0;
  stdout.writeln(
    jsonEncode({
      'ok': success,
      'server': server,
      'storageMode': probe?.storageMode,
      'rooms': probe?.roomsCreated ?? 0,
      'assertions': probe?.assertions ?? 0,
      'checks': probe?.checks.toList() ?? [],
      'cleanup': {
        'left': probe?.cleanupLeft ?? 0,
        'failed': probe?.cleanupFailed ?? 0,
      },
      if (failure != null)
        'error': failure is ApiException ? failure.message : failure.toString(),
    }),
  );
  if (!success) exitCode = 1;
}
