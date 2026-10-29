import 'dart:convert';
import 'dart:io';

import 'package:dama_mobile/game/game.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'native rules match canonical web engine snapshots and complete turns',
    () {
      final fixtures =
          jsonDecode(File('test/fixtures/web_engine.json').readAsStringSync())
              as List;
      expect(fixtures.length, greaterThan(150));
      for (var index = 0; index < fixtures.length; index++) {
        final fixture = (fixtures[index] as Map).cast<String, dynamic>();
        final source = (fixture['game'] as Map).cast<String, dynamic>();
        final game = GameState.fromJson(source);
        expect(
          game.toJson(),
          source,
          reason: 'JSON round-trip at fixture $index',
        );
        expect(
          legalMoves(
            game.board,
            game.turn,
          ).map((move) => move.toJson()).toList(),
          fixture['legal'],
          reason: 'Ordered complete legal moves at fixture $index',
        );
        if (fixture['chosen'] != null) {
          final chosen = (fixture['chosen'] as Map).cast<String, dynamic>();
          final after = playMove(
            game,
            (chosen['from'] as num).toInt(),
            (chosen['path'] as List)
                .map((square) => (square as num).toInt())
                .toList(),
          );
          expect(
            after.toJson(),
            fixture['after'],
            reason:
                'Board, promotion, result, history and repetition at fixture $index',
          );
        } else {
          expect(fixture['after'], isNull);
        }
      }
    },
  );
}
