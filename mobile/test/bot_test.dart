import 'package:dama_mobile/game/bot.dart';
import 'package:dama_mobile/game/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

Board boardWith(Map<int, int> pieces) {
  final board = List<int>.filled(64, 0);
  pieces.forEach((square, piece) => board[square] = piece);
  return board;
}

void main() {
  test('each difficulty chooses a legal complete turn for either color', () {
    final board = initialBoard(), original = List<int>.of(initialBoard());
    for (final color in PlayerColor.values) {
      for (final level in BotLevel.values) {
        final analysis = chooseBotMove(
          board,
          color,
          level,
          timeMs: 25,
          seed: 23,
        );
        expect(analysis.move, isNotNull);
        expect(legalMoves(board, color), contains(analysis.move));
        expect(analysis.nodes, greaterThan(0));
        final next = playMove(
          newGame('bot-test').copyWith(board: board, turn: color),
          analysis.move!.from,
          analysis.move!.path,
        );
        expect(next.ply, 1);
      }
    }
    expect(board, original);
  });

  test(
    'all levels obey mandatory maximum captures and return the full chain',
    () {
      final board = boardWith({48: 1, 40: -1, 24: -1, 54: 1, 46: -1});
      for (final level in BotLevel.values) {
        final analysis = chooseBotMove(
          board,
          PlayerColor.white,
          level,
          seed: 17,
        );
        expect(analysis.move?.from, 48);
        expect(analysis.move?.path, [32, 16]);
        expect(analysis.move?.captures, [40, 24]);
      }
    },
  );

  test(
    'search avoids two immediate capture traps when one safe move exists',
    () {
      final board = boardWith({35: 1, 19: -1, 28: -1, 7: -1});
      for (final level in [BotLevel.medium, BotLevel.hard]) {
        final result = chooseBotMove(
          board,
          PlayerColor.white,
          level,
          timeMs: 160,
          seed: 5,
        );
        expect(result.move?.from, 35);
        expect(result.move?.path, [34]);
        expect(result.depth, greaterThanOrEqualTo(2));
      }
    },
  );

  test('search values promotion and capturing kings over ordinary men', () {
    final promotion = chooseBotMove(
      boardWith({8: 1, 47: -1, 55: -1}),
      PlayerColor.white,
      BotLevel.medium,
      timeMs: 100,
      seed: 19,
    );
    expect(promotion.move?.path, [0]);
    final capture = chooseBotMove(
      boardWith({43: 1, 35: -2, 44: -1, 7: -1}),
      PlayerColor.white,
      BotLevel.hard,
      timeMs: 120,
      seed: 19,
    );
    expect(capture.move?.captures, [35]);
  });

  test(
    'terminal, missing-piece, single-piece and blocked states have no move',
    () {
      expect(
        chooseBotMove(boardWith({}), PlayerColor.white, BotLevel.hard).move,
        isNull,
      );
      expect(
        chooseBotMove(
          boardWith({40: 1}),
          PlayerColor.white,
          BotLevel.medium,
        ).move,
        isNull,
      );
      final blocked = boardWith({
        40: 1,
        56: -1,
        57: -1,
        58: -1,
        59: -1,
        60: -1,
        61: -1,
        62: -1,
        63: -1,
      });
      final result = chooseBotMove(blocked, PlayerColor.black, BotLevel.hard);
      expect(result.move, isNull);
      expect(result.score, lessThan(-90000));
      blocked[40] = 0;
      expect(
        chooseBotMove(blocked, PlayerColor.black, BotLevel.hard).score,
        greaterThan(90000),
      );
      final draw = chooseBotMove(
        boardWith({40: 1, 15: -1}),
        PlayerColor.white,
        BotLevel.hard,
      );
      expect(draw.move, isNull);
      expect(draw.score, 0);
      final kingWins = chooseBotMove(
        boardWith({40: 2, 15: -1}),
        PlayerColor.white,
        BotLevel.hard,
      );
      expect(kingWins.move, isNull);
      expect(kingWins.score, greaterThan(90000));
    },
  );

  test('easy seed repeats exactly and varies choices across seeds', () {
    final board = initialBoard();
    final first = chooseBotMove(
      board,
      PlayerColor.white,
      BotLevel.easy,
      seed: 42,
    );
    final repeated = chooseBotMove(
      board,
      PlayerColor.white,
      BotLevel.easy,
      seed: 42,
    );
    expect(repeated.toJson(), first.toJson());
    // Reference output of the web bot's JS-compatible seeded generator.
    expect(first.move?.from, 43);
    expect(first.move?.path, [35]);
    expect(first.score, -20);
    final choices = <DamaMove>{};
    for (var seed = 0; seed < 16; seed++) {
      choices.add(
        chooseBotMove(
          board,
          PlayerColor.white,
          BotLevel.easy,
          seed: seed,
        ).move!,
      );
    }
    expect(choices.length, greaterThan(3));
  });

  test('tiny and zero budgets retain a legal fallback promptly', () {
    final board = initialBoard(), clock = Stopwatch()..start();
    for (final timeMs in [0, 1, 10]) {
      final analysis = chooseBotMove(
        board,
        PlayerColor.white,
        BotLevel.hard,
        timeMs: timeMs,
        seed: 9,
      );
      expect(analysis.move, isNotNull);
      expect(legalMoves(board, PlayerColor.white), contains(analysis.move));
      expect(analysis.nodes, lessThanOrEqualTo(100000));
      if (timeMs == 0) expect(analysis.depth, 0);
    }
    expect(clock.elapsedMilliseconds, lessThan(1000));
  });

  test(
    'compute entry point and analysis JSON survive isolate transfer',
    () async {
      final result =
          await compute<Map<String, dynamic>, BotAnalysis>(analyzeBot, {
            'board': initialBoard(),
            'color': 'black',
            'level': 'medium',
            'timeMs': 30,
            'seed': 42,
          });
      expect(result.move, isNotNull);
      expect(
        legalMoves(initialBoard(), PlayerColor.black),
        contains(result.move),
      );
      expect(BotAnalysis.fromJson(result.toJson()).toJson(), result.toJson());
    },
  );
}
