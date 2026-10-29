import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../game/bot.dart';
import '../game/game.dart';
import '../preferences.dart';
import '../state/dama_controller.dart';
import '../widgets/common.dart';
import 'settings_dialog.dart';

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('پاشگەزبوونەوە'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

void showRules(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: .78,
    maxChildSize: .94,
    minChildSize: .4,
    builder: (context, scroll) => ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 30),
      children: [
        const SectionTitle(
          'با دامە بکەین',
          subtitle: 'یاساکانی دامەی کوردی / تورکی',
          icon: Icons.menu_book_outlined,
        ),
        const SizedBox(height: 22),
        for (final rule in const [
          (
            '١ · دەستپێک',
            'تەختە ٨×٨یە، هەر کەسێک ١٦ بەردی هەیە و سپی یەکەم جووڵە دەکات.',
          ),
          (
            '٢ · جووڵە',
            'بەردی ئاسایی یەک خانە بۆ پێشەوە، ڕاست یان چەپ دەجووڵێت. جووڵەی قطری یان بۆ دواوە نییە.',
          ),
          (
            '٣ · خواردن',
            'ئەگەر خواردن هەبێت، ناچارییە. دەبێت ئەو زنجیرەیە هەڵبژێریت کە زۆرترین بەرد دەخوات؛ هەر خانەی نیشانکراو بە نۆرە دەست لێ بدە.',
          ),
          (
            '٤ · دامە',
            'بەرد لە کۆتایی نۆرەکە لە ڕیزی بەرامبەر دەبێتە دامە. دامە بە چوار ئاراستە چەند خانەیەک دەجووڵێت؛ لە ناو زنجیرەی خواردندا ١٨٠ پلە ناگەڕێتەوە.',
          ),
          (
            '٥ · بردنەوە',
            'کە بەرامبەرەکەت بێ بەرد یان بێ جووڵە بێت، دەبەیتەوە. سێ جار دووبارەبوونی هەمان دۆخ یەکسانییە.',
          ),
          (
            '٦ · یەک بەرد',
            'یەک بەرد بەرامبەر یەک بەرد یەکسانییە؛ ئەگەر یەکێک دامە بێت و ئەوی تر ئاسایی، دامە دەباتەوە.',
          ),
          (
            '٧ · لەگەڵ هاوڕێکان',
            'ڕووم دروست بکە و لینک یان کۆدەکە بنێرە. هاوڕێکەت لە وێب، Android یان iPhone پەیوەست دەبێت. دوو کەسی تریش دەتوانن تماشاکەر بن.',
          ),
          (
            '٨ · پەیوەندی',
            'داخستنی ئەپ بە تەنیا وازهێنان نییە. بە کردنەوەی دووبارە هەمان ژوور دەگەڕێتەوە. دوگمەی دەرچوون لە یاریی چالاکدا بە وازهێنان هەژمار دەکرێت.',
          ),
        ]) ...[
          Text(rule.$1, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(rule.$2, style: const TextStyle(height: 1.9)),
          const SizedBox(height: 22),
        ],
      ],
    ),
  ),
);

void showSettings(
  BuildContext context,
  AppPreferences prefs,
  DamaController controller,
) => showWebSettings(context, prefs, controller);

class CoachDialog extends StatefulWidget {
  const CoachDialog({super.key, required this.controller});
  final DamaController controller;
  @override
  State<CoachDialog> createState() => _CoachDialogState();
}

class _CoachDialogState extends State<CoachDialog> {
  BotAnalysis? _result;
  bool _thinking = false;
  String? _error;
  String _signature = '';
  int _job = 0;

  String get _currentSignature {
    final g = widget.controller.game;
    return g == null
        ? ''
        : '${g.id}:${g.ply}:${g.turn.name}:${g.board.join(',')}:${widget.controller.canPlay}';
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sync);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    _job++;
    widget.controller.removeListener(_sync);
    super.dispose();
  }

  void _sync() {
    if (!mounted || _signature == _currentSignature) return;
    _signature = _currentSignature;
    _job++;
    setState(() {
      _result = null;
      _thinking = false;
      _error = null;
    });
    final game = widget.controller.game;
    if (game == null || !widget.controller.canPlay) return;
    unawaited(_analyze(game, _job));
  }

  Future<void> _analyze(GameState game, int job) async {
    setState(() => _thinking = true);
    try {
      final result = await compute(analyzeBot, <String, dynamic>{
        'board': game.board,
        'color': game.turn.name,
        'level': 'hard',
        'timeMs': 1200,
      });
      if (!mounted || job != _job || _signature != _currentSignature) return;
      setState(() {
        _result = result;
        _thinking = false;
      });
    } catch (_) {
      if (mounted && job == _job) {
        setState(() {
          _thinking = false;
          _error = 'پێشنیار ئامادە نەبوو. دووبارە هەوڵ بدەوە.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final move = _result?.move;
    return AlertDialog(
      icon: const Icon(Icons.auto_awesome_rounded),
      title: const Text('یارمەتیدەری ناوخۆ'),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'پێشنیارەکە تەنیا لەسەر ئەم ئامێرە دەردەکەوێت.',
              style: TextStyle(fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            if (_thinking)
              const Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              )
            else if (move != null) ...[
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  [
                    move.from,
                    ...move.path,
                  ].map(coordinate).join(move.captures.isEmpty ? ' → ' : ' × '),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'خواردن: ${kuNumber(move.captures.length)} · قووڵایی: ${kuNumber(_result!.depth)}',
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              const Text(
                'بەهێزترین جووڵەی دۆزراوە لەم گەڕانەدا.',
                style: TextStyle(fontSize: 11),
              ),
            ] else
              Text(
                _error ?? 'کاتێک نۆرەی تۆ بێت، پێشنیار ئامادە دەبێت.',
                textAlign: TextAlign.center,
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('داخستن'),
        ),
        if (_error != null)
          TextButton(
            onPressed: () {
              _signature = '';
              _sync();
            },
            child: const Text('دووبارە'),
          ),
        FilledButton(
          onPressed:
              move == null ||
                  !widget.controller.canPlay ||
                  _signature != _currentSignature
              ? null
              : () async {
                  final success = await widget.controller.play(move);
                  if (context.mounted && success) Navigator.pop(context);
                },
          child: const Text('ئەم جووڵەیە بکە'),
        ),
      ],
    );
  }
}
