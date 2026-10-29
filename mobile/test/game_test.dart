import 'dart:convert';

import 'package:dama_mobile/game/game.dart';
import 'package:flutter_test/flutter_test.dart';

Board boardWith(Map<int, int> pieces) {
  final board = List<int>.filled(64, 0);
  pieces.forEach((square, piece) => board[square] = piece);
  return board;
}

void main() {
  test('Turkish setup: sixteen men, empty back ranks and center', () {
    final board = initialBoard();
    expect(countPieces(board, PlayerColor.white), 16);
    expect(countPieces(board, PlayerColor.black), 16);
    for (final row in [0, 3, 4, 7]) {
      expect(board.sublist(row * 8, row * 8 + 8), everyElement(0));
    }
    expect(legalMoves(board, PlayerColor.white).length, 8);
    expect(coordinate(0), 'a8');
    expect(coordinate(63), 'h1');
  });

  test(
    'ordinary men move forward or sideways, never backward or diagonally',
    () {
      final white = legalMoves(
        boardWith({35: 1}),
        PlayerColor.white,
      ).map((move) => move.path.single).toList()..sort();
      final black = legalMoves(
        boardWith({35: -1}),
        PlayerColor.black,
      ).map((move) => move.path.single).toList()..sort();
      expect(white, [27, 34, 36]);
      expect(black, [34, 36, 43]);
    },
  );

  test(
    'capture is compulsory and only the globally longest chains survive',
    () {
      final board = boardWith({48: 1, 40: -1, 24: -1, 54: 1, 46: -1});
      final moves = legalMoves(board, PlayerColor.white);
      expect(moves.length, 1);
      expect(moves.single.from, 48);
      expect(moves.single.path, [32, 16]);
      expect(moves.single.captures, [40, 24]);
    },
  );

  test('a man turns sideways during a chain and captured men disappear', () {
    final board = boardWith({43: 1, 35: -1, 28: -1});
    final move = legalMoves(board, PlayerColor.white).single;
    expect(move.path, [27, 29]);
    final next = playMove(newGame('test').copyWith(board: board), 43, [27, 29]);
    expect(next.board[35], 0);
    expect(next.board[28], 0);
    expect(next.board[29], 1);
    expect(next.lastMove?.label, 'd3 × d5 × f5');
  });

  test('flying kings may choose any free square beyond the captured piece', () {
    final moves = legalMoves(boardWith({56: 2, 32: -1}), PlayerColor.white);
    final landings = moves.map((move) => move.path.single).toList()..sort();
    expect(landings, [0, 8, 16, 24]);
  });

  test('flying kings may not reverse 180 degrees between captures', () {
    final moves = legalMoves(
      boardWith({27: 2, 25: -1, 29: -1}),
      PlayerColor.white,
    );
    expect(moves.length, greaterThan(1));
    expect(moves.every((move) => move.captures.length == 1), isTrue);
  });

  test('promotion occurs only after the entire turn finishes', () {
    final board = boardWith({18: 1, 10: -1, 3: -1, 7: -1});
    final moves = legalMoves(board, PlayerColor.white);
    expect(moves.first.path, [2, 4]);
    expect(moves.first.captures.length, 2);
    final preview = previewMove(board, moves.first, 1);
    expect(preview[2], 1);
    final next = playMove(newGame('test').copyWith(board: board), 18, [2, 4]);
    expect(next.board[4], 2);
    expect(next.board[7], -1);
  });

  test(
    'partial chains and illegal moves are rejected without changing input',
    () {
      final game = newGame(
        'test',
      ).copyWith(board: boardWith({48: 1, 40: -1, 24: -1}));
      final before = jsonEncode(game.toJson());
      expect(() => playMove(game, 48, [32]), throwsA(isA<DamaRuleException>()));
      expect(() => playMove(game, 48, [49]), throwsA(isA<DamaRuleException>()));
      expect(jsonEncode(game.toJson()), before);
    },
  );

  test('capturing the final opponent wins and a blocked opponent loses', () {
    final capture = newGame('test').copyWith(board: boardWith({40: 1, 32: -1}));
    expect(playMove(capture, 40, [24]).winner, 'white');
    final blocked = newGame('test').copyWith(
      board: boardWith({
        40: 1,
        56: -1,
        57: -1,
        58: -1,
        59: -1,
        60: -1,
        61: -1,
        62: -1,
        63: -1,
      }),
    );
    final result = playMove(blocked, 40, [32]);
    expect(result.winner, 'white');
    expect(result.reason, 'blocked');
  });

  test('one equal-ranked piece each draws; a king beats a lone man', () {
    final equal = newGame('test').copyWith(board: boardWith({40: 1, 15: -1}));
    expect(playMove(equal, 40, [32]).winner, 'draw');
    final king = newGame('test').copyWith(board: boardWith({40: 2, 15: -1}));
    expect(playMove(king, 40, [32]).winner, 'white');
  });

  test('sideways repetition is recorded even for ordinary men', () {
    var game = newGame(
      'test',
    ).copyWith(board: boardWith({48: 1, 55: 1, 8: -1, 15: -1}));
    for (var cycle = 0; cycle < 3 && game.winner == null; cycle++) {
      for (final (from, to) in [(48, 49), (8, 9), (49, 48), (9, 8)]) {
        if (game.winner == null) game = playMove(game, from, [to]);
      }
    }
    expect(game.winner, 'draw');
    expect(game.reason, 'repetition');
  });

  test('game and move JSON round-trip with the exact server field names', () {
    var game = newGame('round-trip');
    game = playMove(game, 40, [32]);
    game = playMove(game, 16, [24]);
    game = playMove(game, 32, [16, 0]);
    final decoded = GameState.fromJson(
      jsonDecode(jsonEncode(game.toJson())) as Map<String, dynamic>,
    );
    expect(decoded.toJson(), game.toJson());
    expect(decoded.lastMove, DamaMove.fromJson(game.lastMove!.toJson()));
    expect(decoded.history.last.label, 'a4 × a6 × a8');
    final publicSnapshot = Map<String, dynamic>.of(game.toJson())
      ..remove('positions');
    expect(GameState.fromJson(publicSnapshot).positions, isEmpty);
  });

  test('model snapshots are defensive and nullable fields can be cleared', () {
    final board = initialBoard();
    final game = GameState(
      id: 'immutable',
      board: board,
      turn: PlayerColor.white,
      winner: 'draw',
      reason: 'agreement',
      lastMove: DamaMove(from: 40, path: [32]),
    );
    board[40] = 0;
    expect(game.board[40], 1);
    expect(() => game.board[40] = 0, throwsUnsupportedError);
    expect(() => game.positions['new'] = 1, throwsUnsupportedError);
    final cleared = game.copyWith(winner: null, reason: null, lastMove: null);
    expect(cleared.winner, isNull);
    expect(cleared.reason, isNull);
    expect(cleared.lastMove, isNull);
    expect(game.copyWith(ply: 7).winner, 'draw');
    expect(
      () => GameState(id: 'bad', board: [0], turn: PlayerColor.white),
      throwsFormatException,
    );
  });

  test('move history keeps the newest hundred turns', () {
    final game = newGame('history').copyWith(
      history: List.generate(
        100,
        (index) => MoveRecord(
          color: PlayerColor.white,
          label: 'old-$index',
          captures: 0,
        ),
      ),
    );
    final next = playMove(game, 40, [32]);
    expect(next.history.length, 100);
    expect(next.history.first.label, 'old-1');
    expect(next.history.last.label, 'a3 → a4');
  });

  test('zero-step previews preserve the board and out-of-range steps fail', () {
    final board = initialBoard();
    final move = legalMoves(board, PlayerColor.white).first;
    expect(previewMove(board, move, 0), board);
    expect(() => previewMove(board, move, 2), throwsRangeError);
  });
}
