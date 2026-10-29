import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/game.dart';

class DamaBoard extends StatefulWidget {
  const DamaBoard({
    super.key,
    required this.game,
    required this.canPlay,
    required this.onMove,
    this.perspective = PlayerColor.white,
    this.showCoordinates = true,
    this.showLegalMoves = true,
    this.boardStyle = 'wood',
    this.reduceMotion = false,
  });

  final GameState game;
  final bool canPlay;
  final ValueChanged<DamaMove> onMove;
  final PlayerColor perspective;
  final bool showCoordinates;
  final bool showLegalMoves;
  final String boardStyle;
  final bool reduceMotion;

  @override
  State<DamaBoard> createState() => _DamaBoardState();
}

class _DamaBoardState extends State<DamaBoard> {
  int? _from;
  List<int> _path = [];
  late List<DamaMove> _moves;
  late String _signature;
  final _focusNodes = List.generate(64, (_) => FocusNode());
  int _focusedSquare = 40;
  List<_BoardPiece> _pieces = [];
  List<int> _visualBoard = [];
  int _pieceGeneration = 0;

  bool get _flipped => widget.perspective == PlayerColor.black;
  String _gameKey(GameState game) =>
      '${game.id}:${game.ply}:${game.turn.name}:${game.winner}:${game.board.join(',')}';
  int _visual(int square) => _flipped ? 63 - square : square;
  int? get _selected => _path.isNotEmpty ? _path.last : _from;

  List<DamaMove> get _candidates => _from == null
      ? []
      : _moves
            .where(
              (move) =>
                  move.from == _from &&
                  move.path.length >= _path.length &&
                  List.generate(
                    _path.length,
                    (index) => move.path[index] == _path[index],
                  ).every((same) => same),
            )
            .toList();

  @override
  void initState() {
    super.initState();
    _signature = _gameKey(widget.game);
    _moves = widget.game.winner == null
        ? legalMoves(widget.game.board, widget.game.turn)
        : [];
    if (widget.game.board[_focusedSquare] == 0) {
      _focusedSquare = _moves.isNotEmpty ? _moves.first.from : 0;
    }
  }

  void _clearSelection() {
    _from = null;
    _path = [];
  }

  @override
  void didUpdateWidget(covariant DamaBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextSignature = _gameKey(widget.game);
    if (nextSignature != _signature) {
      _signature = nextSignature;
      _clearSelection();
      _moves = widget.game.winner == null
          ? legalMoves(widget.game.board, widget.game.turn)
          : [];
    } else if ((!widget.canPlay && oldWidget.canPlay) ||
        oldWidget.perspective != widget.perspective) {
      _clearSelection();
    }
  }

  @override
  void dispose() {
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _tap(int square) {
    if (!widget.canPlay || widget.game.winner != null) return;
    final candidates = _candidates;
    if (_from != null && square == _selected) {
      setState(_clearSelection);
      return;
    }
    if (_from != null &&
        candidates.any(
          (move) =>
              move.path.length > _path.length &&
              move.path[_path.length] == square,
        )) {
      final path = [..._path, square];
      final complete = candidates.where(
        (move) => move.path.length == path.length && move.path.last == square,
      );
      if (complete.isNotEmpty) {
        final move = complete.first;
        setState(_clearSelection);
        widget.onMove(move);
      } else {
        setState(() => _path = path);
      }
    } else if (_path.isEmpty &&
        pieceColor(widget.game.board[square]) == widget.game.turn &&
        _moves.any((move) => move.from == square)) {
      setState(() {
        _from = square;
        _path = [];
      });
    }
  }

  KeyEventResult _keyboard(KeyEvent event, int square) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space) {
      _tap(square);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape && _from != null) {
      setState(_clearSelection);
      return KeyEventResult.handled;
    }
    final index = _visual(square);
    final delta = {
      LogicalKeyboardKey.arrowLeft: -1,
      LogicalKeyboardKey.arrowRight: 1,
      LogicalKeyboardKey.arrowUp: -8,
      LogicalKeyboardKey.arrowDown: 8,
    }[key];
    int? next;
    if (delta != null) {
      next = index + delta;
      if (next < 0 ||
          next > 63 ||
          (delta.abs() == 1 && next ~/ 8 != index ~/ 8)) {
        return KeyEventResult.handled;
      }
    } else if (key == LogicalKeyboardKey.home) {
      next = index ~/ 8 * 8;
    } else if (key == LogicalKeyboardKey.end) {
      next = index ~/ 8 * 8 + 7;
    }
    if (next == null) return KeyEventResult.ignored;
    _focusNodes[_flipped ? 63 - next : next].requestFocus();
    return KeyEventResult.handled;
  }

  void _syncPieces(Board board) {
    if (_visualBoard.length == 64 &&
        List.generate(64, (i) => board[i] == _visualBoard[i]).every((v) => v)) {
      return;
    }
    final changed = _visualBoard.length == 64
        ? List.generate(
            64,
            (i) => board[i] != _visualBoard[i],
          ).where((changed) => changed).length
        : 64;
    _pieceGeneration++;
    if (changed > 10) {
      _pieces = [
        for (var square = 0; square < 64; square++)
          if (board[square] != 0)
            _BoardPiece('$_pieceGeneration-$square', square, board[square]),
      ];
    } else {
      final stationary = _pieces
          .where((piece) => board[piece.square] == piece.piece)
          .toList();
      final moved = _pieces
          .where((piece) => board[piece.square] != piece.piece)
          .toList();
      final next = [...stationary];
      for (var square = 0; square < 64; square++) {
        if (board[square] == 0 ||
            stationary.any((piece) => piece.square == square)) {
          continue;
        }
        final matches = moved
            .where(
              (piece) => pieceColor(piece.piece) == pieceColor(board[square]),
            )
            .toList();
        if (matches.isNotEmpty) {
          final source = matches.first;
          moved.remove(source);
          next.add(_BoardPiece(source.id, square, board[square]));
        } else {
          next.add(
            _BoardPiece('$_pieceGeneration-$square', square, board[square]),
          );
        }
      }
      _pieces = next;
    }
    _visualBoard = [...board];
  }

  @override
  Widget build(BuildContext context) {
    final palette = _BoardPalette.forStyle(widget.boardStyle);
    final candidates = _candidates;
    final targets = {
      for (final move in candidates)
        if (move.path.length > _path.length) move.path[_path.length],
    };
    final board = _path.isNotEmpty && candidates.isNotEmpty
        ? previewMove(widget.game.board, candidates.first, _path.length)
        : widget.game.board;
    _syncPieces(board);
    final reduceMotion =
        widget.reduceMotion ||
        (MediaQuery.maybeOf(context)?.disableAnimations ?? false);
    final duration = Duration(milliseconds: reduceMotion ? 0 : 220);
    final last = widget.game.lastMove;
    final lastPath = last == null ? <int>[] : [last.from, ...last.path];
    return Directionality(
      textDirection: TextDirection.ltr,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.hasBoundedWidth
              ? constraints.maxWidth
              : 360.0;
          final height = constraints.hasBoundedHeight
              ? constraints.maxHeight
              : width;
          final size = math.max(0.0, math.min(width, height));
          final frame = (size * .047).clamp(17.0, 28.0);
          final inner = math.max(0.0, size - frame * 2);
          final cell = inner / 8;
          return SizedBox.square(
            dimension: size,
            child: Semantics(
              container: true,
              explicitChildNodes: true,
              label: 'تەختەی دامە، هەشت ڕیز و هەشت ستوون',
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: palette.edge),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [palette.frameLight, palette.frameDark],
                  ),
                  boxShadow: [
                    BoxShadow(color: palette.edge, offset: const Offset(0, 3)),
                    const BoxShadow(
                      color: Color(0x282C2C1B),
                      offset: Offset(0, 13),
                      blurRadius: 24,
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(painter: _WoodPainter(palette)),
                      ),
                    ),
                    if (widget.showCoordinates)
                      ..._coordinates(frame, inner, size, palette),
                    Positioned(
                      left: frame,
                      top: frame,
                      width: inner,
                      height: inner,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: Stack(
                          children: [
                            Column(
                              children: [
                                for (var row = 0; row < 8; row++)
                                  Expanded(
                                    child: Row(
                                      children: [
                                        for (var col = 0; col < 8; col++)
                                          Expanded(
                                            child: _square(
                                              _flipped
                                                  ? 63 - (row * 8 + col)
                                                  : row * 8 + col,
                                              board,
                                              targets,
                                              lastPath,
                                              palette,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                            Positioned.fill(
                              child: IgnorePointer(
                                child: CustomPaint(
                                  painter: _PathPainter(
                                    lastPath,
                                    _flipped,
                                    palette.accent,
                                  ),
                                ),
                              ),
                            ),
                            for (final piece in _pieces)
                              AnimatedPositioned(
                                key: ValueKey('piece-${piece.id}'),
                                duration: duration,
                                curve: Curves.easeOutCubic,
                                left: _visual(piece.square) % 8 * cell,
                                top: _visual(piece.square) ~/ 8 * cell,
                                width: cell,
                                height: cell,
                                child: IgnorePointer(
                                  child: ExcludeSemantics(
                                    child: Center(
                                      child: AnimatedScale(
                                        scale: _selected == piece.square
                                            ? 1.07
                                            : 1,
                                        duration: duration,
                                        child: _DamaPiece(
                                          key: ValueKey(
                                            'piece-at-${piece.square}',
                                          ),
                                          piece: piece.piece,
                                          size: cell * .78,
                                          selected: _selected == piece.square,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _square(
    int square,
    Board board,
    Set<int> targets,
    List<int> lastPath,
    _BoardPalette palette,
  ) {
    final selected = square == _selected;
    final target = widget.canPlay && targets.contains(square);
    final movable =
        widget.canPlay &&
        _from == null &&
        _moves.any((move) => move.from == square);
    final piece = board[square];
    final name = piece == 0
        ? 'بەتاڵ'
        : '${piece > 0 ? 'سپی' : 'ڕەش'} ${piece.abs() == 2 ? 'دامە' : 'بەرد'}';
    final dark = (square ~/ 8 + square % 8).isOdd;
    final background = selected
        ? palette.selected
        : lastPath.contains(square)
        ? palette.last
        : dark
        ? palette.dark
        : palette.light;
    return Semantics(
      key: ValueKey('square-$square'),
      button: true,
      enabled: widget.canPlay,
      selected: selected,
      label:
          '${coordinate(square)}: $name${target ? '، جووڵەی ڕێگەپێدراو' : ''}',
      onTap: widget.canPlay ? () => _tap(square) : null,
      child: Focus(
        focusNode: _focusNodes[square],
        skipTraversal: square != _focusedSquare,
        onFocusChange: (focused) {
          if (focused && mounted) setState(() => _focusedSquare = square);
        },
        onKeyEvent: (_, event) => _keyboard(event, square),
        child: GestureDetector(
          excludeFromSemantics: true,
          behavior: HitTestBehavior.opaque,
          onTap: widget.canPlay ? () => _tap(square) : null,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: background,
              border: Border.all(
                color: selected || _focusNodes[square].hasFocus
                    ? palette.accent
                    : const Color(0x0C655B44),
                width: selected || _focusNodes[square].hasFocus ? 2 : .4,
              ),
            ),
            child: Stack(
              children: [
                if (target && widget.showLegalMoves)
                  Center(
                    child: FractionallySizedBox(
                      widthFactor: .23,
                      heightFactor: .23,
                      child: DecoratedBox(
                        key: ValueKey('target-$square'),
                        decoration: BoxDecoration(
                          color: palette.accent.withValues(alpha: .63),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: palette.accent.withValues(alpha: .08),
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (movable && widget.showLegalMoves)
                  Align(
                    alignment: const Alignment(0, .91),
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: palette.accent.withValues(alpha: .65),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _coordinates(
    double frame,
    double inner,
    double size,
    _BoardPalette palette,
  ) {
    final letters = (_flipped ? 'hgfedcba' : 'abcdefgh').split('');
    final ranks = List.generate(8, (i) => _flipped ? i + 1 : 8 - i);
    final style = TextStyle(
      color: palette.coordinates,
      fontSize: (size * .02).clamp(8.0, 11.0),
      fontWeight: FontWeight.w600,
      height: 1,
    );
    Widget label(String text, String key) => ExcludeSemantics(
      child: Center(
        child: Text(text, key: ValueKey(key), style: style),
      ),
    );
    return [
      for (final top in [true, false])
        Positioned(
          left: frame,
          top: top ? 0 : size - frame,
          width: inner,
          height: frame,
          child: Row(
            children: [
              for (final letter in letters)
                Expanded(
                  child: label(
                    letter,
                    'coordinate-${top ? 'top' : 'bottom'}-$letter',
                  ),
                ),
            ],
          ),
        ),
      for (final left in [true, false])
        Positioned(
          left: left ? 0 : size - frame,
          top: frame,
          width: frame,
          height: inner,
          child: Column(
            children: [
              for (final rank in ranks)
                Expanded(child: label('$rank', 'rank-$left-$rank')),
            ],
          ),
        ),
    ];
  }
}

class _BoardPiece {
  const _BoardPiece(this.id, this.square, this.piece);
  final String id;
  final int square;
  final int piece;
}

class _DamaPiece extends StatelessWidget {
  const _DamaPiece({
    super.key,
    required this.piece,
    required this.size,
    required this.selected,
  });
  final int piece;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final white = piece > 0;
    final edge = white ? const Color(0xFFB19562) : const Color(0xFF1F3825);
    final ring = white ? const Color(0xFFBEA16F) : const Color(0xFF728765);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: edge),
        gradient: RadialGradient(
          center: const Alignment(-.35, -.5),
          radius: 1,
          colors: white
              ? const [Color(0xFFFFF8DF), Color(0xFFE7CAA0)]
              : const [Color(0xFF677F5F), Color(0xFF29422E)],
        ),
        boxShadow: [
          BoxShadow(color: edge, offset: Offset(0, selected ? 4 : 2)),
          BoxShadow(
            color: Colors.black.withValues(alpha: white ? .18 : .25),
            offset: Offset(0, selected ? 7 : 4),
            blurRadius: selected ? 7 : 4,
          ),
        ],
      ),
      child: Center(
        child: FractionallySizedBox(
          widthFactor: .8,
          heightFactor: .8,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: ring.withValues(alpha: .75)),
            ),
            child: Center(
              child: piece.abs() == 2
                  ? CustomPaint(
                      size: Size.square(size * .43),
                      painter: _CrownPainter(
                        white
                            ? const Color(0xFF976E35)
                            : const Color(0xFFE8CC91),
                      ),
                    )
                  : FractionallySizedBox(
                      widthFactor: .68,
                      heightFactor: .68,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: ring.withValues(alpha: .55),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CrownPainter extends CustomPainter {
  const _CrownPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * .14, size.height * .32)
      ..lineTo(size.width * .31, size.height * .52)
      ..lineTo(size.width * .5, size.height * .16)
      ..lineTo(size.width * .69, size.height * .52)
      ..lineTo(size.width * .86, size.height * .32)
      ..lineTo(size.width * .77, size.height * .79)
      ..lineTo(size.width * .23, size.height * .79)
      ..close();
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.3, size.width * .06);
    canvas.drawPath(path, paint);
    canvas.drawLine(
      Offset(size.width * .27, size.height * .94),
      Offset(size.width * .73, size.height * .94),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _CrownPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _WoodPainter extends CustomPainter {
  const _WoodPainter(this.palette);
  final _BoardPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .035)
      ..strokeWidth = .7;
    for (var y = 5.0; y < size.height; y += 12) {
      canvas.drawLine(Offset(5, y), Offset(size.width - 5, y + 4), paint);
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(4, 4, size.width - 8, size.height - 8),
        const Radius.circular(9),
      ),
      Paint()
        ..color = palette.coordinates.withValues(alpha: .19)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _WoodPainter oldDelegate) =>
      oldDelegate.palette != palette;
}

class _PathPainter extends CustomPainter {
  const _PathPainter(this.squares, this.flipped, this.color);
  final List<int> squares;
  final bool flipped;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (squares.length < 2) return;
    final path = Path();
    for (var index = 0; index < squares.length; index++) {
      final square = flipped ? 63 - squares[index] : squares[index];
      final x = (square % 8 + .5) * size.width / 8;
      final y = (square ~/ 8 + .5) * size.height / 8;
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: .23)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _PathPainter oldDelegate) =>
      oldDelegate.squares != squares ||
      oldDelegate.flipped != flipped ||
      oldDelegate.color != color;
}

class _BoardPalette {
  const _BoardPalette({
    required this.frameLight,
    required this.frameDark,
    required this.edge,
    required this.coordinates,
    required this.light,
    required this.dark,
    required this.last,
    required this.selected,
    required this.accent,
  });
  final Color frameLight, frameDark, edge, coordinates;
  final Color light, dark, last, selected, accent;

  static const wood = _BoardPalette(
    frameLight: Color(0xFF9F7A50),
    frameDark: Color(0xFF5B402B),
    edge: Color(0xFF493420),
    coordinates: Color(0xFFE3CBAA),
    light: Color(0xFFEDE2CB),
    dark: Color(0xFFD2BD99),
    last: Color(0xFFB6BC8F),
    selected: Color(0xFFB1BC84),
    accent: Color(0xFF375A3D),
  );
  static const olive = _BoardPalette(
    frameLight: Color(0xFF87947A),
    frameDark: Color(0xFF4A5B46),
    edge: Color(0xFF3C4C37),
    coordinates: Color(0xFFDFE6D0),
    light: Color(0xFFEEEDDA),
    dark: Color(0xFFBEC5A4),
    last: Color(0xFFCED2A0),
    selected: Color(0xFFAEBC7C),
    accent: Color(0xFF45653C),
  );
  static const slate = _BoardPalette(
    frameLight: Color(0xFF647C7D),
    frameDark: Color(0xFF354C50),
    edge: Color(0xFF293E42),
    coordinates: Color(0xFFD3DED9),
    light: Color(0xFFE7E9E0),
    dark: Color(0xFFB5C4BE),
    last: Color(0xFFB6C8A8),
    selected: Color(0xFFA5BBA1),
    accent: Color(0xFF365B4F),
  );

  static _BoardPalette forStyle(String style) => switch (style) {
    'olive' => olive,
    'slate' => slate,
    _ => wood,
  };
}
