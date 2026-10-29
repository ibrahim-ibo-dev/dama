/// Bounded, pure Dart computer opponent. Run [analyzeBot] with Flutter compute
/// so alpha-beta search never blocks the app's main isolate.
library;

import 'dart:math' as math;

import 'game.dart';

enum BotLevel { easy, medium, hard }

class BotAnalysis {
  const BotAnalysis({
    required this.move,
    required this.score,
    required this.depth,
    required this.nodes,
  });

  final DamaMove? move;
  final int score;
  final int depth;
  final int nodes;

  factory BotAnalysis.fromJson(Map<String, dynamic> json) => BotAnalysis(
    move: json['move'] == null
        ? null
        : DamaMove.fromJson((json['move'] as Map).cast<String, dynamic>()),
    score: (json['score'] as num).toInt(),
    depth: (json['depth'] as num).toInt(),
    nodes: (json['nodes'] as num).toInt(),
  );

  Map<String, dynamic> toJson() => {
    'move': move?.toJson(),
    'score': score,
    'depth': depth,
    'nodes': nodes,
  };
}

const _mate = 100000;
const _mateThreshold = _mate - 100;
const _stop = _SearchStopped();

class _SearchStopped implements Exception {
  const _SearchStopped();
}

typedef _Settings = ({int timeMs, int depth, int nodes, int extensions});

_Settings _settings(BotLevel level) => switch (level) {
  BotLevel.easy => (timeMs: 20, depth: 1, nodes: 1000, extensions: 0),
  BotLevel.medium => (timeMs: 250, depth: 5, nodes: 25000, extensions: 2),
  BotLevel.hard => (timeMs: 1000, depth: 8, nodes: 100000, extensions: 4),
};

String _moveKey(DamaMove move) => '${move.from}:${move.path.join(',')}';
String _boardKey(Board board, PlayerColor color) =>
    '${board.join(',')}:${color.name}';

// JS Math.imul-compatible multiplication, including Dart's web compiler.
int _imul(int a, int b) {
  final low = (a & 0xffff) * (b & 0xffff);
  final high =
      ((a >>> 16) & 0xffff) * (b & 0xffff) +
      (a & 0xffff) * ((b >>> 16) & 0xffff);
  return (low + ((high & 0xffff) << 16)) & 0xffffffff;
}

double Function() _randomSource(int seed) {
  var state = seed & 0xffffffff;
  return () {
    state = (state + 0x6d2b79f5) & 0xffffffff;
    var value = state;
    value = _imul(value ^ (value >>> 15), value | 1);
    value ^= (value + _imul(value ^ (value >>> 7), value | 61)) & 0xffffffff;
    return ((value ^ (value >>> 14)) & 0xffffffff) / 4294967296;
  };
}

typedef _Counts = ({int white, int black, bool whiteKing, bool blackKing});

_Counts _counts(Board board) {
  var white = 0, black = 0;
  var whiteKing = false, blackKing = false;
  for (final piece in board) {
    if (piece > 0) {
      white++;
      whiteKing = whiteKing || piece == 2;
    } else if (piece < 0) {
      black++;
      blackKing = blackKing || piece == -2;
    }
  }
  return (
    white: white,
    black: black,
    whiteKing: whiteKing,
    blackKing: blackKing,
  );
}

Board _nextBoard(Board board, DamaMove move) {
  final next = previewMove(board, move, move.path.length);
  final destination = move.path.last;
  if (next[destination] == 1 && destination < 8) {
    next[destination] = 2;
  } else if (next[destination] == -1 && destination >= 56) {
    next[destination] = -2;
  }
  return next;
}

int? _terminal(
  _Counts count,
  PlayerColor color,
  List<DamaMove> moves,
  int ply,
) {
  final mine = color == PlayerColor.white ? count.white : count.black;
  final theirs = color == PlayerColor.white ? count.black : count.white;
  if (mine == 0 && theirs == 0) return 0;
  if (mine == 0) return -_mate + ply;
  if (theirs == 0) return _mate - ply;
  if (moves.isEmpty) return -_mate + ply;
  if (mine == 1 && theirs == 1) {
    if (count.whiteKing == count.blackKing) return 0;
    final winner = count.whiteKing ? PlayerColor.white : PlayerColor.black;
    return winner == color ? _mate - ply : -_mate + ply;
  }
  return null;
}

int _evaluate(Board board, PlayerColor color, int mobility) {
  var whiteScore = 0.0;
  for (var square = 0; square < 64; square++) {
    final piece = board[square];
    if (piece == 0) continue;
    final sign = piece > 0 ? 1 : -1;
    final row = square ~/ 8, col = square % 8;
    final center = 3.5 - (3.5 - col).abs();
    var value = piece.abs() == 2 ? 350.0 : 100.0;
    value += center * (piece.abs() == 2 ? 4 : 2);
    if (piece.abs() == 1) {
      value += (piece > 0 ? 7 - row : row) * 5;
      if (col > 0 && board[square - 1].sign == sign) value += 4;
      if (col < 7 && board[square + 1].sign == sign) value += 4;
      final behind = square + (piece > 0 ? 8 : -8);
      if (behind >= 0 && behind < 64 && board[behind].sign == sign) value += 3;
    } else {
      value += (3.5 - (3.5 - row).abs()) * 3;
      for (final (dr, dc) in const [(-1, 0), (1, 0), (0, -1), (0, 1)]) {
        var r = row + dr, c = col + dc;
        while (r >= 0 && r < 8 && c >= 0 && c < 8 && board[r * 8 + c] == 0) {
          value += 1.3;
          r += dr;
          c += dc;
        }
      }
    }
    whiteScore += sign * value;
  }
  // Dart round() differs from JS Math.round() on negative half-integers.
  return ((color == PlayerColor.white ? whiteScore : -whiteScore) +
          math.min(mobility, 32) * .7 +
          .5)
      .floor();
}

double _rankMove(Board board, DamaMove move) {
  final piece = board[move.from], destination = move.path.last;
  var score =
      move.captures
          .fold<int>(
            0,
            (total, square) => total + (board[square].abs() == 2 ? 350 : 100),
          )
          .toDouble() *
      10;
  if ((piece == 1 && destination < 8) || (piece == -1 && destination >= 56)) {
    score += 700;
  }
  final fromRow = move.from ~/ 8, toRow = destination ~/ 8;
  if (piece.abs() == 1) {
    score += (piece > 0 ? fromRow - toRow : toRow - fromRow) * 7;
  }
  return score + (3.5 - (3.5 - destination % 8).abs()) * 2;
}

enum _Bound { exact, lower, upper }

class _Entry {
  const _Entry(this.depth, this.score, this.bound, this.best);
  final int depth;
  final double score;
  final _Bound bound;
  final String best;
}

/// Chooses a complete legal turn using the same heuristic search as the web bot.
/// Easy intentionally varies and weakens play. Medium and hard use completed
/// iterative-deepening alpha-beta searches with transpositions and bounded
/// capture extensions; they are heuristic opponents, not solved play.
///
/// Time checks are cooperative between calls into legal move generation. Run
/// this function in a background isolate. A stopped search retains its last
/// completed iteration and always has a legal fallback. Repetition from earlier
/// game history remains the responsibility of [playMove].
BotAnalysis chooseBotMove(
  Board board,
  PlayerColor color,
  BotLevel level, {
  int? timeMs,
  int? seed,
}) {
  final config = _settings(level);
  final clock = Stopwatch()..start();
  final budgetMicros = (timeMs ?? config.timeMs).clamp(0, 2000) * 1000;
  final random = _randomSource(seed ?? math.Random().nextInt(0x100000000));
  final rootMoves = legalMoves(board, color);
  final ended = _terminal(_counts(board), color, rootMoves, 0);
  if (ended != null) {
    return BotAnalysis(move: null, score: ended, depth: 0, nodes: 1);
  }

  final priorities = {for (final move in rootMoves) _moveKey(move): random()};
  List<DamaMove> ordered(
    Board position,
    List<DamaMove> moves, {
    String? preferred,
    bool root = false,
  }) {
    final ranked = <({DamaMove move, double rank, int index})>[];
    for (var i = 0; i < moves.length; i++) {
      final move = moves[i], key = _moveKey(moves[i]);
      ranked.add((
        move: move,
        rank:
            (key == preferred ? 1000000.0 : 0.0) +
            _rankMove(position, move) +
            (root ? priorities[key] ?? 0 : 0),
        index: i,
      ));
    }
    ranked.sort((a, b) {
      final rank = b.rank.compareTo(a.rank);
      return rank == 0 ? a.index.compareTo(b.index) : rank;
    });
    return ranked.map((entry) => entry.move).toList();
  }

  var rootOrder = ordered(board, rootMoves, root: true);
  var chosen = level == BotLevel.easy && random() < .8
      ? rootMoves[(random() * rootMoves.length).floor()]
      : rootOrder.first;
  final fallbackBoard = _nextBoard(board, chosen);
  final fallbackMoves = legalMoves(fallbackBoard, opposite(color));
  var bestScore =
      -(_terminal(_counts(fallbackBoard), opposite(color), fallbackMoves, 1) ??
          _evaluate(fallbackBoard, opposite(color), fallbackMoves.length));
  var nodes = 2, completedDepth = 0;
  if (level == BotLevel.easy || rootMoves.length == 1) {
    return BotAnalysis(move: chosen, score: bestScore, depth: 1, nodes: nodes);
  }

  final table = <String, _Entry>{};
  void visit() {
    if (nodes >= config.nodes || clock.elapsedMicroseconds >= budgetMicros) {
      throw _stop;
    }
    nodes++;
  }

  double toTable(double score, int ply) => score > _mateThreshold
      ? score + ply
      : score < -_mateThreshold
      ? score - ply
      : score;
  double fromTable(double score, int ply) => score > _mateThreshold
      ? score - ply
      : score < -_mateThreshold
      ? score + ply
      : score;

  double search(
    Board position,
    PlayerColor turn,
    int depth,
    double alpha,
    double beta,
    int ply,
    int extensions,
  ) {
    visit();
    final moves = legalMoves(position, turn);
    final end = _terminal(_counts(position), turn, moves, ply);
    if (end != null) return end.toDouble();
    final extending =
        depth <= 0 && extensions > 0 && moves.first.captures.isNotEmpty;
    if (depth <= 0 && !extending) {
      return _evaluate(position, turn, moves.length).toDouble();
    }
    final key = depth > 0 ? _boardKey(position, turn) : '';
    final cached = key.isNotEmpty ? table[key] : null;
    if (cached != null && cached.depth >= depth) {
      final score = fromTable(cached.score, ply);
      if (cached.bound == _Bound.exact) return score;
      if (cached.bound == _Bound.lower) {
        alpha = math.max(alpha, score);
      } else {
        beta = math.min(beta, score);
      }
      if (alpha >= beta) return score;
    }
    final originalAlpha = alpha, originalBeta = beta;
    var value = double.negativeInfinity;
    var best = '';
    for (final move in ordered(position, moves, preferred: cached?.best)) {
      final score = -search(
        _nextBoard(position, move),
        opposite(turn),
        math.max(0, depth - 1),
        -beta,
        -alpha,
        ply + 1,
        extending ? extensions - 1 : extensions,
      );
      if (score > value) {
        value = score;
        best = _moveKey(move);
      }
      alpha = math.max(alpha, score);
      if (alpha >= beta) break;
    }
    if (key.isNotEmpty && table.length < 25000) {
      table[key] = _Entry(
        depth,
        toTable(value, ply),
        value <= originalAlpha
            ? _Bound.upper
            : value >= originalBeta
            ? _Bound.lower
            : _Bound.exact,
        best,
      );
    }
    return value;
  }

  for (var depth = 1; depth <= config.depth; depth++) {
    var iterationMove = rootOrder.first;
    var iterationScore = double.negativeInfinity;
    var alpha = double.negativeInfinity;
    try {
      for (final move in rootOrder) {
        final score = -search(
          _nextBoard(board, move),
          opposite(color),
          depth - 1,
          double.negativeInfinity,
          -alpha,
          1,
          config.extensions,
        );
        if (score > iterationScore) {
          iterationScore = score;
          iterationMove = move;
        }
        alpha = math.max(alpha, score);
      }
    } catch (error) {
      if (!identical(error, _stop)) rethrow;
      break;
    }
    chosen = iterationMove;
    bestScore = iterationScore.toInt();
    completedDepth = depth;
    rootOrder = ordered(
      board,
      rootMoves,
      preferred: _moveKey(chosen),
      root: true,
    );
    if (bestScore > _mateThreshold) break;
  }
  return BotAnalysis(
    move: chosen,
    score: bestScore,
    depth: completedDepth,
    nodes: nodes,
  );
}

/// Top-level, isolate-sendable entry point for `compute(analyzeBot, request)`.
/// Payload: board, color, level; optional integer timeMs and seed.
BotAnalysis analyzeBot(Map<String, dynamic> request) => chooseBotMove(
  (request['board'] as List).map((piece) => (piece as num).toInt()).toList(),
  playerColorFromName(request['color'] as String),
  BotLevel.values.byName(request['level'] as String),
  timeMs: (request['timeMs'] as num?)?.toInt(),
  seed: (request['seed'] as num?)?.toInt(),
);
