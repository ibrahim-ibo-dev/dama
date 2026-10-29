import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'preferences.dart';
import 'screens/dialogs.dart';
import 'screens/game_screen.dart';
import 'screens/lobby_screen.dart';
import 'state/dama_controller.dart';
import 'theme.dart';
import 'widgets/web_brand.dart';

class DamaApp extends StatefulWidget {
  const DamaApp({super.key, this.controller, this.preferences});
  final DamaController? controller;
  final AppPreferences? preferences;
  @override
  State<DamaApp> createState() => _DamaAppState();
}

class _DamaAppState extends State<DamaApp> {
  late final DamaController c;
  late final AppPreferences prefs;
  Timer? _hold;
  bool _confirming = false;
  String? _lastGame, _lastWinner;
  int _lastPly = 0;
  @override
  void initState() {
    super.initState();
    c = widget.controller ?? DamaController();
    prefs = widget.preferences ?? AppPreferences();
    c.addListener(_feedback);
    if (widget.controller == null) unawaited(c.initialize());
    if (widget.preferences == null) unawaited(prefs.load());
  }

  void _feedback() {
    final game = c.game;
    if (game == null) {
      _lastGame = null;
      return;
    }
    if (_lastGame == game.id &&
        (game.ply != _lastPly || game.winner != _lastWinner)) {
      if (prefs.sound) unawaited(SystemSound.play(SystemSoundType.click));
      if (prefs.vibration) unawaited(HapticFeedback.lightImpact());
    }
    _lastGame = game.id;
    _lastPly = game.ply;
    _lastWinner = game.winner;
  }

  @override
  void dispose() {
    _hold?.cancel();
    c.removeListener(_feedback);
    if (widget.controller == null) c.dispose();
    if (widget.preferences == null) prefs.dispose();
    super.dispose();
  }

  Future<void> _leave(BuildContext context) async {
    if (_confirming || c.busy) return;
    _confirming = true;
    final active =
        c.mode == GameMode.online &&
        c.room!.started &&
        c.game?.winner == null &&
        c.role != 'spectator';
    final yes = await confirmAction(
      context,
      title: 'لە ڕوومەکە دەردەچیت؟',
      message: active
          ? 'دەرچوون لەم یارییە بە وازهێنان هەژمار دەکرێت. داخستنی ئەپ بە تەنیا وازهێنان نییە.'
          : 'دەگەڕێیتەوە بۆ پەڕەی سەرەتا.',
      action: 'دەرچوون',
    );
    _confirming = false;
    if (yes) await c.leave();
  }

  void _holdStart(BuildContext context) {
    _hold?.cancel();
    if (c.mode == GameMode.lobby) return;
    _hold = Timer(const Duration(milliseconds: 1500), () async {
      await prefs.update(coachEnabled: true);
      if (context.mounted && c.game != null) {
        unawaited(
          showDialog<void>(
            context: context,
            builder: (_) => CoachDialog(controller: c),
          ),
        );
      }
    });
  }

  PreferredSizeWidget _header(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final margin = wide
        ? (MediaQuery.sizeOf(context).width * .051).clamp(19.0, 72.0)
        : 19.0;
    return PreferredSize(
      preferredSize: Size.fromHeight(wide ? 108 : 86),
      child: SafeArea(
        bottom: false,
        child: Container(
          margin: EdgeInsets.symmetric(horizontal: margin),
          constraints: BoxConstraints(minHeight: wide ? 108 : 86),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          child: Row(
            children: [
              const Expanded(child: WebBrand()),
              if (MediaQuery.sizeOf(context).width > 920) ...[
                Text(
                  '✳',
                  style: TextStyle(
                    fontFamily: 'serif',
                    fontSize: 27,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
                const SizedBox(width: 10),
                const Text('کاتێک بۆ هاوڕێکان', style: TextStyle(fontSize: 11)),
                const SizedBox(width: 13),
                const Text('·', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 13),
                Text(
                  'یارییەکی کۆن، بیرەوەرییەکی نوێ',
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: .55),
                  ),
                ),
                const Spacer(),
              ],
              if (wide)
                TextButton.icon(
                  onPressed: () => showRules(context),
                  icon: const Icon(Icons.help_outline_rounded, size: 16),
                  label: const Text(
                    'چۆن یاری بکەم؟',
                    style: TextStyle(fontSize: 11),
                  ),
                )
              else
                IconButton(
                  tooltip: 'یاساکانی دامە',
                  onPressed: () => showRules(context),
                  icon: const Icon(Icons.help_outline_rounded, size: 19),
                ),
              IconButton(
                tooltip: prefs.dark ? 'ڕووکاری ڕۆژ' : 'ڕووکاری شەو',
                onPressed: () => prefs.update(dark: !prefs.dark),
                icon: Icon(
                  prefs.dark
                      ? Icons.light_mode_outlined
                      : Icons.dark_mode_outlined,
                  size: 19,
                ),
              ),
              IconButton(
                tooltip: 'ڕێکخستنەکان',
                onPressed: () => showSettings(context, prefs, c),
                icon: const Icon(Icons.tune_rounded, size: 19),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _footer(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: .55);
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 19),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Theme.of(context).colorScheme.outline),
          ),
        ),
        child: Row(
          children: [
            Listener(
              onPointerDown: (_) => _holdStart(context),
              onPointerUp: (_) => _hold?.cancel(),
              onPointerCancel: (_) => _hold?.cancel(),
              child: Semantics(
                label: 'دامە',
                button: true,
                child: SizedBox(
                  width: 34,
                  height: 34,
                  child: Center(
                    child: Text(
                      '✳',
                      style: TextStyle(
                        fontFamily: 'serif',
                        fontSize: 23,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'بۆ ئەو کاتانەی پێکەوەین.',
                style: TextStyle(fontSize: 9, color: muted),
              ),
            ),
            if (wide) ...[
              Icon(Icons.verified_user_outlined, size: 13, color: muted),
              const SizedBox(width: 7),
              Text(
                'تایبەت بە تۆ و هاوڕێکانت',
                style: TextStyle(fontSize: 9, color: muted),
              ),
              const Spacer(),
            ],
            Text(
              'CLASSIC · PRIVATE BOARD',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: wide ? 8 : 6,
                letterSpacing: wide ? 1.6 : .8,
                color: muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([c, prefs]),
    builder: (context, _) => MaterialApp(
      title: 'دامە',
      debugShowCheckedModeBanner: false,
      theme: damaTheme(),
      darkTheme: damaTheme(dark: true),
      themeMode: prefs.dark ? ThemeMode.dark : ThemeMode.light,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: Builder(
        builder: (context) => PopScope(
          canPop: c.mode == GameMode.lobby,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && c.mode != GameMode.lobby) _leave(context);
          },
          child: Scaffold(
            appBar: _header(context),
            body: SafeArea(
              top: false,
              bottom: false,
              child: Column(
                children: [
                  if (c.error != null)
                    Container(
                      margin: const EdgeInsets.fromLTRB(19, 10, 19, 0),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.secondary.withValues(alpha: .10),
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).colorScheme.secondary.withValues(alpha: .25),
                        ),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              c.error!,
                              style: const TextStyle(fontSize: 11, height: 1.9),
                            ),
                          ),
                          if (!c.connected)
                            TextButton(
                              onPressed: c.refresh,
                              child: const Text(
                                'دووبارە',
                                style: TextStyle(fontSize: 10),
                              ),
                            ),
                          IconButton(
                            tooltip: 'داخستن',
                            onPressed: c.clearError,
                            icon: const Icon(Icons.close_rounded, size: 17),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: c.game == null
                        ? LobbyScreen(controller: c, preferences: prefs)
                        : GameScreen(
                            controller: c,
                            preferences: prefs,
                            onLeave: () => _leave(context),
                          ),
                  ),
                ],
              ),
            ),
            bottomNavigationBar: _footer(context),
          ),
        ),
      ),
    ),
  );
}
