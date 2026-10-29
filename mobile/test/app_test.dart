import 'dart:convert';

import 'package:dama_mobile/app.dart';
import 'package:dama_mobile/game/bot.dart';
import 'package:dama_mobile/game/game.dart';
import 'package:dama_mobile/preferences.dart';
import 'package:dama_mobile/services/api.dart';
import 'package:dama_mobile/services/session_store.dart';
import 'package:dama_mobile/state/dama_controller.dart';
import 'package:dama_mobile/widgets/board_focus.dart';
import 'package:dama_mobile/widgets/dama_board.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<DamaController> controller() async {
    final c = DamaController(
      api: DamaApi(
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({'mode': 'redis', 'passwordRequired': false}),
            200,
          ),
        ),
      ),
      store: MemorySessionStore(),
      autoPoll: false,
      observeLifecycle: false,
      botRunner: (board, color, level) async =>
          chooseBotMove(board, color, BotLevel.easy, seed: 42),
    );
    await c.initialize();
    return c;
  }

  testWidgets(
    'phone lobby starts native solo game; move, undo and board-only view stay live',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = await controller();
      final prefs = AppPreferences();
      await tester.pumpWidget(DamaApp(controller: c, preferences: prefs));
      await tester.pumpAndSettle();
      expect(find.text('ڕوومێک دروست بکە'), findsOneWidget);
      await tester.ensureVisible(find.text('لەگەڵ بۆت'));
      await tester.tap(find.text('لەگەڵ بۆت'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('یاری لەگەڵ بۆت دەست پێ بکە'));
      await tester.tap(find.text('یاری لەگەڵ بۆت دەست پێ بکە'));
      await tester.pumpAndSettle();
      expect(find.byType(DamaBoard), findsOneWidget);
      expect(c.mode, GameMode.bot);
      await c.play(legalMoves(c.game!.board, c.game!.turn).first);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(c.game!.ply, 2);
      c.undo();
      await tester.pumpAndSettle();
      expect(c.game!.ply, 0);
      await tester.ensureVisible(find.text('تەنیا تەختە'));
      await tester.tap(find.text('تەنیا تەختە'));
      await tester.pumpAndSettle();
      expect(find.byType(BoardFocus), findsOneWidget);
      await c.play(legalMoves(c.game!.board, c.game!.turn).first);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(c.game!.ply, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
      prefs.dispose();
    },
  );

  testWidgets(
    'compact phone and enlarged text keep lobby and settings usable',
    (tester) async {
      final originalErrorHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        debugPrint(details.toString());
        originalErrorHandler?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalErrorHandler);
      tester.view.physicalSize = const Size(320, 700);
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = await controller();
      final prefs = AppPreferences();
      await tester.pumpWidget(DamaApp(controller: c, preferences: prefs));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('ڕێکخستنەکان'));
      await tester.pumpAndSettle();
      expect(find.text('بە شێوەی خۆت یاری بکە'), findsOneWidget);
      await tester.tap(find.text('شەو'));
      await tester.pumpAndSettle();
      expect(prefs.dark, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
      prefs.dispose();
    },
  );
}
