import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../game/bot.dart';
import '../game/game.dart';
import '../preferences.dart';
import '../state/dama_controller.dart';
import '../theme.dart';
import '../widgets/dama_board.dart';
import 'dialogs.dart';

String levelName(BotLevel level) => switch (level) {
  BotLevel.easy => 'ئاسان',
  BotLevel.medium => 'مامناوەند',
  BotLevel.hard => 'بەهێز',
};

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({
    super.key,
    required this.controller,
    required this.preferences,
  });
  final DamaController controller;
  final AppPreferences preferences;
  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  final _code = TextEditingController();
  final _password = TextEditingController();
  int _tab = 0;
  bool _spectator = false,
      _nameEdited = false,
      _levelEdited = false,
      _restored = false;
  late BotLevel _level;
  DamaController get c => widget.controller;
  Color get muted =>
      Theme.of(context).colorScheme.onSurface.withValues(alpha: .61);
  Color get line => Theme.of(context).colorScheme.outline;
  Color get soft =>
      Theme.of(context).colorScheme.primary.withValues(alpha: .075);

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: c.name);
    _level = c.botLevel;
    c.addListener(_restore);
  }

  void _restore() {
    if (!mounted || _restored || c.initializing) return;
    _restored = true;
    if (!_nameEdited) _name.text = c.name;
    if (!_levelEdited) setState(() => _level = c.botLevel);
  }

  @override
  void dispose() {
    c.removeListener(_restore);
    _name.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _enter() async {
    if (_tab == 2) {
      c.startSolo(level: _level);
      return;
    }
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    c.setName(_name.text.trim());
    if (_tab == 0) {
      await c.createRoom(password: _password.text);
    } else {
      await c.joinRoom(
        _code.text,
        password: _password.text,
        spectator: _spectator,
      );
    }
  }

  Widget _label(String title, [String? hint]) => Padding(
    padding: const EdgeInsets.only(top: 13, bottom: 7),
    child: Row(
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
        ),
        const Spacer(),
        if (hint != null)
          Text(hint, style: TextStyle(fontSize: 8, color: muted)),
      ],
    ),
  );

  Widget _entryCard() {
    final solo = _tab == 2;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: line),
        boxShadow: [
          BoxShadow(
            color: DamaColors.forest.withValues(alpha: .045),
            blurRadius: 25,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 19),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (final item in [
                (0, 'ڕوومێکی نوێ', Icons.person_outline_rounded),
                (1, 'چوونە ناو ڕووم', Icons.link_rounded),
                (2, 'لەگەڵ بۆت', Icons.smart_toy_outlined),
              ])
                Expanded(
                  child: Semantics(
                    selected: _tab == item.$1,
                    button: true,
                    child: InkWell(
                      onTap: c.busy
                          ? null
                          : () => setState(() => _tab = item.$1),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 53),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: _tab == item.$1
                                  ? Theme.of(context).colorScheme.primary
                                  : line,
                              width: _tab == item.$1 ? 2 : 1,
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              item.$3,
                              size: 14,
                              color: _tab == item.$1
                                  ? Theme.of(context).colorScheme.primary
                                  : muted,
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                item.$2,
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize:
                                      MediaQuery.sizeOf(context).width < 360
                                      ? 8
                                      : 10,
                                  fontWeight: _tab == item.$1
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: _tab == item.$1
                                      ? Theme.of(context).colorScheme.primary
                                      : muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            solo
                ? 'هاوڕێیەک، هەمیشە ئامادەی یاری'
                : _tab == 0
                ? 'شوێنێک بۆ تۆ و هاوڕێکانت'
                : 'هاوڕێکەت چاوەڕێتە',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 7),
          Text(
            solo
                ? 'بۆتەکە بە ئاستی خۆت هەڵبژێرە و زیرەکییەکەت تاقی بکەرەوە.'
                : _tab == 0
                ? 'ڕوومێکی تایبەت لە چەند چرکەیەکدا.'
                : 'کۆدی بانگهێشتەکەت بنووسە و پەیوەست بە.',
            style: TextStyle(fontSize: 9, color: muted, height: 2),
          ),
          if (solo)
            _soloEntry()
          else
            Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _label('ناوەکەت', 'تا ٢٤ پیت'),
                  TextFormField(
                    controller: _name,
                    onChanged: (_) => _nameEdited = true,
                    maxLength: 24,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.nickname],
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      hintText: 'بە چی ناوێک بانگت بکەین؟',
                      prefixIcon: Icon(Icons.people_outline_rounded, size: 18),
                      counterText: '',
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'تکایە ناوت بنووسە.'
                        : null,
                  ),
                  if (_tab == 1) ...[
                    _label('کۆدی ڕووم'),
                    TextFormField(
                      controller: _code,
                      textDirection: TextDirection.ltr,
                      textCapitalization: TextCapitalization.characters,
                      autocorrect: false,
                      enableSuggestions: false,
                      style: const TextStyle(
                        fontFamily: 'Manrope',
                        fontSize: 13,
                        letterSpacing: 2,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'ABCDEFG234',
                        prefixIcon: Icon(Icons.link_rounded, size: 18),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'کۆدی ڕوومەکە بنووسە.'
                          : null,
                    ),
                    const SizedBox(height: 13),
                    Row(
                      children: [
                        for (final option in [
                          (
                            false,
                            'یاریزان',
                            'شوێنی دووەم بۆ تۆیە',
                            Icons.workspace_premium_outlined,
                          ),
                          (
                            true,
                            'تماشاکەر',
                            'یاری ببینە و گفتوگۆ بکە',
                            Icons.visibility_outlined,
                          ),
                        ]) ...[
                          if (option.$1) const SizedBox(width: 8),
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(7),
                              onTap: () =>
                                  setState(() => _spectator = option.$1),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: _spectator == option.$1 ? soft : null,
                                  border: Border.all(
                                    color: _spectator == option.$1
                                        ? Theme.of(context).colorScheme.primary
                                              .withValues(alpha: .3)
                                        : line,
                                  ),
                                  borderRadius: BorderRadius.circular(7),
                                ),
                                child: Row(
                                  children: [
                                    Icon(option.$4, size: 17, color: muted),
                                    const SizedBox(width: 7),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            option.$2,
                                            style: const TextStyle(
                                              fontSize: 11,
                                            ),
                                          ),
                                          Text(
                                            option.$3,
                                            style: TextStyle(
                                              fontSize: 7,
                                              color: muted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (_spectator == option.$1)
                                      const Icon(Icons.check_rounded, size: 13),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                  if (c.status?.passwordRequired == true) ...[
                    _label('وشەی نهێنی هاوڕێکان'),
                    TextFormField(
                      controller: _password,
                      obscureText: true,
                      maxLength: 200,
                      decoration: const InputDecoration(
                        hintText: 'وشە نهێنییە هاوبەشەکەتان',
                        prefixIcon: Icon(Icons.lock_outline_rounded, size: 17),
                        counterText: '',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          if (!solo && c.savedRoomCode.isNotEmpty && c.room == null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: OutlinedButton.icon(
                onPressed: c.busy ? null : c.refresh,
                icon: const Icon(Icons.restore_rounded, size: 16),
                label: const Text('گەڕانەوە بۆ ڕوومی پێشوو'),
              ),
            ),
          if (!solo && c.status == null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'پەیوەندی سێرڤەر دەپشکنرێت…',
                      style: TextStyle(fontSize: 9, color: muted),
                    ),
                  ),
                  TextButton(
                    onPressed: c.refresh,
                    child: const Text(
                      'دووبارە هەوڵ بدەوە',
                      style: TextStyle(fontSize: 9),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 17),
          FilledButton(
            onPressed:
                c.busy ||
                    (!solo &&
                        (c.initializing ||
                            c.status == null ||
                            c.status!.mode == 'unconfigured'))
                ? null
                : _enter,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    c.busy
                        ? 'ڕوومەکە ئامادە دەکرێت…'
                        : solo
                        ? 'یاری لەگەڵ بۆت دەست پێ بکە'
                        : _tab == 0
                        ? 'ڕوومێک دروست بکە'
                        : 'بچۆ ناو ڕووم',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (c.busy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    solo ? Icons.smart_toy_outlined : Icons.north_west_rounded,
                    size: 21,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                solo ? Icons.smart_toy_outlined : Icons.verified_user_outlined,
                size: 13,
                color: muted,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  solo
                      ? 'بێ بانگهێشت و چاوەڕوانی · یاری لەسەر ئەم ئامێرە'
                      : 'بێ تۆمارکردن · بە لینکی تایبەت · تا ٤ کەس',
                  style: TextStyle(fontSize: 8, color: muted),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _soloEntry() => Column(
    children: [
      const SizedBox(height: 13),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border.all(color: line),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          children: [
            Expanded(child: _matchup('تۆ', 'بەردە سپییەکان', false)),
            Text(
              'VS',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 8,
                fontWeight: FontWeight.w700,
                color: muted,
              ),
            ),
            Expanded(child: _matchup('بۆتی دامە', 'بەردە ڕەشەکان', true)),
          ],
        ),
      ),
      const SizedBox(height: 17),
      Row(
        children: [
          const Text('ئاستی بۆت', style: TextStyle(fontSize: 11)),
          const Spacer(),
          Flexible(
            child: Text(
              'هەر کاتێک بتەوێت دەتوانیت بیگۆڕیت',
              style: TextStyle(fontSize: 7, color: muted),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          for (final level in BotLevel.values) ...[
            if (level != BotLevel.easy) const SizedBox(width: 8),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() {
                  _level = level;
                  _levelEdited = true;
                }),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(5, 12, 5, 10),
                  decoration: BoxDecoration(
                    color: _level == level ? soft : null,
                    border: Border.all(
                      color: _level == level
                          ? Theme.of(context).colorScheme.primary
                          : line,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (var i = 0; i < 3; i++)
                            Container(
                              width: 5,
                              height: 8.0 + i * 5,
                              margin: const EdgeInsets.symmetric(
                                horizontal: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: i <= level.index
                                    ? (_level == level
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.primary
                                          : muted)
                                    : line,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 9),
                      Text(
                        levelName(level),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(switch (level) {
                        BotLevel.easy => 'بۆ دەستپێکردن',
                        BotLevel.medium => 'بۆ ڕاهێنان',
                        BotLevel.hard => 'بۆ ڕکابەری',
                      }, style: TextStyle(fontSize: 8, color: muted)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
      const SizedBox(height: 12),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.circle, size: 4, color: Color(0xff7c9a65)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'سپی دەست پێ دەکات؛ یەکەم جووڵە بۆ تۆیە.',
              style: TextStyle(fontSize: 8, color: muted),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    ],
  );

  Widget _matchup(String title, String subtitle, bool bot) => Row(
    mainAxisAlignment: bot ? MainAxisAlignment.end : MainAxisAlignment.start,
    children: [
      Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: bot ? DamaColors.forest : const Color(0xffefe0c2),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(
          bot ? Icons.smart_toy_outlined : Icons.people_outline_rounded,
          size: 19,
          color: bot ? const Color(0xffc7d9b4) : const Color(0xff947140),
        ),
      ),
      const SizedBox(width: 7),
      Flexible(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
            ),
            Text(subtitle, style: TextStyle(fontSize: 6, color: muted)),
          ],
        ),
      ),
    ],
  );

  Widget _hero(bool wide) => Column(
    crossAxisAlignment: wide
        ? CrossAxisAlignment.start
        : CrossAxisAlignment.center,
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: const Color(0xff7c9a65),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: soft, spreadRadius: 4)],
            ),
          ),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              'بۆ ئەو دانیشتنانەی بیرمان دەکەون',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 9, color: muted),
            ),
          ),
        ],
      ),
      const SizedBox(height: 17),
      Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: wide
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              Text(
                'دامەیەک لەگەڵ',
                textAlign: wide ? TextAlign.start : TextAlign.center,
                style: TextStyle(
                  fontSize: wide
                      ? (MediaQuery.sizeOf(context).width <= 920
                            ? 35.0
                            : MediaQuery.sizeOf(context).width <= 1150
                            ? 40.0
                            : (MediaQuery.sizeOf(context).width * .038).clamp(
                                35.0,
                                52.0,
                              ))
                      : MediaQuery.sizeOf(context).width < 400
                      ? 34
                      : 39,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -1.3,
                  height: 1.65,
                ),
              ),
              Text(
                'هاوڕێیەکی باش.',
                textAlign: wide ? TextAlign.start : TextAlign.center,
                style: TextStyle(
                  fontSize: wide
                      ? (MediaQuery.sizeOf(context).width <= 920
                            ? 35.0
                            : MediaQuery.sizeOf(context).width <= 1150
                            ? 40.0
                            : (MediaQuery.sizeOf(context).width * .038).clamp(
                                35.0,
                                52.0,
                              ))
                      : MediaQuery.sizeOf(context).width < 400
                      ? 34
                      : 39,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.secondary,
                  letterSpacing: -1.3,
                  height: 1.65,
                ),
              ),
            ],
          ),
          if (MediaQuery.sizeOf(context).width > 360)
            const Positioned(
              top: 0,
              left: -26,
              child: Text(
                '✳',
                style: TextStyle(
                  fontFamily: 'serif',
                  fontSize: 30,
                  color: Color(0xffb3b99a),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 15),
      Text(
        'چا ئامادە بکە، لینکەکە بنێرە و پێکەوە یاری بکەن.\nهەمان دامەی خۆمان؛ لە هەر شوێنێک کە بن.',
        textAlign: wide ? TextAlign.start : TextAlign.center,
        style: TextStyle(fontSize: 11, color: muted, height: 2.3),
      ),
      const SizedBox(height: 25),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 435),
        child: _entryCard(),
      ),
      const SizedBox(height: 16),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: TextButton.icon(
              onPressed: c.busy ? null : c.startHotseat,
              icon: Icon(
                Icons.play_circle_outline_rounded,
                size: 21,
                color: muted,
              ),
              label: Text(
                'تاقیکردنەوەی دوو کەسی',
                style: TextStyle(fontSize: 10, color: muted),
              ),
            ),
          ),
          TextButton.icon(
            onPressed: () => showRules(context),
            icon: Icon(Icons.help_outline_rounded, size: 15, color: muted),
            label: Text(
              'یاساکان',
              style: TextStyle(fontSize: 10, color: muted),
            ),
          ),
        ],
      ),
    ],
  );

  Widget _preview() => LayoutBuilder(
    builder: (context, constraints) => Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: CustomPaint(
          painter: _ScenePainter(line),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 14),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        'THE TABLE IS YOURS',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 8,
                          letterSpacing: 2.5,
                          color: muted,
                        ),
                      ),
                    ),
                    Text(
                      '✳',
                      style: TextStyle(
                        fontFamily: 'serif',
                        fontSize: 26,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Transform.rotate(
                  angle: -math.pi / 60,
                  child: Column(
                    children: [
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: FractionallySizedBox(
                          widthFactor: .84,
                          child: _previewPlayer(false),
                        ),
                      ),
                      const SizedBox(height: 15),
                      ExcludeSemantics(
                        child: IgnorePointer(
                          child: DamaBoard(
                            game: newGame('decorative'),
                            canPlay: false,
                            onMove: (_) {},
                            boardStyle: widget.preferences.boardStyle,
                            showCoordinates: true,
                            showLegalMoves: false,
                            reduceMotion: true,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: FractionallySizedBox(
                          widthFactor: .84,
                          child: _previewPlayer(true),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 23),
                Transform.rotate(
                  angle: .045,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.secondary.withValues(alpha: .13),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.secondary.withValues(alpha: .17),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.local_cafe_outlined,
                          size: 19,
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                        const SizedBox(width: 9),
                        Text(
                          'بێ پەلە،\nبە چێژەوە.',
                          style: TextStyle(
                            fontSize: 9,
                            color: Theme.of(context).colorScheme.secondary,
                            height: 1.8,
                          ),
                        ),
                        const SizedBox(width: 15),
                        Text(
                          '✦',
                          style: TextStyle(
                            fontSize: 18,
                            color: Theme.of(context).colorScheme.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'CLASSIC 8 × 8',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 8,
                          letterSpacing: 2,
                          color: muted,
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: () =>
                            showSettings(context, widget.preferences, c),
                        child: Text(
                          'تەختەکەت هەڵبژێرە ‹',
                          style: TextStyle(fontSize: 9, color: muted),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _previewPlayer(bool white) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border.all(color: line),
      borderRadius: BorderRadius.circular(10),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .035),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Row(
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: white ? const Color(0xffe8d5ae) : DamaColors.forest,
            border: Border.all(
              color: white ? const Color(0xffcfb78a) : const Color(0xff294333),
            ),
          ),
          child: Text(
            white ? 'ت' : 'هـ',
            style: TextStyle(
              fontSize: 14,
              color: white ? const Color(0xff8c6b42) : const Color(0xffe6ebd3),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                white ? 'تۆ' : 'هاوڕێکەت',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                white ? 'سپی · ١٦ بەرد' : 'ڕەش · ١٦ بەرد',
                style: TextStyle(fontSize: 8, color: muted),
              ),
            ],
          ),
        ),
        if (white)
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: soft,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                'یەکەم جووڵە بۆ تۆیە',
                style: TextStyle(
                  fontSize: 7,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          )
        else
          Text('● ئامادەیە', style: TextStyle(fontSize: 8, color: muted)),
      ],
    ),
  );

  Widget _features(bool wide) => Container(
    padding: const EdgeInsets.symmetric(vertical: 28),
    decoration: BoxDecoration(
      border: Border(
        top: BorderSide(color: line),
        bottom: BorderSide(color: line),
      ),
    ),
    child: Wrap(
      spacing: 20,
      runSpacing: 24,
      children: [
        for (final item in [
          (
            Icons.lock_outline_rounded,
            'دانیشتنێکی تایبەت',
            'لینکەکە لەگەڵ هاوڕێکانت هاوبەش بکە.',
          ),
          (
            Icons.people_outline_rounded,
            'دوو کەس یاری، دوو کەس تماشا',
            'هەمووان لە یەک ڕوومدا، بە گفتوگۆوە.',
          ),
          (
            Icons.auto_awesome_outlined,
            'بە سەلیقەی خۆت',
            'ڕووکارێکی شەو و سێ شێوەی تەختە.',
          ),
          (
            Icons.workspace_premium_outlined,
            'هەمان دامەی خۆمان',
            'یاساکان خۆکارانە دەپارێزرێن.',
          ),
        ])
          FractionallySizedBox(
            widthFactor: wide ? .23 : .46,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 39,
                  height: 39,
                  decoration: BoxDecoration(
                    color: soft,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: line),
                  ),
                  child: Icon(
                    item.$1,
                    size: 21,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  item.$2,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  item.$3,
                  style: TextStyle(fontSize: 10, color: muted, height: 2),
                ),
              ],
            ),
          ),
      ],
    ),
  );

  Widget _steps(bool wide) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 34),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'LET’S PLAY',
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.8,
            color: muted,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'دانیشتنەکە لێرە دەست پێ دەکات.',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 7),
        Text(
          'هەموو شتێک ئامادەیە؛ تەنیا هاوڕێکەت بانگ بکە.',
          style: TextStyle(fontSize: 10, color: muted),
        ),
        const SizedBox(height: 25),
        for (final step in [
          ('01', 'ڕوومێک بۆ خۆتان', 'ناوەکەت بنووسە و ڕوومەکەت دروست بکە.'),
          ('02', 'لینکێک بۆ هاوڕێکەت', 'لینکی تایبەتەکە کۆپی بکە و بۆی بنێرە.'),
          (
            '03',
            'با زیرەکی دەست پێ بکات',
            'بەردێک هەڵبژێرە؛ ئەوە یەکەم جووڵەتە.',
          ),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.$1,
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 24,
                    color: Color(0xffbdc3aa),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step.$2,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        step.$3,
                        style: TextStyle(fontSize: 9, color: muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 760;
      final margin = wide
          ? (constraints.maxWidth * .051).clamp(20.0, 72.0)
          : 19.0;
      return SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: margin),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1288),
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.only(top: wide ? 52 : 33, bottom: 40),
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(flex: 97, child: _hero(true)),
                            const SizedBox(width: 60),
                            Expanded(flex: 103, child: _preview()),
                          ],
                        )
                      : Column(
                          children: [
                            _hero(false),
                            const SizedBox(height: 32),
                            _preview(),
                          ],
                        ),
                ),
                _features(wide),
                _steps(wide),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _ScenePainter extends CustomPainter {
  const _ScenePainter(this.line);
  final Color line;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = line.withValues(alpha: .4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .6;
    final radius = size.width * .48;
    canvas.drawCircle(Offset(size.width / 2, size.height * .47), radius, paint);
    paint.color = line.withValues(alpha: .13);
    for (double x = 25; x < size.width - 25; x += 34) {
      canvas.drawLine(Offset(x, 80), Offset(x, size.height - 85), paint);
    }
    for (double y = 80; y < size.height - 85; y += 34) {
      canvas.drawLine(Offset(25, y), Offset(size.width - 25, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ScenePainter oldDelegate) =>
      oldDelegate.line != line;
}
