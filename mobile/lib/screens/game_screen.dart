import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../game/bot.dart';
import '../game/game.dart';
import '../models/room.dart';
import '../preferences.dart';
import '../state/dama_controller.dart';
import '../widgets/board_focus.dart';
import '../widgets/common.dart';
import '../widgets/dama_board.dart';
import 'dialogs.dart';
import 'lobby_screen.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.controller,
    required this.preferences,
    required this.onLeave,
  });
  final DamaController controller;
  final AppPreferences preferences;
  final VoidCallback onLeave;
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  bool _flipped = false;
  DamaController get c => widget.controller;
  AppPreferences get prefs => widget.preferences;
  PlayerColor get perspective {
    final base = c.myColor ?? PlayerColor.white;
    return _flipped ? opposite(base) : base;
  }

  Widget _board(BuildContext context) {
    final game = c.game;
    if (game == null) {
      return const Center(child: Text('ژوورەکە داخراوە. بگەڕێوە بۆ سەرەتا.'));
    }
    return DamaBoard(
      game: game,
      canPlay: c.canPlay,
      perspective: perspective,
      onMove: (move) {
        c.play(move);
      },
      boardStyle: prefs.boardStyle,
      showCoordinates: prefs.coordinates,
      showLegalMoves: prefs.targets,
      reduceMotion: MediaQuery.disableAnimationsOf(context),
    );
  }

  Future<void> _focus() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => BoardFocus(
          listenable: Listenable.merge([c, prefs]),
          boardBuilder: _board,
        ),
      ),
    );
  }

  Future<void> _copyInvite() async {
    final code = c.room?.code;
    if (code == null) return;
    try {
      await Clipboard.setData(
        ClipboardData(text: '${c.serverUrl}/?room=$code'),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('لینکەکە کۆپی نەکرا؛ کۆدی ڕوومەکە بنووسە.'),
          ),
        );
      }
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('لینکی بانگهێشت کۆپی کرا.')));
    }
  }

  Future<void> _share(BuildContext buttonContext) async {
    final code = c.room?.code;
    if (code == null) return;
    final render = buttonContext.findRenderObject() as RenderBox?;
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: 'با دامە بکەین! کۆدی ڕووم: $code\n${c.serverUrl}/?room=$code',
          subject: 'بانگهێشتی دامە',
          sharePositionOrigin: render == null
              ? null
              : render.localToGlobal(Offset.zero) & render.size,
        ),
      );
    } catch (_) {
      await _copyInvite();
    }
  }

  String _playerName(PlayerColor color) {
    if (c.mode == GameMode.online) {
      return c.room!.members
              .where((m) => m.role == color.name)
              .firstOrNull
              ?.name ??
          'چاوەڕوانی هاوڕێ…';
    }
    if (c.mode == GameMode.bot) {
      return color == PlayerColor.white
          ? (c.name.isEmpty ? 'تۆ' : c.name)
          : 'بۆتی دامە';
    }
    return color == PlayerColor.white ? 'یاریزانی سپی' : 'یاریزانی ڕەش';
  }

  Widget _playerBar(PlayerColor color) {
    final game = c.game!;
    final active =
        game.winner == null && game.turn == color && (c.room?.started ?? true);
    final count = countPieces(game.board, color);
    final kings = game.board
        .where((p) => p.abs() == 2 && pieceColor(p) == color)
        .length;
    final member = c.room?.members
        .where((m) => m.role == color.name)
        .firstOrNull;
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: active ? theme.colorScheme.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: active
              ? theme.colorScheme.primary.withValues(alpha: .35)
              : theme.dividerColor.withValues(alpha: .10),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 35,
            height: 35,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: color == PlayerColor.white
                    ? [const Color(0xfffff1d6), const Color(0xffc99b65)]
                    : [const Color(0xff40594d), const Color(0xff122b24)],
              ),
              border: Border.all(color: const Color(0xffb58b5b), width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .13),
                  offset: const Offset(0, 2),
                  blurRadius: 3,
                ),
              ],
            ),
            child: Center(
              child: Container(
                width: 23,
                height: 23,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xffc5a177), width: .8),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _playerName(color),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                Text(
                  c.mode == GameMode.bot && color == PlayerColor.black
                      ? (c.botThinking
                            ? 'بیر دەکاتەوە…'
                            : levelName(c.botLevel))
                      : color == PlayerColor.white
                      ? 'سپی'
                      : 'ڕەش',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (member != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 10),
              child: Icon(
                Icons.circle,
                size: 7,
                color: member.isOnline()
                    ? const Color(0xff509d76)
                    : Colors.grey,
              ),
            ),
          if (active)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 10),
              child: Icon(
                Icons.play_arrow_rounded,
                color: theme.colorScheme.primary,
                size: 20,
              ),
            ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${kuNumber(count)} بەرد',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (kings > 0)
                Text(
                  '${kuNumber(kings)} دامە',
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.secondary,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String get _statusText {
    final game = c.game!;
    if (game.winner == 'draw') return 'یارییەکە بە یەکسانی کۆتایی هات';
    if (game.winner != null) {
      return '${_playerName(game.winner == 'white' ? PlayerColor.white : PlayerColor.black)} بردییەوە!';
    }
    if (c.room != null && !c.room!.started) return 'چاوەڕوانی هاوڕێکەتین';
    if (c.role == 'spectator' && c.mode == GameMode.online) {
      return 'نۆرەی ${_playerName(game.turn)}';
    }
    if (c.botThinking) return 'بۆتەکە بیر دەکاتەوە…';
    if (c.mode == GameMode.hotseat) {
      return game.turn == PlayerColor.white
          ? 'نۆرەی یاریزانی سپییە'
          : 'نۆرەی یاریزانی ڕەشە';
    }
    return c.canPlay ? 'نۆرەی تۆیە؛ بەردێک هەڵبژێرە' : 'نۆرەی هاوڕێکەتە';
  }

  Widget _matchStatus(int captures) {
    final game = c.game!;
    final waiting = c.room != null && !c.room!.started;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
      decoration: BoxDecoration(
        color:
            (game.winner != null
                    ? theme.colorScheme.secondary
                    : theme.colorScheme.primary)
                .withValues(alpha: .075),
        border: Border.all(
          color:
              (game.winner != null
                      ? theme.colorScheme.secondary
                      : theme.colorScheme.primary)
                  .withValues(alpha: .18),
        ),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: [
          Container(
            width: 43,
            height: 43,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.outline),
            ),
            child: Icon(
              game.winner != null
                  ? Icons.workspace_premium_outlined
                  : waiting
                  ? Icons.people_outline_rounded
                  : Icons.trip_origin_rounded,
              color: theme.colorScheme.primary,
              size: 28,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  game.winner != null
                      ? 'WELL PLAYED'
                      : waiting
                      ? 'WAITING FOR A FRIEND'
                      : 'MOVE ${(game.ply + 1).toString().padLeft(2, '0')}',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 7,
                    letterSpacing: 1.6,
                    color: theme.colorScheme.onSurface.withValues(alpha: .6),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _statusText,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    height: 1.8,
                  ),
                ),
                Text(
                  game.winner != null
                      ? _reasonText(game.reason)
                      : waiting
                      ? 'لینکەکە بۆ هاوڕێکەت بنێرە تا پەیوەست بێت.'
                      : captures > 0
                      ? 'خواردن ناچارییە؛ زۆرترین بەرد بخۆ.'
                      : 'بەردێک هەڵبژێرە و لە خانەی ڕێگەپێدراو دایبنێ.',
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.9,
                    color: theme.colorScheme.onSurface.withValues(alpha: .6),
                  ),
                ),
              ],
            ),
          ),
          if (c.busy || c.botThinking)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }

  Widget _roomToolbar() {
    final theme = Theme.of(context);
    final online = c.mode == GameMode.online;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        children: [
          IconButton.outlined(
            tooltip: 'گەڕانەوە بۆ سەرەتا',
            onPressed: widget.onLeave,
            icon: const Icon(Icons.arrow_forward_rounded, size: 16),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  online
                      ? 'YOUR PRIVATE TABLE'
                      : c.mode == GameMode.bot
                      ? 'SOLO MATCH'
                      : 'PRACTICE TABLE',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 8,
                    letterSpacing: 1.7,
                    color: theme.colorScheme.onSurface.withValues(alpha: .6),
                  ),
                ),
                Text(
                  online
                      ? 'دانیشتنی هاوڕێکان'
                      : c.mode == GameMode.bot
                      ? 'ڕکابەری لەگەڵ بۆت'
                      : 'تەختەی تاقیکردنەوە',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (online)
            IconButton(
              tooltip: 'کۆپیکردنی کۆدی ڕووم',
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: c.room!.code));
              },
              icon: const Icon(Icons.copy_rounded, size: 15),
            ),
          if (MediaQuery.sizeOf(context).width > 600)
            Text(
              online ? c.room!.code : 'لەسەر یەک ئامێر',
              style: TextStyle(
                fontFamily: online ? 'Manrope' : null,
                fontSize: 10,
                color: theme.colorScheme.onSurface.withValues(alpha: .6),
              ),
            ),
        ],
      ),
    );
  }

  Widget _practiceBanner() => Container(
    margin: const EdgeInsets.only(bottom: 24),
    padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: .07),
      border: Border.all(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: .15),
      ),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              c.mode == GameMode.bot
                  ? Icons.smart_toy_outlined
                  : Icons.auto_awesome_outlined,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                c.mode == GameMode.bot
                    ? 'یاریکردن لەگەڵ بۆت · تۆ سپیت؛ بۆتەکە بە ڕەش یاری دەکات.'
                    : 'بە ئاسوودەیی تاقی بکەرەوە. نۆرە بە نۆرە هەردوو ڕەنگەکە بجووڵێنە.',
                style: const TextStyle(fontSize: 10, height: 2),
              ),
            ),
          ],
        ),
        if (c.mode == GameMode.bot) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 4,
            children: [
              for (final level in BotLevel.values)
                ChoiceChip(
                  label: Text(
                    levelName(level),
                    style: const TextStyle(fontSize: 9),
                  ),
                  selected: c.botLevel == level,
                  onSelected: (_) => c.setBotLevel(level),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ],
    ),
  );

  Widget _sideDetails() => c.room != null
      ? _roomDetails()
      : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DamaCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionTitle(
                    c.mode == GameMode.bot ? 'بۆتی دامە' : 'تەختەی تاقیکردنەوە',
                    icon: c.mode == GameMode.bot
                        ? Icons.smart_toy_outlined
                        : Icons.people_outline_rounded,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    c.mode == GameMode.bot
                        ? 'ئاستی ${levelName(c.botLevel)} · یاری لەسەر ئەم ئامێرە'
                        : 'نۆرە بە نۆرە یاری بکەن و جووڵەکان بگەڕێننەوە.',
                    style: const TextStyle(fontSize: 10, height: 2),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            DamaCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionTitle(
                    'مێژووی جووڵەکان',
                    icon: Icons.history_rounded,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(height: 240, child: MoveHistory(game: c.game!)),
                ],
              ),
            ),
            const SizedBox(height: 18),
            DamaCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionTitle(
                    'هەمان دامەی خۆمان',
                    icon: Icons.workspace_premium_outlined,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'خواردن ناچارییە؛ زۆرترین بەرد بخۆ. دامەکان بە چوار ئاراستە دەجووڵێن.',
                    style: TextStyle(fontSize: 10, height: 2),
                  ),
                  TextButton(
                    onPressed: () => showRules(context),
                    child: const Text(
                      'یاساکان ببینە',
                      style: TextStyle(fontSize: 10),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

  Widget _table() {
    final game = c.game!;
    final captures = game.winner == null
        ? legalMoves(game.board, game.turn).firstOrNull?.captures.length ?? 0
        : 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _matchStatus(captures),
        const SizedBox(height: 16),
        _playerBar(opposite(perspective)),
        const SizedBox(height: 10),
        _board(context),
        const SizedBox(height: 10),
        _playerBar(perspective),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            OutlinedButton.icon(
              onPressed: _focus,
              icon: const Icon(Icons.fullscreen_rounded, size: 16),
              label: const Text('تەنیا تەختە', style: TextStyle(fontSize: 10)),
            ),
            IconButton(
              tooltip: 'سووڕاندنی تەختە',
              onPressed: () => setState(() => _flipped = !_flipped),
              icon: const Icon(Icons.flip_camera_android_outlined),
            ),
            IconButton(
              tooltip: prefs.sound ? 'بێدەنگکردن' : 'چالاککردنی دەنگ',
              onPressed: () => prefs.update(sound: !prefs.sound),
              icon: Icon(
                prefs.sound
                    ? Icons.volume_up_outlined
                    : Icons.volume_off_outlined,
              ),
            ),
            if (c.mode != GameMode.online)
              IconButton(
                tooltip: 'گەڕاندنەوەی جووڵە',
                onPressed: game.ply > 0 ? c.undo : null,
                icon: const Icon(Icons.undo_rounded),
              ),
            if (prefs.coachEnabled)
              IconButton(
                tooltip: 'یارمەتیدەری ناوخۆ',
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => CoachDialog(controller: c),
                ),
                icon: const Icon(Icons.auto_awesome_outlined),
              ),
          ],
        ),
        if (game.winner != null)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: DamaCard(
              child: Column(
                children: [
                  Icon(
                    game.winner == 'draw'
                        ? Icons.handshake_outlined
                        : Icons.emoji_events_outlined,
                    size: 34,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _statusText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _reasonText(game.reason),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  if (c.mode == GameMode.online && c.role != 'spectator')
                    FilledButton.icon(
                      onPressed:
                          c.busy || c.room!.rematchVotes.contains(c.me?.id)
                          ? null
                          : c.rematch,
                      icon: const Icon(Icons.replay_rounded),
                      label: Text(
                        c.room!.rematchVotes.contains(c.me?.id)
                            ? 'چاوەڕوانی ڕەزامەندی هاوڕێکەت…'
                            : 'یارییەکی تر',
                      ),
                    ),
                  if (c.mode != GameMode.online)
                    FilledButton.icon(
                      onPressed: _reset,
                      icon: const Icon(Icons.replay_rounded),
                      label: const Text('یارییەکی نوێ'),
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 14),
        if (game.winner == null &&
            (c.mode != GameMode.online || c.role != 'spectator'))
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            children: [
              if (c.mode == GameMode.online && c.room!.started)
                OutlinedButton.icon(
                  onPressed: c.busy ? null : c.offerDraw,
                  icon: const Icon(Icons.handshake_outlined),
                  label: Text(
                    c.room!.drawOffer == c.myColor?.name
                        ? 'پاشگەزبوونەوە لە یەکسانی'
                        : 'داوای یەکسانی',
                  ),
                ),
              if (c.mode == GameMode.online && c.room!.started)
                TextButton.icon(
                  onPressed: c.busy
                      ? null
                      : () async {
                          if (await confirmAction(
                            context,
                            title: 'واز لە یاری دەهێنیت؟',
                            message:
                                'ئەم یارییە بە بردنەوەی هاوڕێکەت کۆتایی دێت.',
                            action: 'وازهێنان',
                          )) {
                            await c.resign();
                          }
                        },
                  icon: const Icon(Icons.flag_outlined),
                  label: const Text('وازهێنان'),
                ),
              if (c.mode != GameMode.online)
                TextButton.icon(
                  onPressed: _reset,
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('لە سەرەتاوە'),
                ),
            ],
          ),
      ],
    );
  }

  Future<void> _reset() async {
    if (!await confirmAction(
      context,
      title: 'یارییەکی نوێ؟',
      message: 'تەختەکە دەگەڕێتەوە بۆ سەرەتا.',
      action: 'دەستپێکردنەوە',
    )) {
      return;
    }
    if (c.mode == GameMode.bot) {
      c.startSolo(level: c.botLevel);
    } else {
      c.startHotseat();
    }
  }

  Widget _roomDetails() {
    final room = c.room!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (room.drawOffer != null &&
            room.drawOffer != c.myColor?.name &&
            c.role != 'spectator' &&
            room.game.winner == null) ...[
          DamaCard(
            child: Column(
              children: [
                const SectionTitle(
                  'هاوڕێکەت یەکسانی دەوێت',
                  icon: Icons.handshake_outlined,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: c.busy ? null : c.offerDraw,
                        child: const Text('ڕازیم'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: c.busy ? null : c.declineDraw,
                        child: const Text('بەردەوام بین'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        DamaCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionTitle(
                'هاوڕێکەت بانگ بکە',
                subtitle: 'لینکەکە لە وێب و مۆبایل کار دەکات.',
                icon: Icons.group_add_outlined,
              ),
              const SizedBox(height: 18),
              Directionality(
                textDirection: TextDirection.ltr,
                child: SelectableText(
                  room.code,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _copyInvite,
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text('کۆپی'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Builder(
                      builder: (buttonContext) => FilledButton.icon(
                        onPressed: () => _share(buttonContext),
                        icon: const Icon(Icons.ios_share_rounded, size: 18),
                        label: const Text('هاوبەشکردن'),
                      ),
                    ),
                  ),
                ],
              ),
              if (room.results.isNotEmpty) ...[
                const Divider(height: 30),
                const Text(
                  'ئەنجامی ئەم دانیشتنە',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                ),
                const SizedBox(height: 8),
                for (final player in room.players)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            player.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        Text(
                          '${kuNumber(room.results.where((r) => r.winnerId == player.id).length)} بردنەوە',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        DamaCard(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            height: 420,
            child: DefaultTabController(
              length: 3,
              child: Column(
                children: [
                  TabBar(
                    labelStyle: const TextStyle(
                      fontFamily: 'NotoSansArabic',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    tabs: [
                      Tab(text: 'گفتوگۆ ${kuNumber(room.messages.length)}'),
                      const Tab(text: 'جووڵەکان'),
                      const Tab(text: 'ئامادەکان'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        RoomChat(controller: c),
                        MoveHistory(game: room.game),
                        ListView(
                          padding: const EdgeInsets.all(8),
                          children: [
                            for (final member in room.members)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  member.role == 'spectator'
                                      ? Icons.visibility_outlined
                                      : Icons.person_outline_rounded,
                                ),
                                title: Text(
                                  member.name,
                                  style: const TextStyle(fontSize: 13),
                                ),
                                subtitle: Text(
                                  member.role == 'spectator'
                                      ? 'تماشاکەر'
                                      : member.role == 'white'
                                      ? 'سپی'
                                      : 'ڕەش',
                                  style: const TextStyle(fontSize: 10),
                                ),
                                trailing: Icon(
                                  Icons.circle,
                                  size: 8,
                                  color: member.isOnline()
                                      ? Colors.green
                                      : Colors.grey,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 920;
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(19, 29, 19, 44),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1060),
            child: Column(
              children: [
                _roomToolbar(),
                if (c.mode != GameMode.online) _practiceBanner(),
                if (wide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 65, child: _table()),
                      const SizedBox(width: 40),
                      Expanded(flex: 33, child: _sideDetails()),
                    ],
                  )
                else
                  Column(
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 650),
                        child: _table(),
                      ),
                      const SizedBox(height: 24),
                      _sideDetails(),
                    ],
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

String _reasonText(String? reason) => switch (reason) {
  'pieces' => 'هەموو بەردەکانی بەرامبەر خوران.',
  'blocked' => 'بەرامبەر هیچ جووڵەیەکی نەما.',
  'resign' => 'بە وازهێنان یارییەکە کۆتایی هات.',
  'agreement' => 'هەردوو یاریزان لەسەر یەکسانی ڕێک کەوتن.',
  'repetition' => 'هەمان دۆخ سێ جار دووبارە بووەوە.',
  'single-piece' => 'یاسای یەک بەرد بەرامبەر یەک بەرد.',
  _ => '',
};

class MoveHistory extends StatelessWidget {
  const MoveHistory({super.key, required this.game});
  final GameState game;
  @override
  Widget build(BuildContext context) {
    if (game.history.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timeline_rounded, size: 30),
            SizedBox(height: 8),
            Text('یەکەم جووڵە چاوەڕێ دەکات.', style: TextStyle(fontSize: 12)),
          ],
        ),
      );
    }
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.all(8),
      itemCount: game.history.length,
      itemBuilder: (context, index) {
        final item = game.history[game.history.length - 1 - index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            children: [
              Text(
                kuNumber(game.ply - index),
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(width: 12),
              Icon(
                Icons.circle,
                size: 10,
                color: item.color == PlayerColor.white
                    ? const Color(0xffd0aa7e)
                    : const Color(0xff2d5040),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    item.label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              if (item.captures > 0)
                Text(
                  '×${kuNumber(item.captures)}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.secondary,
                    fontSize: 11,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class RoomChat extends StatefulWidget {
  const RoomChat({super.key, required this.controller});
  final DamaController controller;
  @override
  State<RoomChat> createState() => _RoomChatState();
}

class _RoomChatState extends State<RoomChat> {
  final _text = TextEditingController();
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send([String? preset]) async {
    final draft = preset ?? _text.text;
    if (draft.trim().isEmpty) return;
    final success = await widget.controller.sendMessage(draft);
    if (mounted && success && preset == null && _text.text == draft) {
      _text.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final messages = c.room?.messages ?? <RoomMessage>[];
    return Column(
      children: [
        Expanded(
          child: messages.isEmpty
              ? const Center(
                  child: Text(
                    'سڵاوێک لە هاوڕێکەت بکە.',
                    style: TextStyle(fontSize: 12),
                  ),
                )
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 4,
                  ),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[messages.length - 1 - index];
                    final mine = message.memberId == c.me?.id;
                    return Align(
                      alignment: mine
                          ? AlignmentDirectional.centerStart
                          : AlignmentDirectional.centerEnd,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 270),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: mine
                              ? Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: .09)
                              : Theme.of(context).scaffoldBackgroundColor,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              message.name,
                              style: TextStyle(
                                fontSize: 10,
                                color: Theme.of(context).colorScheme.secondary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              message.text,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final text in ['سڵاو 👋', 'یارییەکی خۆش بێت!', 'دەستخۆش!'])
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: ActionChip(
                    label: Text(text, style: const TextStyle(fontSize: 10)),
                    onPressed: c.chatBusy ? null : () => _send(text),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _text,
                maxLength: 240,
                minLines: 1,
                maxLines: 3,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: const InputDecoration(
                  hintText: 'پەیامێک بنووسە…',
                  counterText: '',
                  contentPadding: EdgeInsets.all(12),
                ),
              ),
            ),
            const SizedBox(width: 5),
            IconButton.filled(
              tooltip: 'ناردنی پەیام',
              onPressed: c.chatBusy ? null : _send,
              icon: c.chatBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded, size: 20),
            ),
          ],
        ),
      ],
    );
  }
}
