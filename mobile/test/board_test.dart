import 'package:dama_mobile/game/game.dart';
import 'package:dama_mobile/theme.dart';
import 'package:dama_mobile/widgets/board_focus.dart';
import 'package:dama_mobile/widgets/dama_board.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Board boardWith(Map<int, int> pieces) {
  final board = List<int>.filled(64, 0);
  for (final entry in pieces.entries) {
    board[entry.key] = entry.value;
  }
  return board;
}

Widget boardHarness({
  required GameState game,
  required ValueChanged<DamaMove> onMove,
  bool canPlay = true,
  PlayerColor perspective = PlayerColor.white,
  bool coordinates = true,
  bool hints = true,
}) => MaterialApp(
  theme: damaTheme(),
  home: Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      body: Center(
        child: SizedBox.square(
          dimension: 400,
          child: DamaBoard(
            key: const ValueKey('test-board'),
            game: game,
            onMove: onMove,
            canPlay: canPlay,
            perspective: perspective,
            showCoordinates: coordinates,
            showLegalMoves: hints,
            reduceMotion: true,
          ),
        ),
      ),
    ),
  ),
);

Finder square(int value) => find.byKey(ValueKey('square-$value'));

void main() {
  testWidgets('captures preview locally and dispatch only the complete chain', (
    tester,
  ) async {
    final moves = <DamaMove>[];
    final game = newGame(
      'chain',
    ).copyWith(board: boardWith({48: 1, 40: -1, 24: -1}));
    await tester.pumpWidget(boardHarness(game: game, onMove: moves.add));
    await tester.tap(square(48));
    await tester.pump();
    expect(find.byKey(const ValueKey('target-32')), findsOneWidget);
    await tester.tap(square(32));
    await tester.pump();
    expect(moves, isEmpty);
    expect(find.byKey(const ValueKey('piece-at-32')), findsOneWidget);
    expect(find.byKey(const ValueKey('piece-at-40')), findsNothing);
    expect(find.byKey(const ValueKey('target-16')), findsOneWidget);
    expect(game.board[48], 1);
    expect(game.board[40], -1);
    await tester.tap(square(16));
    await tester.pump();
    expect(moves, [
      DamaMove(from: 48, path: [32, 16], captures: [40, 24]),
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('selection resets when play is disabled or game changes', (
    tester,
  ) async {
    final moves = <DamaMove>[];
    final game = newGame(
      'chain',
    ).copyWith(board: boardWith({48: 1, 40: -1, 24: -1}));
    await tester.pumpWidget(boardHarness(game: game, onMove: moves.add));
    await tester.tap(square(48));
    await tester.pump();
    await tester.tap(square(32));
    await tester.pump();
    await tester.pumpWidget(
      boardHarness(game: game, onMove: moves.add, canPlay: false),
    );
    expect(find.byKey(const ValueKey('piece-at-48')), findsOneWidget);
    expect(find.byKey(const ValueKey('target-16')), findsNothing);
    await tester.tap(square(16));
    await tester.pump();
    expect(moves, isEmpty);
    await tester.pumpWidget(boardHarness(game: game, onMove: moves.add));
    await tester.tap(square(48));
    await tester.pump();
    await tester.pumpWidget(
      boardHarness(
        game: game.copyWith(id: 'new-game'),
        onMove: moves.add,
      ),
    );
    expect(find.byKey(const ValueKey('target-32')), findsNothing);
    expect(tester.widget<Semantics>(square(48)).properties.selected, isFalse);
  });

  testWidgets('only pieces with a maximum capture can be selected', (
    tester,
  ) async {
    final game = newGame(
      'maximum',
    ).copyWith(board: boardWith({48: 1, 40: -1, 24: -1, 54: 1, 46: -1}));
    final moves = <DamaMove>[];
    await tester.pumpWidget(boardHarness(game: game, onMove: moves.add));
    await tester.tap(square(54));
    await tester.pump();
    expect(tester.widget<Semantics>(square(54)).properties.selected, isFalse);
    expect(find.byKey(const ValueKey('target-38')), findsNothing);
    await tester.tap(square(48));
    await tester.pump();
    expect(tester.widget<Semantics>(square(48)).properties.selected, isTrue);
    expect(find.byKey(const ValueKey('target-32')), findsOneWidget);
    expect(moves, isEmpty);
  });

  testWidgets('black perspective flips squares while RTL stays intrinsic LTR', (
    tester,
  ) async {
    final game = newGame('flipped');
    await tester.pumpWidget(boardHarness(game: game, onMove: (_) {}));
    expect(
      tester.getCenter(square(0)).dx,
      lessThan(tester.getCenter(square(63)).dx),
    );
    expect(
      tester.getCenter(square(0)).dy,
      lessThan(tester.getCenter(square(63)).dy),
    );
    await tester.pumpWidget(
      boardHarness(game: game, onMove: (_) {}, perspective: PlayerColor.black),
    );
    expect(
      tester.getCenter(square(63)).dx,
      lessThan(tester.getCenter(square(0)).dx),
    );
    expect(
      tester.getCenter(square(63)).dy,
      lessThan(tester.getCenter(square(0)).dy),
    );
    expect(
      tester.getCenter(find.byKey(const ValueKey('coordinate-top-h'))).dx,
      lessThan(
        tester.getCenter(find.byKey(const ValueKey('coordinate-top-a'))).dx,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'hiding coordinates and hints keeps dimensions and legal actions',
    (tester) async {
      final game = newGame('preferences');
      final moves = <DamaMove>[];
      await tester.pumpWidget(boardHarness(game: game, onMove: moves.add));
      final size = tester.getSize(find.byKey(const ValueKey('test-board')));
      await tester.pumpWidget(
        boardHarness(
          game: game,
          onMove: moves.add,
          coordinates: false,
          hints: false,
        ),
      );
      expect(find.byKey(const ValueKey('coordinate-top-a')), findsNothing);
      expect(tester.getSize(find.byKey(const ValueKey('test-board'))), size);
      await tester.tap(square(40));
      await tester.pump();
      expect(find.byKey(const ValueKey('target-32')), findsNothing);
      expect(
        tester.widget<Semantics>(square(32)).properties.label,
        contains('جووڵەی ڕێگەپێدراو'),
      );
      await tester.tap(square(32));
      await tester.pump();
      expect(moves.single, DamaMove(from: 40, path: [32]));
    },
  );

  testWidgets('board-only focus remains live and restores system overlays', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
    final game = ValueNotifier(newGame('focus'));
    addTearDown(game.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => BoardFocus(
                    listenable: game,
                    boardBuilder: (_) => DamaBoard(
                      game: game.value,
                      canPlay: false,
                      onMove: (_) {},
                      reduceMotion: true,
                    ),
                  ),
                ),
              ),
              child: const Text('Open board'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open board'));
    await tester.pumpAndSettle();
    expect(find.byType(BoardFocus), findsOneWidget);
    expect(
      calls.any(
        (call) =>
            call.method == 'SystemChrome.setEnabledSystemUIMode' &&
            call.arguments.toString().contains('immersiveSticky'),
      ),
      isTrue,
    );
    game.value = game.value.copyWith(board: boardWith({0: 2, 63: -2}), ply: 10);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('piece-at-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('piece-at-40')), findsNothing);
    await tester.tap(find.byTooltip('دەرچوون لە دۆخی تەنیا تەختە'));
    await tester.pumpAndSettle();
    expect(find.byType(BoardFocus), findsNothing);
    expect(find.text('Open board'), findsOneWidget);
    expect(
      calls.any(
        (call) =>
            call.method == 'SystemChrome.setEnabledSystemUIMode' &&
            call.arguments.toString().contains('edgeToEdge'),
      ),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
}
